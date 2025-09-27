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
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ILeverageInterfaces.sol";

/**
 * @title InstantLeverageHook
 * @notice Uniswap V4 hook for atomic leverage trading execution
 * @dev Enables borrowing from pools, executing leveraged trades, and immediate repayment
 */

contract InstantLeverageHook is BaseHook, Ownable, ReentrancyGuard {
    using StateLibrary for IPoolManager;
    using SafeERC20 for IERC20;

    // ============ Constants ============
    uint256 public constant MAX_LEVERAGE_MULTIPLIER = 10;
    uint256 public constant POOL_FEE_BPS = 300; // 3% pool fee
    uint256 public constant USER_PROFIT_BPS = 9700; // 97% to user

    // ============ State Variables ============
    IWalletFactory public immutable walletFactory;
    ILeverageController public leverageController;
    address public poolFeeRecipient;

    mapping(address => bool) public authorizedPlatforms;
    mapping(bytes32 => IInstantLeverageHook.LeveragePosition) public leveragePositions;
    mapping(address => bytes32[]) public userPositions;
    mapping(bytes32 => uint256) public outputTokenHoldings;

    // Pool lending info
    struct PoolInfo {
        uint256 totalLent;
        uint256 maxLendingLimit;
        uint256 utilizationRate;
        bool isActive;
    }
    mapping(bytes32 => PoolInfo) public poolInfo;

    // ============ Events ============
    event LeveragePositionOpened(
        bytes32 indexed requestId,
        address indexed user,
        address tokenOut,
        uint256 outputAmount,
        uint256 openPrice
    );

    event LeveragePositionClosed(
        bytes32 indexed requestId,
        address indexed user,
        uint256 finalValue
    );

    event LiquidationExecuted(
        bytes32 indexed requestId,
        address indexed user,
        uint256 liquidationPrice
    );

    // ============ Modifiers ============
    modifier onlyAuthorizedPlatform() {
        require(authorizedPlatforms[msg.sender], "Unauthorized platform");
        _;
    }

    modifier onlyLeverageController() {
        require(msg.sender == address(leverageController), "Only leverage controller");
        _;
    }

    // ============ Constructor ============
    constructor(
    IPoolManager _poolManager,
    address _walletFactory,
    address _leverageController,
    address _poolFeeRecipient
) BaseHook(_poolManager) Ownable(_poolFeeRecipient) ReentrancyGuard() {
    walletFactory = IWalletFactory(_walletFactory);
    leverageController = ILeverageController(_leverageController);
    poolFeeRecipient = _poolFeeRecipient;
    authorizedPlatforms[_walletFactory] = true;
    authorizedPlatforms[_leverageController] = true;
}

    // ============ Hook Permissions ============
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ============ Hook Functions ============
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal
        virtual override
        returns (bytes4, BeforeSwapDelta, uint24) {
        if (hookData.length > 0 && authorizedPlatforms[sender]) {
            InstantLeverageRequest memory request = abi.decode(hookData, (InstantLeverageRequest));
            _handleLeverageRequest(key, request);
        }
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // ============ Core Leverage Functions ============

    /**
     * @notice Execute leverage trade atomically
     * @param poolKey The pool to trade on and borrow from
     * @param request The leverage request parameters
     */
    function executeLeverageTrade(
        PoolKey calldata poolKey,
        InstantLeverageRequest memory request
    ) external onlyLeverageController nonReentrant returns (uint256 outputAmount, uint256 openPrice) {
        require(_validateLeverageRequest(poolKey, request), "Invalid leverage request");

        // Get current pool price
        openPrice = _getPoolPrice(poolKey);
        require(openPrice > 0, "Invalid pool price");

        // Calculate leverage amounts
        uint256 leverageAmount = request.userBaseAmount * (request.leverageMultiplier - 1);
        uint256 totalTradeAmount = request.userBaseAmount + leverageAmount;

        // Transfer user funds to hook
        IERC20(request.tokenIn).safeTransferFrom(
            request.userWallet,
            address(this),
            request.userBaseAmount
        );

        // Borrow from pool (remove liquidity temporarily)
        uint256 borrowedAmount = _borrowFromPool(poolKey, request.tokenIn, leverageAmount);
        require(borrowedAmount >= leverageAmount, "Insufficient pool liquidity");

        // Execute the leveraged swap
        outputAmount = _executeSwap(poolKey, request.tokenIn, request.tokenOut, totalTradeAmount);
        require(outputAmount >= request.minOutputAmount, "Slippage exceeded");

        // Repay pool with fees
        uint256 repaymentAmount = leverageAmount + ((leverageAmount * POOL_FEE_BPS) / 10000);
        uint256 repaymentInOutputToken = (repaymentAmount * openPrice) / 1e18;

        require(outputAmount > repaymentInOutputToken, "Insufficient output for repayment");
        _repayPool(poolKey, request.tokenOut, repaymentInOutputToken);

        // Store position
        uint256 finalOutputAmount = outputAmount - repaymentInOutputToken;
        _createPosition(request, finalOutputAmount, openPrice);

        emit LeveragePositionOpened(
            request.requestId,
            request.user,
            request.tokenOut,
            finalOutputAmount,
            openPrice
        );

        return (finalOutputAmount, openPrice);
    }

    /**
     * @notice Handle leverage request during swap
     */
    function _handleLeverageRequest(
        PoolKey memory poolKey,
        InstantLeverageRequest memory request
    ) internal {
        try this.executeLeverageTrade(poolKey, request) returns (uint256 outputAmount, uint256 openPrice) {
            // Success - position created
        } catch {
            // Fail silently for prototype
        }
    }

    /**
     * @notice Validate leverage request parameters
     */
    function _validateLeverageRequest(
        PoolKey calldata poolKey,
        InstantLeverageRequest memory request
    ) internal view returns (bool) {
        // Check leverage multiplier
        if (request.leverageMultiplier == 0 || request.leverageMultiplier > MAX_LEVERAGE_MULTIPLIER) {
            return false;
        }

        // Check user has base funds
        if (request.userBaseAmount == 0) {
            return false;
        }

        // Check pool configuration
        bytes32 poolId = _getPoolId(poolKey);
        PoolInfo memory pool = poolInfo[poolId];
        uint256 leverageAmount = request.userBaseAmount * (request.leverageMultiplier - 1);

        if (leverageAmount > (pool.maxLendingLimit - pool.totalLent)) {
            return false;
        }

        return true;
    }

    /**
     * @notice Borrow tokens from pool by removing liquidity
     */
    function _borrowFromPool(
        PoolKey memory poolKey,
        address token,
        uint256 amount
    ) internal returns (uint256 borrowed) {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -887220,
            tickUpper: 887220,
            liquidityDelta: -int256(amount),
            salt: 0
        });

        (BalanceDelta delta,) = poolManager.modifyLiquidity(poolKey, params, "");
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();
        borrowed = token < Currency.unwrap(poolKey.currency1) ?
            (amount0 < 0 ? uint256(uint128(-amount0)) : uint256(uint128(amount0))) :
            (amount1 < 0 ? uint256(uint128(-amount1)) : uint256(uint128(amount1)));

        // Update pool lending state
        bytes32 poolId = _getPoolId(poolKey);
        poolInfo[poolId].totalLent += borrowed;

        return borrowed;
    }

    /**
     * @notice Repay borrowed tokens to pool
     */
    function _repayPool(
        PoolKey memory poolKey,
        address token,
        uint256 amount
    ) internal {
        // Approve and add liquidity back to pool
        IERC20(token).approve(address(poolManager), amount);

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -887220,
            tickUpper: 887220,
            liquidityDelta: int256(amount),
            salt: 0
        });

        (BalanceDelta repayDelta,) = poolManager.modifyLiquidity(poolKey, params, "");

        // Update pool lending state
        bytes32 poolId = _getPoolId(poolKey);
        if (poolInfo[poolId].totalLent >= amount) {
            poolInfo[poolId].totalLent -= amount;
        } else {
            poolInfo[poolId].totalLent = 0;
        }
    }

    /**
     * @notice Execute swap on the pool
     */
    function _executeSwap(
        PoolKey memory poolKey,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(poolManager), amountIn);

        SwapParams memory swapParams = SwapParams({
            zeroForOne: tokenIn < tokenOut,
            amountSpecified: -int256(amountIn), // Exact input
            sqrtPriceLimitX96: 0
        });

        BalanceDelta delta = poolManager.swap(poolKey, swapParams, "");
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();
        amountOut = tokenIn < tokenOut ?
            (amount1 < 0 ? uint256(uint128(-amount1)) : uint256(uint128(amount1))) :
            (amount0 < 0 ? uint256(uint128(-amount0)) : uint256(uint128(amount0)));

        return amountOut;
    }

    /**
     * @notice Create leverage position
     */
    function _createPosition(
        InstantLeverageRequest memory request,
        uint256 outputAmount,
        uint256 openPrice
    ) internal {
        uint256 leverageAmount = request.userBaseAmount * (request.leverageMultiplier - 1);
        uint256 initialNotional = request.userBaseAmount + leverageAmount;

        IInstantLeverageHook.LeveragePosition memory position = IInstantLeverageHook.LeveragePosition({
            user: request.user,
            userWallet: request.userWallet,
            tokenIn: request.tokenIn,
            tokenOut: request.tokenOut,
            initialNotional: initialNotional,
            userContribution: request.userBaseAmount,
            leverageAmount: leverageAmount,
            leverageMultiplier: request.leverageMultiplier,
            outputTokenAmount: outputAmount,
            openPrice: openPrice,
            liquidationThreshold: initialNotional / request.leverageMultiplier,
            openTimestamp: block.timestamp,
            isOpen: true
        });

        leveragePositions[request.requestId] = position;
        userPositions[request.user].push(request.requestId);
        outputTokenHoldings[request.requestId] = outputAmount;
    }

    // ============ Position Management ============

    /**
     * @notice Close leverage position
     */
    function closeLeveragePosition(
        IInstantLeverageHook.ClosePositionParams calldata params
    ) external nonReentrant returns (bool success) {
        IInstantLeverageHook.LeveragePosition storage position = leveragePositions[params.requestId];
        require(position.isOpen, "Position not open");
        require(
            msg.sender == position.user || authorizedPlatforms[msg.sender],
            "Unauthorized"
        );

        uint256 currentPrice = _getPoolPrice(params.poolKey);
        uint256 currentValue = _calculatePositionValue(position, currentPrice);

        // Swap output tokens back to input tokens
        uint256 inputTokenAmount = _executeSwap(
            params.poolKey,
            position.tokenOut,
            position.tokenIn,
            position.outputTokenAmount
        );

        // Calculate P&L and distribute proceeds
        uint256 leverageRepayment = (position.leverageAmount * currentPrice) / position.openPrice;

        if (inputTokenAmount > leverageRepayment) {
            uint256 profit = inputTokenAmount - leverageRepayment;
            uint256 poolFee = (profit * POOL_FEE_BPS) / 10000;
            uint256 userProceeds = inputTokenAmount - leverageRepayment - poolFee;

            // Transfer proceeds
            IERC20(position.tokenIn).safeTransfer(position.userWallet, userProceeds);
            IERC20(position.tokenIn).safeTransfer(poolFeeRecipient, poolFee);
        } else {
            // Loss scenario - user gets whatever remains after leverage repayment
            uint256 userProceeds = inputTokenAmount > leverageRepayment ?
                inputTokenAmount - leverageRepayment : 0;

            if (userProceeds > 0) {
                IERC20(position.tokenIn).safeTransfer(position.userWallet, userProceeds);
            }
        }

        // Close position
        position.isOpen = false;
        outputTokenHoldings[params.requestId] = 0;

        emit LeveragePositionClosed(params.requestId, position.user, currentValue);
        return true;
    }

    /**
     * @notice Check and execute liquidation if needed
     */
    function checkLiquidation(bytes32 requestId, uint256 currentPrice) external returns (bool) {
        IInstantLeverageHook.LeveragePosition storage position = leveragePositions[requestId];
        require(position.isOpen, "Position not open");

        uint256 currentValue = _calculatePositionValue(position, currentPrice);

        if (currentValue <= position.liquidationThreshold) {
            position.isOpen = false;
            outputTokenHoldings[requestId] = 0;

            emit LiquidationExecuted(requestId, position.user, currentPrice);
            return true;
        }

        return false;
    }

    // ============ View Functions ============

    /**
     * @notice Get current pool price from sqrtPriceX96
     */
    function _getPoolPrice(PoolKey memory key) internal view returns (uint256) {
        PoolId poolId = PoolId.wrap(keccak256(abi.encode(key.currency0, key.currency1, key.fee, key.tickSpacing)));
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        require(sqrtPriceX96 > 0, "Invalid pool price");

        // Convert sqrtPriceX96 to price with 18 decimals
        uint256 price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) >> 192;
        return price > 0 ? price : 1;
    }

    function getPoolPrice(PoolKey calldata key) external view returns (uint256) {
        return _getPoolPrice(key);
    }

    /**
     * @notice Calculate current position value
     */
    function _calculatePositionValue(
        IInstantLeverageHook.LeveragePosition memory position,
        uint256 currentPrice
    ) internal pure returns (uint256) {
        return (position.outputTokenAmount * currentPrice) / position.openPrice;
    }

    /**
     * @notice Get position health metrics
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
        IInstantLeverageHook.LeveragePosition memory position = leveragePositions[requestId];
        require(position.isOpen, "Position not open");

        currentValue = _calculatePositionValue(position, currentPrice);
        liquidationThreshold = position.liquidationThreshold;
        isHealthy = currentValue > liquidationThreshold;
        pnl = int256(currentValue) - int256(position.initialNotional);

        return (currentValue, liquidationThreshold, isHealthy, pnl);
    }

    function getPosition(bytes32 requestId) external view returns (IInstantLeverageHook.LeveragePosition memory) {
        return leveragePositions[requestId];
    }

    function getUserPositions(address user) external view returns (bytes32[] memory) {
        return userPositions[user];
    }

    // ============ Helper Functions ============

    function _getPoolId(PoolKey memory key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key.currency0, key.currency1, key.fee, key.tickSpacing));
    }

    // ============ Admin Functions ============

    function authorizePlatform(address platform) external onlyOwner {
        authorizedPlatforms[platform] = true;
    }

    function setLeverageController(address _leverageController) external onlyOwner {
        leverageController = ILeverageController(_leverageController);
        authorizedPlatforms[_leverageController] = true;
    }

    function setPoolFeeRecipient(address _poolFeeRecipient) external onlyOwner {
        poolFeeRecipient = _poolFeeRecipient;
    }

    function configurePoolLending(
        PoolKey calldata poolKey,
        uint256 maxLendingLimit,
        bool isActive
    ) external onlyOwner {
        bytes32 poolId = _getPoolId(poolKey);
        poolInfo[poolId] = PoolInfo({
            totalLent: poolInfo[poolId].totalLent,
            maxLendingLimit: maxLendingLimit,
            utilizationRate: 0,
            isActive: isActive
        });
    }
}