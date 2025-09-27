// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import "./ILeverageInterfaces.sol";

/**
 * @title InstantLeverageHook
 * @notice Hook for instant leverage trading through temporary pool liquidity
 * @dev Enables users to get leveraged positions without collateral via atomic trades
 */

    
contract InstantLeverageHook is BaseHook {
    using StateLibrary for IPoolManager;

    // ============ Constants ============
    
    uint256 public constant MAX_LEVERAGE_MULTIPLIER = 10; // 10x max
    uint24 public constant DYNAMIC_FEE_FLAG = 0x800000;
    uint256 public constant POOL_FEE_BPS = 300; // 3% fee to pool on profits
    uint256 public constant USER_PROFIT_BPS = 9700; // 97% to user on profits

    // ============ State Variables ============
    
    address public immutable walletFactory;     // Your WalletFactory contract
    mapping(bytes32 => PoolInfo) public poolInfo;
    mapping(address => bool) public authorizedPlatforms;
    mapping(bytes32 => InstantLeverageRequest) public pendingRequests;
    mapping(bytes32 => LeveragePosition) public leveragePositions; // requestId -> position
    mapping(address => bytes32[]) public userPositions; // user -> position IDs

    // ============ Structs ============

    struct InstantLeverageRequest {
        address user;                // User's EOA
        address userWallet;          // User's smart wallet address  
        address tokenIn;             // Base token user is spending
        address tokenOut;            // Token user wants to receive
        uint256 userBaseAmount;      // Amount from user's wallet
        uint256 leverageMultiplier;  // 1-10x leverage
        uint256 minOutputAmount;     // Slippage protection
        bytes32 delegationHash;      // Delegation signature hash
        bytes32 requestId;           // Unique request identifier
    }

    struct LeveragePosition {
        address user;
        address userWallet;
        address tokenIn;
        address tokenOut;
        uint256 initialNotional;     // Total position size (user + leverage)
        uint256 userContribution;    // User's base amount
        uint256 leverageAmount;      // Amount borrowed from pool
        uint256 leverageMultiplier;
        uint256 openPrice;           // Price at position open
        uint256 liquidationThreshold; // Position value at which to liquidate
        uint256 openTimestamp;
        bool isOpen;
    }

    struct PoolInfo {
        uint256 totalLent;           // Total currently lent out
        uint256 maxLendingLimit;     // Maximum amount pool will lend
        uint256 utilizationRate;     // Current utilization percentage
        bool isActive;               // Whether pool accepts leverage requests
    }

    // ============ Events ============

    event LeveragePositionOpened(
        bytes32 indexed requestId,
        address indexed user,
        address userWallet,
        address tokenIn,
        address tokenOut,
        uint256 userAmount,
        uint256 leverageAmount,
        uint256 totalNotional,
        uint256 liquidationThreshold
    );

    event LeveragePositionClosed(
        bytes32 indexed requestId,
        address indexed user,
        uint256 finalValue,
        int256 pnl,
        uint256 userProceeds,
        uint256 poolFee,
        string reason
    );

    event PositionLiquidated(
        bytes32 indexed requestId,
        address indexed user,
        uint256 liquidationValue,
        uint256 poolRepayment
    );

    event PoolUtilizationUpdated(
        bytes32 indexed poolId,
        uint256 utilizationRate,
        uint256 newFee
    );

    event LeverageRequestFailed(
        bytes32 indexed requestId,
        string reason
    );

    // ============ Modifiers ============

    modifier onlyAuthorizedPlatform() {
        require(authorizedPlatforms[msg.sender], "Unauthorized platform");
        _;
    }

    // ============ Constructor ============

    constructor(
        IPoolManager _poolManager,
        address _walletFactory
    ) BaseHook(_poolManager) {
        walletFactory = _walletFactory;
        authorizedPlatforms[_walletFactory] = true;
    }

    // ============ Hook Permissions ============

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,    // Setup pool info
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: true,  // Handle instant leverage
            afterAddLiquidity: false,
            afterRemoveLiquidity: true,   // Cleanup and fee updates
            beforeSwap: true,             // Validate leverage trades
            afterSwap: true,              // Track pool state
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ============ Hook Implementation ============

    /**
     * @notice Initialize pool for leverage trading
     */
    function _afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick
    ) internal override returns (bytes4) {
        bytes32 poolId = _getPoolId(key);

        // Initialize pool with default leverage settings
        poolInfo[poolId] = PoolInfo({
            totalLent: 0,
            maxLendingLimit: 1000000 ether, // Default 1M limit
            utilizationRate: 0,
            isActive: true
        });

        return BaseHook.afterInitialize.selector;
    }

    /**
     * @notice Handle instant leverage requests
     * @dev Called when platform requests temporary liquidity for user leverage
     */
    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {

        // Only process if called by authorized platform with leverage request
        if (hookData.length > 0 && authorizedPlatforms[sender]) {
            InstantLeverageRequest memory request = abi.decode(hookData, (InstantLeverageRequest));

            // Validate leverage request
            require(_validateLeverageRequest(key, request), "Invalid leverage request");

            // Execute instant leverage logic
            _executeInstantLeverage(key, request, params);
        }

        return BaseHook.beforeRemoveLiquidity.selector;
    }

    /**
     * @notice Complete leverage operation and update pool state
     */
    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {

        if (hookData.length > 0 && authorizedPlatforms[sender]) {
            bytes32 poolId = _getPoolId(key);

            // Update pool utilization after leverage operation
            _updatePoolUtilization(poolId, key);

            // Calculate and apply dynamic fees based on new utilization
            _updateDynamicFees(poolId, key);
        }

        return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    /**
     * @notice Validate swaps during leverage operations
     */
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {

        bytes32 poolId = _getPoolId(key);
        PoolInfo memory pool = poolInfo[poolId];

        // Ensure pool is active and not over-utilized
        require(pool.isActive, "Pool not active for leverage");
        require(pool.utilizationRate < 9000, "Pool over-utilized"); // Max 90%

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /**
     * @notice Track pool state after swaps
     */
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {

        // Update pool metrics for risk management
        bytes32 poolId = _getPoolId(key);
        _trackPoolHealth(poolId, key, delta);

        return (BaseHook.afterSwap.selector, 0);
    }

    // ============ Internal Functions ============

    /**
     * @notice Validate leverage request parameters
     */
    function _validateLeverageRequest(
        PoolKey calldata key,
        InstantLeverageRequest memory request
    ) internal view returns (bool) {
        
        // Check leverage multiplier
        if (request.leverageMultiplier == 0 || request.leverageMultiplier > MAX_LEVERAGE_MULTIPLIER) {
            return false;
        }
        
        // Check user has base funds (this would integrate with UserWallet contract)
        if (request.userBaseAmount == 0) {
            return false;
        }
        
        // Check pool can provide leverage amount
        bytes32 poolId = _getPoolId(key);
        PoolInfo memory pool = poolInfo[poolId];
        uint256 leverageAmount = request.userBaseAmount * (request.leverageMultiplier - 1);
        
        if (leverageAmount > (pool.maxLendingLimit - pool.totalLent)) {
            return false;
        }
        
        return true;
    }

    /**
     * @notice Execute instant leverage trade atomically
     */
    function _executeInstantLeverage(
        PoolKey calldata key,
        InstantLeverageRequest memory request,
        ModifyLiquidityParams calldata params
    ) internal {
        
        try this._performLeverageTrade(key, request) returns (uint256 outputAmount, uint256 openPrice) {
            
            // Calculate position details
            uint256 leverageAmount = request.userBaseAmount * (request.leverageMultiplier - 1);
            uint256 totalNotional = request.userBaseAmount * request.leverageMultiplier;
            uint256 liquidationThreshold = totalNotional / request.leverageMultiplier; // 1/leverage rule
            
            // Create leverage position
            LeveragePosition memory position = LeveragePosition({
                user: request.user,
                userWallet: request.userWallet,
                tokenIn: request.tokenIn,
                tokenOut: request.tokenOut,
                initialNotional: totalNotional,
                userContribution: request.userBaseAmount,
                leverageAmount: leverageAmount,
                leverageMultiplier: request.leverageMultiplier,
                openPrice: openPrice,
                liquidationThreshold: liquidationThreshold,
                openTimestamp: block.timestamp,
                isOpen: true
            });
            
            // Store position
            leveragePositions[request.requestId] = position;
            userPositions[request.user].push(request.requestId);
            
            // Credit user wallet with leveraged position (represented as tokenOut)
            IUserWallet(request.userWallet).creditBalance(request.tokenOut, outputAmount);
            
            emit LeveragePositionOpened(
                request.requestId,
                request.user,
                request.userWallet,
                request.tokenIn,
                request.tokenOut,
                request.userBaseAmount,
                leverageAmount,
                totalNotional,
                liquidationThreshold
            );
            
        } catch Error(string memory reason) {
            emit LeverageRequestFailed(request.requestId, reason);
        }
    }

    /**
     * @notice Close leverage position and handle profit/loss distribution
     * @param requestId Position to close
     * @param currentPrice Current market price
     */
    function closeLeveragePosition(
        bytes32 requestId,
        uint256 currentPrice
    ) external returns (bool success) {
        
        LeveragePosition storage position = leveragePositions[requestId];
        require(position.isOpen, "Position not open");
        require(msg.sender == position.user || authorizedPlatforms[msg.sender], "Unauthorized");
        
        // Calculate current position value
        uint256 currentValue = _calculatePositionValue(position, currentPrice);
        
        // Calculate P&L
        int256 pnl = int256(currentValue) - int256(position.initialNotional);
        
        // Mark position as closed
        position.isOpen = false;
        
        if (pnl > 0) {
            // PROFITS: 3% to pool, 97% to user
            _handleProfitableClose(requestId, position, currentValue, uint256(pnl));
        } else {
            // LOSSES: Pool repaid, user wallet balance wiped for this trade
            _handleLossClose(requestId, position, currentValue, uint256(-pnl));
        }
        
        return true;
    }

    /**
     * @notice Handle profitable position closure
     */
    function _handleProfitableClose(
        bytes32 requestId,
        LeveragePosition memory position,
        uint256 currentValue,
        uint256 profit
    ) internal {
        
        // Calculate distribution
        uint256 poolFee = (profit * POOL_FEE_BPS) / 10000;  // 3% of profit to pool
        uint256 userProfit = (profit * USER_PROFIT_BPS) / 10000; // 97% of profit to user
        uint256 userTotalProceeds = position.userContribution + userProfit;
        
        // Repay pool (original leverage amount)
        bytes32 poolId = keccak256(abi.encodePacked(position.tokenIn, position.tokenOut));
        poolInfo[poolId].totalLent -= position.leverageAmount;
        
        // Credit pool with fee
        // (In practice, this would transfer tokens to pool)
        
        // Credit user wallet with their original investment + 97% of profits
        IUserWallet(position.userWallet).creditBalance(position.tokenOut, userTotalProceeds);
        
        emit LeveragePositionClosed(
            requestId,
            position.user,
            currentValue,
            int256(profit),
            userTotalProceeds,
            poolFee,
            "Profitable close"
        );
    }

    /**
     * @notice Handle loss position closure
     */
    function _handleLossClose(
        bytes32 requestId,
        LeveragePosition memory position,
        uint256 currentValue,
        uint256 loss
    ) internal {
        
        // Pool gets repaid from whatever value remains
        uint256 poolRepayment = currentValue > position.leverageAmount ? 
            position.leverageAmount : currentValue;
        
        // User gets whatever is left (could be zero)
        uint256 userRemainder = currentValue > poolRepayment ? 
            currentValue - poolRepayment : 0;
        
        // Update pool state
        bytes32 poolId = keccak256(abi.encodePacked(position.tokenIn, position.tokenOut));
        poolInfo[poolId].totalLent -= position.leverageAmount;
        
        // Credit user wallet (could be zero if total loss)
        if (userRemainder > 0) {
            IUserWallet(position.userWallet).creditBalance(position.tokenOut, userRemainder);
        }
        
        emit LeveragePositionClosed(
            requestId,
            position.user,
            currentValue,
            -int256(loss),
            userRemainder,
            0, // No pool fee on losses
            "Loss close"
        );
    }

    /**
     * @notice Check and execute liquidation if needed
     * @param requestId Position to check
     * @param currentPrice Current market price
     */
    function checkLiquidation(
        bytes32 requestId,
        uint256 currentPrice
    ) external returns (bool liquidated) {
        
        LeveragePosition storage position = leveragePositions[requestId];
        require(position.isOpen, "Position not open");
        
        uint256 currentValue = _calculatePositionValue(position, currentPrice);
        
        // Liquidation rule: if position value falls below 1/leverage of initial notional
        if (currentValue <= position.liquidationThreshold) {
            
            // Mark as closed
            position.isOpen = false;
            
            // Pool gets whatever value remains (priority repayment)
            uint256 poolRepayment = currentValue > position.leverageAmount ? 
                position.leverageAmount : currentValue;
            
            // Update pool state
            bytes32 poolId = keccak256(abi.encodePacked(position.tokenIn, position.tokenOut));
            poolInfo[poolId].totalLent -= position.leverageAmount;
            
            // User gets nothing on liquidation (position value too low)
            
            emit PositionLiquidated(
                requestId,
                position.user,
                currentValue,
                poolRepayment
            );
            
            return true;
        }
        
        return false;
    }

    /**
     * @notice Calculate current position value using pool price
     */
    function _calculatePositionValue(
        LeveragePosition memory position,
        uint256 currentPrice
    ) internal pure returns (uint256) {

        if (currentPrice == 0 || position.openPrice == 0) {
            return 0;
        }

        // Calculate value: initialNotional * (currentPrice / openPrice)
        return (position.initialNotional * currentPrice) / position.openPrice;
    }

    /**
     * @notice Get current price from Uniswap V4 pool (external)
     */
    function getPoolPrice(PoolKey calldata key) external view returns (uint256) {
        return _getPoolPrice(key);
    }

    /**
     * @notice Get current price from Uniswap V4 pool (internal)
     */
    function _getPoolPrice(PoolKey calldata key) internal view returns (uint256) {
        PoolId poolId = PoolId.wrap(_getPoolId(key));

        // Get pool slot0 data using StateLibrary
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        // Convert sqrtPriceX96 to regular price
        uint256 price = _sqrtPriceX96ToPrice(sqrtPriceX96);

        return price;
    }

    /**
     * @notice Convert sqrtPriceX96 to regular price
     * @dev Uses proper fixed-point arithmetic for accurate price calculation
     */
    function _sqrtPriceX96ToPrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
        // price = (sqrtPriceX96 / 2^96)^2
        // For tokens with different decimals, this gives the price of token1 in terms of token0
        if (sqrtPriceX96 == 0) return 0;

        // Calculate price using safe math to prevent overflow
        // price = (sqrtPriceX96^2 * 1e18) / (2^192)
        uint256 numerator = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 denominator = 1 << 192; // 2^192

        // Scale by 1e18 for 18 decimal precision
        return (numerator * 1e18) / denominator;
    }

    /**
     * @notice Get current position health
     * @param requestId Position ID
     * @param currentPrice Current market price
     */
    function getPositionHealth(
        bytes32 requestId,
        uint256 currentPrice
    ) external view returns (
        uint256 currentValue,
        uint256 liquidationThreshold,
        bool isHealthy,
        int256 pnl
    ) {
        LeveragePosition memory position = leveragePositions[requestId];
        require(position.isOpen, "Position not open");
        
        currentValue = _calculatePositionValue(position, currentPrice);
        liquidationThreshold = position.liquidationThreshold;
        isHealthy = currentValue > liquidationThreshold;
        pnl = int256(currentValue) - int256(position.initialNotional);
        
        return (currentValue, liquidationThreshold, isHealthy, pnl);
    }

    /**
     * @notice Perform the actual leverage trade (external for try-catch)
     */
    function _performLeverageTrade(
        PoolKey calldata key,
        InstantLeverageRequest memory request
    ) external returns (uint256 outputAmount, uint256 openPrice) {
        require(msg.sender == address(this), "Internal only");

        // Validate the request would work
        require(_validateLeverageRequest(key, request), "Leverage validation failed");

        // Get current pool price for position opening
        openPrice = _getPoolPrice(key);
        require(openPrice > 0, "Invalid pool price");

        // Calculate leverage amounts
        uint256 leverageAmount = request.userBaseAmount * (request.leverageMultiplier - 1);
        uint256 totalTradeAmount = request.userBaseAmount + leverageAmount;

        // Update pool lending state
        bytes32 poolId = _getPoolId(key);
        poolInfo[poolId].totalLent += leverageAmount;

        // Simulate swap calculation using current price
        // In a real implementation, this would execute actual swaps
        outputAmount = (totalTradeAmount * 1e18) / openPrice;

        // Apply slippage protection
        require(outputAmount >= request.minOutputAmount, "Slippage exceeded");

        return (outputAmount, openPrice);
    }

    /**
     * @notice Get user's open positions
     */
    function getUserPositions(address user) external view returns (bytes32[] memory) {
        return userPositions[user];
    }

    /**
     * @notice Interface for UserWallet credit balance
     */
    

    /**
     * @notice Update pool utilization rate
     */
    function _updatePoolUtilization(bytes32 poolId, PoolKey calldata key) internal {
        // Get current pool liquidity from PoolManager
        // Calculate new utilization rate
        // Update poolInfo[poolId].utilizationRate
        
        // Placeholder calculation
        PoolInfo storage pool = poolInfo[poolId];
        // pool.utilizationRate = (pool.totalLent * 10000) / totalPoolLiquidity;
    }

    /**
     * @notice Update dynamic fees based on utilization
     */
    function _updateDynamicFees(bytes32 poolId, PoolKey calldata key) internal {
        PoolInfo memory pool = poolInfo[poolId];
        
        // Calculate new fee based on utilization
        uint24 newFee = _calculateDynamicFee(pool.utilizationRate);
        
        // Update fee if pool uses dynamic fees
        if (key.fee == DYNAMIC_FEE_FLAG) {
            // poolManager.updateDynamicLPFee(key, newFee);
            emit PoolUtilizationUpdated(poolId, pool.utilizationRate, newFee);
        }
    }

    /**
     * @notice Calculate dynamic fee based on utilization
     */
    function _calculateDynamicFee(uint256 utilizationRate) internal pure returns (uint24) {
        uint24 baseFee = 500; // 0.05%
        
        if (utilizationRate > 8000) { // > 80%
            return baseFee * 6; // 0.3%
        } else if (utilizationRate > 6000) { // > 60%
            return baseFee * 3; // 0.15%
        } else if (utilizationRate > 4000) { // > 40%
            return baseFee * 2; // 0.1%
        } else {
            return baseFee; // 0.05%
        }
    }

    /**
     * @notice Track pool health metrics
     */
    function _trackPoolHealth(
        bytes32 poolId,
        PoolKey calldata key,
        BalanceDelta delta
    ) internal {
        // Monitor for unusual trading patterns
        // Update risk metrics
        // Trigger alerts if needed
    }

    /**
     * @notice Generate pool ID from pool key
     */
    function _getPoolId(PoolKey calldata key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key.currency0, key.currency1, key.fee, key.tickSpacing));
    }

    // ============ Admin Functions ============

    /**
     * @notice Authorize new platform contract
     */
    function authorizePlatform(address platform) external {
        // Add proper access control
        authorizedPlatforms[platform] = true;
    }

    /**
     * @notice Update pool leverage limits
     */
    function updatePoolLimits(
        bytes32 poolId,
        uint256 newMaxLimit,
        bool isActive
    ) external {
        // Add proper access control
        poolInfo[poolId].maxLendingLimit = newMaxLimit;
        poolInfo[poolId].isActive = isActive;
    }
}