// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./ILeverageInterfaces.sol";

/**
 * @title AssetManager
 * @notice Manages cross-pool leverage by holding intermediate assets and executing trades
 * @dev Simplifies cross-pool flow: Pool A/B (borrow) → AssetManager (hold) → Pool B/C (trade)
 */
contract AssetManager is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============
    IPoolManager public immutable poolManager;
    ILeverageController public leverageController;
    IInstantLeverageHook public leverageHook;

    mapping(bytes32 => CrossPoolPosition) public crossPoolPositions;
    mapping(address => bytes32[]) public userCrossPoolPositions;
    mapping(address => bool) public authorizedContracts;

    // ============ Structs ============
    struct CrossPoolPosition {
        bytes32 positionId;
        address user;
        address userWallet;
        PoolKey borrowPool;      // Pool A/B - source of leverage
        PoolKey tradingPool;     // Pool B/C - target trading pool
        address tokenA;          // User's collateral token
        address tokenB;          // Bridge token (common between pools)
        address tokenC;          // Target token user wants exposure to
        uint256 collateralAmount; // Initial Token A amount
        uint256 borrowedTokenB;   // Token B borrowed from Pool A/B
        uint256 tokenCHolding;    // Token C amount held by AssetManager
        uint256 leverage;         // Leverage multiplier
        uint256 openPrice;        // B/C price when position opened
        uint256 openTimestamp;
        bool isActive;
    }

    // ============ Events ============
    event CrossPoolPositionOpened(
        bytes32 indexed positionId,
        address indexed user,
        address tokenA,
        address tokenB,
        address tokenC,
        uint256 leverage,
        uint256 tokenCAmount
    );

    event CrossPoolPositionClosed(
        bytes32 indexed positionId,
        address indexed user,
        uint256 finalValue,
        int256 pnl
    );

    event AssetsTransferred(
        bytes32 indexed positionId,
        address token,
        uint256 amount,
        string operation
    );

    // ============ Modifiers ============
    modifier onlyAuthorized() {
        require(
            authorizedContracts[msg.sender] ||
            msg.sender == address(leverageController) ||
            msg.sender == address(leverageHook),
            "AssetManager: Unauthorized"
        );
        _;
    }

    modifier validPosition(bytes32 positionId) {
        require(crossPoolPositions[positionId].isActive, "AssetManager: Invalid position");
        _;
    }

    // ============ Constructor ============
    constructor(
        IPoolManager _poolManager,
        address _leverageController,
        address _leverageHook
    ) Ownable(msg.sender) {
        poolManager = _poolManager;
        leverageController = ILeverageController(_leverageController);
        leverageHook = IInstantLeverageHook(_leverageHook);

        // Authorize core contracts
        authorizedContracts[_leverageController] = true;
        authorizedContracts[_leverageHook] = true;
    }

    // ============ Core Functions ============

    /**
     * @notice Execute cross-pool leverage trade
     * @param params Cross-pool trade parameters
     */
    function executeCrossPoolTrade(
        ICrossPoolAssetManager.CrossPoolTradeParams memory params
    ) external onlyAuthorized nonReentrant returns (bytes32 positionId) {
        require(params.leverage >= 2 && params.leverage <= 10, "AssetManager: Invalid leverage");
        require(params.collateralAmount > 0, "AssetManager: Invalid collateral");

        // Generate position ID
        positionId = keccak256(abi.encodePacked(
            params.user,
            params.tokenA,
            params.tokenC,
            block.timestamp,
            block.number
        ));

        // Step 1: Borrow Token B from Pool A/B via LeverageHook
        uint256 borrowAmount = params.collateralAmount * (params.leverage - 1);
        uint256 totalTokenB = _borrowFromPoolAB(params.borrowPool, params.tokenB, borrowAmount);

        // Step 2: Convert user's Token A to Token B (if needed)
        uint256 userTokenB = _convertTokenAToB(params.borrowPool, params.tokenA, params.collateralAmount);
        totalTokenB += userTokenB;

        // Step 3: Trade Token B → Token C in Pool B/C
        uint256 tokenCReceived = _tradeTokenBToC(params.tradingPool, params.tokenB, params.tokenC, totalTokenB);
        require(tokenCReceived >= params.minTokenCAmount, "AssetManager: Insufficient output");

        // Step 4: Store position
        CrossPoolPosition memory position = CrossPoolPosition({
            positionId: positionId,
            user: params.user,
            userWallet: params.userWallet,
            borrowPool: params.borrowPool,
            tradingPool: params.tradingPool,
            tokenA: params.tokenA,
            tokenB: params.tokenB,
            tokenC: params.tokenC,
            collateralAmount: params.collateralAmount,
            borrowedTokenB: borrowAmount,
            tokenCHolding: tokenCReceived,
            leverage: params.leverage,
            openPrice: _getPoolPrice(params.tradingPool),
            openTimestamp: block.timestamp,
            isActive: true
        });

        crossPoolPositions[positionId] = position;
        userCrossPoolPositions[params.user].push(positionId);

        emit CrossPoolPositionOpened(
            positionId,
            params.user,
            params.tokenA,
            params.tokenB,
            params.tokenC,
            params.leverage,
            tokenCReceived
        );

        return positionId;
    }

    /**
     * @notice Close cross-pool position
     * @param positionId Position to close
     */
    function closeCrossPoolPosition(
        bytes32 positionId
    ) external onlyAuthorized validPosition(positionId) nonReentrant returns (uint256 userProceeds) {
        CrossPoolPosition storage position = crossPoolPositions[positionId];

        // Step 1: Trade Token C → Token B in Pool B/C
        uint256 tokenBReceived = _tradeTokenCToB(
            position.tradingPool,
            position.tokenC,
            position.tokenB,
            position.tokenCHolding
        );

        // Step 2: Repay borrowed Token B to Pool A/B
        uint256 repayAmount = position.borrowedTokenB + _calculateFees(position.borrowedTokenB);
        require(tokenBReceived >= repayAmount, "AssetManager: Insufficient funds for repayment");

        _repayToPoolAB(position.borrowPool, position.tokenB, repayAmount);

        // Step 3: Convert remaining Token B to Token A for user
        uint256 remainingTokenB = tokenBReceived - repayAmount;
        userProceeds = _convertTokenBToA(position.borrowPool, position.tokenB, position.tokenA, remainingTokenB);

        // Step 4: Transfer proceeds to user wallet
        IERC20(position.tokenA).safeTransfer(position.userWallet, userProceeds);

        // Step 5: Calculate P&L and clean up
        int256 pnl = int256(userProceeds) - int256(position.collateralAmount);
        position.isActive = false;

        emit CrossPoolPositionClosed(positionId, position.user, userProceeds, pnl);

        return userProceeds;
    }

    /**
     * @notice Get cross-pool position health
     */
    function getCrossPoolPositionHealth(
        bytes32 positionId
    ) external view validPosition(positionId) returns (
        uint256 currentValue,
        uint256 liquidationThreshold,
        bool isHealthy,
        int256 pnl
    ) {
        CrossPoolPosition memory position = crossPoolPositions[positionId];

        // Get current Token C price from Pool B/C
        uint256 currentPrice = _getPoolPrice(position.tradingPool);

        // Calculate current position value in Token B
        currentValue = (position.tokenCHolding * currentPrice) / 1e18;

        // Calculate liquidation threshold (debt + fees + safety margin)
        uint256 debt = position.borrowedTokenB + _calculateFees(position.borrowedTokenB);
        liquidationThreshold = (debt * 110) / 100; // 110% of debt

        isHealthy = currentValue > liquidationThreshold;

        // Calculate P&L in Token A equivalent
        uint256 totalValue = currentValue > debt ? currentValue - debt : 0;
        uint256 tokenAValue = _estimateTokenBToA(position.borrowPool, position.tokenB, totalValue);
        pnl = int256(tokenAValue) - int256(position.collateralAmount);
    }

    // ============ Internal Functions ============

    function _borrowFromPoolAB(
        PoolKey memory poolKey,
        address tokenB,
        uint256 amount
    ) internal returns (uint256 borrowed) {
        // Call LeverageHook to borrow from Pool A/B
        return leverageHook.borrowFromPool(poolKey, tokenB, amount);
    }

    function _repayToPoolAB(
        PoolKey memory poolKey,
        address tokenB,
        uint256 amount
    ) internal {
        // Approve and repay to Pool A/B via LeverageHook
        IERC20(tokenB).approve(address(leverageHook), amount);
        leverageHook.repayToPool(poolKey, tokenB, amount);
    }

    function _convertTokenAToB(
        PoolKey memory poolKey,
        address tokenA,
        uint256 amount
    ) internal returns (uint256 tokenBReceived) {
        return _executeSwap(poolKey, tokenA, Currency.unwrap(poolKey.currency1), amount);
    }

    function _convertTokenBToA(
        PoolKey memory poolKey,
        address tokenB,
        address tokenA,
        uint256 amount
    ) internal returns (uint256 tokenAReceived) {
        return _executeSwap(poolKey, tokenB, tokenA, amount);
    }

    function _tradeTokenBToC(
        PoolKey memory poolKey,
        address tokenB,
        address tokenC,
        uint256 amount
    ) internal returns (uint256 tokenCReceived) {
        return _executeSwap(poolKey, tokenB, tokenC, amount);
    }

    function _tradeTokenCToB(
        PoolKey memory poolKey,
        address tokenC,
        address tokenB,
        uint256 amount
    ) internal returns (uint256 tokenBReceived) {
        return _executeSwap(poolKey, tokenC, tokenB, amount);
    }

    function _executeSwap(
        PoolKey memory poolKey,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        // Approve tokens for PoolManager
        IERC20(tokenIn).approve(address(poolManager), amountIn);

        // Execute swap
        SwapParams memory swapParams = SwapParams({
            zeroForOne: tokenIn < tokenOut,
            amountSpecified: -int256(amountIn), // Exact input
            sqrtPriceLimitX96: 0
        });

        BalanceDelta delta = poolManager.swap(poolKey, swapParams, "");

        // Extract output amount
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();
        amountOut = tokenIn < tokenOut ?
            (amount1 > 0 ? uint256(uint128(amount1)) : 0) :
            (amount0 > 0 ? uint256(uint128(amount0)) : 0);

        emit AssetsTransferred(bytes32(0), tokenOut, amountOut, "swap_received");
        return amountOut;
    }

    function _getPoolPrice(PoolKey memory poolKey) internal view returns (uint256) {
        // Get pool price using the same logic as InstantLeverageHook
        return leverageHook.getPoolPrice(poolKey);
    }

    function _estimateTokenBToA(
        PoolKey memory poolKey,
        address tokenB,
        uint256 tokenBAmount
    ) internal view returns (uint256) {
        // Estimate Token A value without executing trade
        uint256 poolPrice = _getPoolPrice(poolKey);
        return (tokenBAmount * poolPrice) / 1e18;
    }

    function _calculateFees(uint256 borrowedAmount) internal pure returns (uint256) {
        return (borrowedAmount * 300) / 10000; // 3% fee
    }

    // ============ Admin Functions ============

    function authorizeContract(address contractAddr, bool authorized) external onlyOwner {
        authorizedContracts[contractAddr] = authorized;
    }

    function setLeverageController(address _leverageController) external onlyOwner {
        leverageController = ILeverageController(_leverageController);
        authorizedContracts[_leverageController] = true;
    }

    function setLeverageHook(address _leverageHook) external onlyOwner {
        leverageHook = IInstantLeverageHook(_leverageHook);
        authorizedContracts[_leverageHook] = true;
    }

    // ============ View Functions ============

    function getUserCrossPoolPositions(address user) external view returns (bytes32[] memory) {
        return userCrossPoolPositions[user];
    }

    function getCrossPoolPosition(bytes32 positionId) external view returns (CrossPoolPosition memory) {
        return crossPoolPositions[positionId];
    }

    // For compatibility with interface
    function getCrossPoolPositionInterface(bytes32 positionId) external view returns (ICrossPoolAssetManager.CrossPoolPosition memory) {
        CrossPoolPosition memory pos = crossPoolPositions[positionId];
        return ICrossPoolAssetManager.CrossPoolPosition({
            positionId: pos.positionId,
            user: pos.user,
            userWallet: pos.userWallet,
            borrowPool: pos.borrowPool,
            tradingPool: pos.tradingPool,
            tokenA: pos.tokenA,
            tokenB: pos.tokenB,
            tokenC: pos.tokenC,
            collateralAmount: pos.collateralAmount,
            borrowedTokenB: pos.borrowedTokenB,
            tokenCHolding: pos.tokenCHolding,
            leverage: pos.leverage,
            openPrice: pos.openPrice,
            openTimestamp: pos.openTimestamp,
            isActive: pos.isActive
        });
    }

    // ============ Emergency Functions ============

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    receive() external payable {}
}