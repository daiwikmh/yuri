// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./ILeverageInterfaces.sol";



/**
 * @title LeverageController
 * @notice Main controller that orchestrates leverage trading between WalletFactory, UserWallet, and InstantLeverageHook
 * @dev Handles trade requests, position management, and profit/loss distribution
 */
contract LeverageController is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ============ Interfaces ============
    
  
    // ============ State Variables ============
    
    IPoolManager public immutable poolManager;
    IWalletFactory public immutable walletFactory;
    IInstantLeverageHook public immutable leverageHook;
    
    uint256 public nextRequestId = 1;
    mapping(bytes32 => TradeRequest) public tradeRequests;
    mapping(bytes32 => bool) public executedTrades;
    
    // Pool and platform configuration
    mapping(bytes32 => PoolConfig) public poolConfigs;
    mapping(address => address) public priceOracles; // token -> oracle
    
    uint256 public maxLeverageGlobal = 10;
    bool public emergencyPaused;
    address public priceOracleManager;

    // ============ Structs ============
    
    struct TradeRequest {
        address user;
        address userWallet;
        address tokenIn;
        address tokenOut;
        uint256 baseAmount;
        uint256 leverageMultiplier;
        uint256 minOutputAmount;
        bytes32 delegationHash;
        uint256 deadline;
        uint256 requestTimestamp;
        bool executed;
    }
    
    struct PoolConfig {
        bool active;
        uint256 maxLeverageForPool;
        uint256 maxUtilization; // basis points (9000 = 90%)
        uint256 baseFeeRate;     // basis points
    }

    // ============ Events ============
    
    event TradeRequested(
        bytes32 indexed requestId,
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 baseAmount,
        uint256 leverage,
        uint256 deadline
    );
    
    event TradeExecuted(
        bytes32 indexed requestId,
        address indexed user,
        uint256 outputAmount,
        uint256 openPrice
    );
    
    event PositionClosed(
        bytes32 indexed requestId,
        address indexed user,
        uint256 finalValue,
        int256 pnl,
        uint256 userProceeds
    );
    
    event PositionLiquidated(
        bytes32 indexed requestId,
        address indexed user,
        uint256 liquidationValue
    );
    
    event PoolConfigured(
        bytes32 indexed poolId,
        bool active,
        uint256 maxLeverage
    );

    // ============ Modifiers ============
    
    modifier notPaused() {
        require(!emergencyPaused, "Controller: Emergency paused");
        _;
    }
    
    modifier validPool(PoolKey calldata poolKey) {
        bytes32 poolId = _getPoolId(poolKey);
        require(poolConfigs[poolId].active, "Controller: Pool not active");
        _;
    }
    
    modifier onlyPriceOracle() {
        require(msg.sender == priceOracleManager, "Controller: Only price oracle");
        _;
    }

    // ============ Constructor ============
    
    constructor(
        address _poolManager,
        address _walletFactory,
        address _leverageHook
    ) Ownable(msg.sender) {
        poolManager = IPoolManager(_poolManager);
        walletFactory = IWalletFactory(_walletFactory);
        leverageHook = IInstantLeverageHook(_leverageHook);
    }

    // ============ Core Trading Functions ============
    
    /**
     * @notice Request a leverage trade
     */
    function requestLeverageTrade(
        PoolKey calldata poolKey,
        address tokenIn,
        address tokenOut,
        uint256 baseAmount,
        uint256 leverageMultiplier,
        uint256 minOutputAmount,
        bytes32 delegationHash,
        uint256 deadline
    ) external notPaused validPool(poolKey) returns (bytes32 requestId) {
        
        // Validate basic parameters
        require(block.timestamp <= deadline, "Controller: Deadline passed");
        require(leverageMultiplier >= 2 && leverageMultiplier <= maxLeverageGlobal, "Controller: Invalid leverage");
        require(baseAmount > 0, "Controller: Invalid amount");
        
        // Get and validate user wallet
        (address payable userWallet, bool exists,) = walletFactory.userAccounts(msg.sender);
        require(exists, "Controller: No wallet found");
        require(userWallet != address(0), "Controller: Invalid wallet");
        
        // Validate user has funds and delegation
        require(_validateUserCapacity(userWallet, tokenIn, baseAmount, delegationHash), "Controller: Insufficient capacity");
        
        // Validate tokens are whitelisted
        require(walletFactory.allowedTokens(tokenIn), "Controller: TokenIn not allowed");
        require(walletFactory.allowedTokens(tokenOut), "Controller: TokenOut not allowed");
        
        // Validate pool-specific limits
        bytes32 poolId = _getPoolId(poolKey);
        require(leverageMultiplier <= poolConfigs[poolId].maxLeverageForPool, "Controller: Exceeds pool leverage limit");
        
        // Generate request ID
        requestId = keccak256(abi.encodePacked(msg.sender, block.timestamp, nextRequestId++));
        
        // Store trade request
        tradeRequests[requestId] = TradeRequest({
            user: msg.sender,
            userWallet: userWallet,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            baseAmount: baseAmount,
            leverageMultiplier: leverageMultiplier,
            minOutputAmount: minOutputAmount,
            delegationHash: delegationHash,
            deadline: deadline,
            requestTimestamp: block.timestamp,
            executed: false
        });
        
        emit TradeRequested(
            requestId,
            msg.sender,
            tokenIn,
            tokenOut,
            baseAmount,
            leverageMultiplier,
            deadline
        );
        
        return requestId;
    }
    
    /**
     * @notice Execute a leverage trade
     */
    function executeLeverageTrade(
        bytes32 requestId,
        PoolKey calldata poolKey
    ) external nonReentrant notPaused returns (bool success) {
        
        TradeRequest storage request = tradeRequests[requestId];
        
        // Validate execution conditions
        require(!request.executed, "Controller: Already executed");
        require(block.timestamp <= request.deadline, "Controller: Request expired");
        require(request.user != address(0), "Controller: Invalid request");
        
        // Mark as executed
        request.executed = true;
        executedTrades[requestId] = true;
        
        try this._executeTradeInternal(requestId, poolKey) returns (uint256 outputAmount, uint256 openPrice) {
            
            emit TradeExecuted(requestId, request.user, outputAmount, openPrice);
            return true;
            
        } catch Error(string memory reason) {
            
            // Revert execution state on failure
            request.executed = false;
            executedTrades[requestId] = false;
            
            revert(string(abi.encodePacked("Controller: Trade failed - ", reason)));
        }
    }
    
    /**
     * @notice Internal trade execution (external for try-catch)
     */
    function _executeTradeInternal(
        bytes32 requestId,
        PoolKey calldata poolKey
    ) external returns (uint256 outputAmount, uint256 openPrice) {
        require(msg.sender == address(this), "Controller: Internal only");
        
        TradeRequest memory request = tradeRequests[requestId];
        
        // Prepare hook data for leverage execution
        bytes memory hookData = abi.encode(
            request.user,
            request.userWallet,
            request.tokenIn,
            request.tokenOut,
            request.baseAmount,
            request.leverageMultiplier,
            request.minOutputAmount,
            request.delegationHash,
            requestId
        );
        
        // Execute trade through user wallet (respects delegation)
        bytes memory tradeCalldata = abi.encodeWithSelector(
            this.executeViaHook.selector,
            poolKey,
            hookData,
            requestId
        );
        
        // Use user's wallet to execute trade
        IUserWallet(request.userWallet).executeTrade(
            request.tokenIn,
            request.baseAmount,
            tradeCalldata,
            request.delegationHash
        );
        
        // Get position details from hook (after execution)
        IInstantLeverageHook.LeveragePosition memory position = leverageHook.leveragePositions(requestId);
        
        return (position.initialNotional, position.openPrice);
    }
    
    /**
     * @notice Execute trade via leverage hook
     */
    function executeViaHook(
        PoolKey calldata poolKey,
        bytes calldata hookData,
        bytes32 requestId
    ) external returns (bool) {
        
        // Verify this is called by a user wallet during trade execution
        TradeRequest memory request = tradeRequests[requestId];
        require(msg.sender == request.userWallet, "Controller: Only user wallet");
        
        // Execute through pool manager with hook
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -887220,  // Full range
            tickUpper: 887220,
            liquidityDelta: -int256(request.baseAmount * request.leverageMultiplier), // Negative = remove/borrow
            salt: 0
        });
        
        // This triggers the leverage hook
        poolManager.modifyLiquidity(poolKey, params, hookData);
        
        return true;
    }

    // ============ Position Management ============
    
    /**
     * @notice Close a leverage position
     */
    function closeLeveragePosition(
        bytes32 requestId,
        PoolKey calldata poolKey
    ) external nonReentrant notPaused returns (bool success) {
        
        // Verify position ownership
        TradeRequest memory request = tradeRequests[requestId];
        require(request.user == msg.sender, "Controller: Not position owner");
        require(executedTrades[requestId], "Controller: Position not open");
        
        // Get current price from pool
        uint256 currentPrice = leverageHook.getPoolPrice(poolKey);
        
        // Close through hook (handles profit/loss distribution)
        success = leverageHook.closeLeveragePosition(requestId, currentPrice);
        
        if (success) {
            // Mark as closed
            executedTrades[requestId] = false;
            
            emit PositionClosed(requestId, request.user, currentPrice, 0, 0);
        }
        
        return success;
    }
    
    /**
     * @notice Check for liquidation (anyone can call)
     */
    function checkLiquidation(
        bytes32 requestId,
        PoolKey calldata poolKey
    ) external returns (bool liquidated) {
        
        require(executedTrades[requestId], "Controller: Position not open");
        
        // Get current price from pool
        uint256 currentPrice = leverageHook.getPoolPrice(poolKey);
        
        liquidated = leverageHook.checkLiquidation(requestId, currentPrice);
        
        if (liquidated) {
            executedTrades[requestId] = false;
            
            TradeRequest memory request = tradeRequests[requestId];
            emit PositionLiquidated(requestId, request.user, currentPrice);
        }
        
        return liquidated;
    }
    
    /**
     * @notice Get position health
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
        require(executedTrades[requestId], "Controller: Position not open");
        return leverageHook.getPositionHealth(requestId, currentPrice);
    }

    // ============ View Functions ============
    
    /**
     * @notice Get user's active positions (external interface)
     */
    function getUserActivePositions(address user) external view returns (bytes32[] memory) {
        return _getUserActivePositions(user);
    }

    /**
     * @notice Get user's active positions (internal implementation)
     */
    function _getUserActivePositions(address user) internal view returns (bytes32[] memory activePositions) {
        bytes32[] memory allPositions = leverageHook.getUserPositions(user);

        // Filter for active positions
        uint256 activeCount = 0;
        for (uint256 i = 0; i < allPositions.length; i++) {
            if (executedTrades[allPositions[i]]) {
                activeCount++;
            }
        }

        activePositions = new bytes32[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allPositions.length; i++) {
            if (executedTrades[allPositions[i]]) {
                activePositions[index] = allPositions[i];
                index++;
            }
        }

        return activePositions;
    }
    
    /**
     * @notice Check if user can execute leverage trade
     */
    function canExecuteLeverageTrade(
        address user,
        PoolKey calldata poolKey,
        address tokenIn,
        uint256 baseAmount,
        uint256 leverageMultiplier,
        bytes32 delegationHash
    ) external view returns (bool canExecute, string memory reason) {
        
        // Check if pool is active
        bytes32 poolId = _getPoolId(poolKey);
        if (!poolConfigs[poolId].active) {
            return (false, "Pool not active");
        }
        
        // Check leverage limits
        if (leverageMultiplier > poolConfigs[poolId].maxLeverageForPool) {
            return (false, "Exceeds pool leverage limit");
        }
        
        // Check user wallet
        (address payable userWallet, bool exists,) = walletFactory.userAccounts(user);
        if (!exists) {
            return (false, "No wallet found");
        }
        
        // Check capacity
        if (!_validateUserCapacity(userWallet, tokenIn, baseAmount, delegationHash)) {
            return (false, "Insufficient capacity");
        }
        
        return (true, "");
    }

    // ============ Internal Functions ============
    
    /**
     * @notice Validate user has sufficient funds and delegation
     */
    function _validateUserCapacity(
        address userWallet,
        address token,
        uint256 amount,
        bytes32 delegationHash
    ) internal view returns (bool) {
        
        // Check wallet balance
        if (IUserWallet(userWallet).balances(token) < amount) {
            return false;
        }
        
        // Check delegation
        (bool active, uint256 maxAmount, uint256 expiry) = IUserWallet(userWallet).delegations(delegationHash);
        if (!active || amount > maxAmount || block.timestamp >= expiry) {
            return false;
        }
        
        return true;
    }
    
    /**
     * @notice Generate pool ID
     */
    function _getPoolId(PoolKey calldata key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key.currency0, key.currency1, key.fee, key.tickSpacing));
    }

    // ============ Admin Functions ============
    
    /**
     * @notice Configure pool for leverage trading
     */
    function configurePool(
        PoolKey calldata poolKey,
        bool active,
        uint256 maxLeverage,
        uint256 maxUtilization,
        uint256 baseFeeRate
    ) external onlyOwner {
        bytes32 poolId = _getPoolId(poolKey);
        
        poolConfigs[poolId] = PoolConfig({
            active: active,
            maxLeverageForPool: maxLeverage,
            maxUtilization: maxUtilization,
            baseFeeRate: baseFeeRate
        });
        
        emit PoolConfigured(poolId, active, maxLeverage);
    }
    
    /**
     * @notice Set global leverage limit
     */
    function setMaxLeverageGlobal(uint256 newMax) external onlyOwner {
        require(newMax >= 2 && newMax <= 50, "Controller: Invalid leverage range");
        maxLeverageGlobal = newMax;
    }
    
    /**
     * @notice Emergency pause
     */
    function setEmergencyPause(bool paused) external onlyOwner {
        emergencyPaused = paused;
    }
    
    /**
     * @notice Set price oracle manager
     */
    function setPriceOracleManager(address newManager) external onlyOwner {
        require(newManager != address(0), "Controller: Invalid manager address");
        priceOracleManager = newManager;
    }

    /**
     * @notice Batch liquidation checker for efficiency
     */
    function batchCheckLiquidations(
        bytes32[] calldata requestIds,
        PoolKey calldata poolKey
    ) external returns (uint256 liquidatedCount) {
        uint256 currentPrice = leverageHook.getPoolPrice(poolKey);

        for (uint256 i = 0; i < requestIds.length; i++) {
            if (executedTrades[requestIds[i]]) {
                bool liquidated = leverageHook.checkLiquidation(requestIds[i], currentPrice);
                if (liquidated) {
                    executedTrades[requestIds[i]] = false;
                    liquidatedCount++;

                    TradeRequest memory request = tradeRequests[requestIds[i]];
                    emit PositionLiquidated(requestIds[i], request.user, currentPrice);
                }
            }
        }

        return liquidatedCount;
    }

    /**
     * @notice Emergency function to close all positions for a user
     */
    function emergencyCloseUserPositions(
        address user,
        PoolKey calldata poolKey
    ) external onlyOwner {
        bytes32[] memory positions = _getUserActivePositions(user);
        uint256 currentPrice = leverageHook.getPoolPrice(poolKey);

        for (uint256 i = 0; i < positions.length; i++) {
            leverageHook.closeLeveragePosition(positions[i], currentPrice);
            executedTrades[positions[i]] = false;
        }
    }
}