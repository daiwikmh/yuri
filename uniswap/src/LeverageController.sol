// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
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

    // ============ State Variables ============
    IWalletFactory public immutable walletFactory;
    IInstantLeverageHook public leverageHook;
    IPoolManager public immutable poolManager;

    uint256 public nextRequestId = 1;
    mapping(bytes32 => TradeRequest) public tradeRequests;
    mapping(bytes32 => bool) public executedTrades;
    mapping(address => bool) public authorizedPlatforms;

    // Pool and platform configuration
    mapping(bytes32 => PoolConfig) public poolConfigs;
    mapping(address => address) public priceOracles;

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
        IPoolManager _poolManager,
        address _walletFactory,
        address _leverageHook
    ) Ownable(msg.sender) {
        poolManager = _poolManager;
        walletFactory = IWalletFactory(_walletFactory);
        leverageHook = IInstantLeverageHook(_leverageHook);
        authorizedPlatforms[_walletFactory] = true;
    }

    // ============ Core Trading Functions ============

    /**
     * @notice Request a leverage trade
     */
    function requestLeverageTrade(
        ILeverageController.TradeRequestParams calldata params
    ) external notPaused validPool(params.poolKey) returns (bytes32 requestId) {
        require(block.timestamp <= params.deadline, "Controller: Deadline passed");
        require(
            params.leverageMultiplier >= 2 && params.leverageMultiplier <= maxLeverageGlobal,
            "Controller: Invalid leverage"
        );
        require(params.baseAmount > 0, "Controller: Invalid amount");

        (address payable userWallet, bool exists,) = walletFactory.userAccounts(msg.sender);
        require(exists, "Controller: No wallet found");
        require(userWallet != address(0), "Controller: Invalid wallet");

        require(_validateTradeParams(userWallet, params), "Controller: Invalid trade parameters");

        requestId = keccak256(abi.encodePacked(msg.sender, block.timestamp, nextRequestId++));

        tradeRequests[requestId] = TradeRequest({
            user: msg.sender,
            userWallet: userWallet,
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            baseAmount: params.baseAmount,
            leverageMultiplier: params.leverageMultiplier,
            minOutputAmount: params.minOutputAmount,
            delegationHash: params.delegationHash,
            deadline: params.deadline,
            requestTimestamp: block.timestamp,
            executed: false
        });

        emit TradeRequested(
            requestId,
            msg.sender,
            params.tokenIn,
            params.tokenOut,
            params.baseAmount,
            params.leverageMultiplier,
            params.deadline
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
        require(!request.executed, "Controller: Already executed");
        require(block.timestamp <= request.deadline, "Controller: Request expired");
        require(request.user != address(0), "Controller: Invalid request");

        request.executed = true;
        executedTrades[requestId] = true;

        // Create leverage request for hook
        InstantLeverageRequest memory leverageRequest = InstantLeverageRequest({
            requestId: requestId,
            user: request.user,
            userWallet: request.userWallet,
            tokenIn: request.tokenIn,
            tokenOut: request.tokenOut,
            userBaseAmount: request.baseAmount,
            leverageMultiplier: request.leverageMultiplier,
            minOutputAmount: request.minOutputAmount,
            targetPoolKey: poolKey
        });

        try leverageHook.executeLeverageTrade(poolKey, leverageRequest) returns (
            uint256 outputAmount,
            uint256 openPrice
        ) {
            emit TradeExecuted(requestId, request.user, outputAmount, openPrice);
            return true;
        } catch Error(string memory reason) {
            request.executed = false;
            executedTrades[requestId] = false;
            revert(string(abi.encodePacked("Controller: Trade failed - ", reason)));
        }
    }

    // ============ Position Management ============

    /**
     * @notice Close a leverage position
     */
    function closeLeveragePosition(
        bytes32 requestId,
        PoolKey calldata poolKey
    ) external nonReentrant notPaused returns (bool success) {
        TradeRequest memory request = tradeRequests[requestId];
        require(request.user == msg.sender, "Controller: Not position owner");
        require(executedTrades[requestId], "Controller: Position not open");

        IInstantLeverageHook.ClosePositionParams memory params = IInstantLeverageHook.ClosePositionParams({
            requestId: requestId,
            poolKey: poolKey
        });

        success = leverageHook.closeLeveragePosition(params);
        if (success) {
            delete executedTrades[requestId];

            IInstantLeverageHook.LeveragePosition memory position = leverageHook.getPosition(requestId);
            uint256 currentPrice = leverageHook.getPoolPrice(poolKey);
            uint256 currentValue = _calculatePositionValue(position, currentPrice);
            int256 pnl = int256(currentValue) - int256(position.initialNotional);
            uint256 userProceeds = pnl > 0 ? position.userContribution + (uint256(pnl) * 9700) / 10000 : 0;

            emit PositionClosed(requestId, msg.sender, currentValue, pnl, userProceeds);
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
     * @notice Get user's active positions
     */
    function getUserActivePositions(address user) external view returns (bytes32[] memory activePositions) {
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
        bytes32 poolId = _getPoolId(poolKey);
        if (!poolConfigs[poolId].active) return (false, "Pool not active");
        if (leverageMultiplier > poolConfigs[poolId].maxLeverageForPool) return (false, "Exceeds limit");

        (address payable userWallet, bool exists,) = walletFactory.userAccounts(user);
        if (!exists) return (false, "No wallet");
        if (!_validateUserCapacity(userWallet, tokenIn, baseAmount, delegationHash)) return (false, "Insufficient capacity");

        return (true, "");
    }

    // ============ Internal Functions ============

    /**
     * @notice Validate trade parameters
     */
    function _validateTradeParams(
        address userWallet,
        ILeverageController.TradeRequestParams calldata params
    ) internal view returns (bool) {
        // Check wallet balance
        if (IUserWallet(userWallet).balances(params.tokenIn) < params.baseAmount) {
            return false;
        }

        // Check delegation
        (bool active, uint256 maxAmount, uint256 expiry) = IUserWallet(userWallet).delegations(params.delegationHash);
        if (!active || params.baseAmount > maxAmount || block.timestamp >= expiry) {
            return false;
        }

        // Check token allowances
        if (!walletFactory.allowedTokens(params.tokenIn) || !walletFactory.allowedTokens(params.tokenOut)) {
            return false;
        }

        // Check pool-specific leverage limit
        bytes32 poolId = _getPoolId(params.poolKey);
        if (params.leverageMultiplier > poolConfigs[poolId].maxLeverageForPool) {
            return false;
        }

        return true;
    }

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

    /**
     * @notice Calculate position value
     */
    function _calculatePositionValue(
        IInstantLeverageHook.LeveragePosition memory position,
        uint256 currentPrice
    ) internal pure returns (uint256) {
        return (position.outputTokenAmount * currentPrice) / position.openPrice;
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
     * @notice Set leverage hook
     */
    function setLeverageHook(address _leverageHook) external onlyOwner {
        leverageHook = IInstantLeverageHook(_leverageHook);
    }

    /**
     * @notice Authorize platform for AssetManager integration
     */
    function authorizePlatform(address platform) external onlyOwner {
        authorizedPlatforms[platform] = true;
    }

    /**
     * @notice Revoke platform authorization
     */
    function revokePlatform(address platform) external onlyOwner {
        authorizedPlatforms[platform] = false;
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
        bytes32[] memory positions = this.getUserActivePositions(user);

        for (uint256 i = 0; i < positions.length; i++) {
            IInstantLeverageHook.ClosePositionParams memory params = IInstantLeverageHook.ClosePositionParams({
                requestId: positions[i],
                poolKey: poolKey
            });

            leverageHook.closeLeveragePosition(params);
            executedTrades[positions[i]] = false;
        }
    }
}