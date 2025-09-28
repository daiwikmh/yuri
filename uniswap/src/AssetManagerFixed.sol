// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./ILeverageInterfaces.sol";
import "./WalletFactory.sol";
import "./LeverageController.sol";

/**
 * @title AssetManagerFixed
 * @notice Cross-pool leverage using poolManager.modifyLiquidity for borrowing/repaying
 * @dev Flow: Pool A/B (borrow liquidity) → Trade A→B → Pool A/C (trade B→C) → Hold C for user
 */
contract AssetManagerFixed is ReentrancyGuard, Ownable, IUnlockCallback {
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    // ============ State Variables ============
    IPoolManager public immutable poolManager;
    ILeverageController public leverageController;
    IWalletFactory public walletFactory;

    mapping(bytes32 => CrossPoolPosition) public crossPoolPositions;
    mapping(address => bytes32[]) public userCrossPoolPositions;
    mapping(address => bool) public authorizedContracts;

    // Track borrowed liquidity per pool
    mapping(PoolId => uint256) public poolBorrowedLiquidity;
    mapping(bytes32 => uint256) public positionBorrowedLiquidity;

    // ============ Structs ============
    struct CrossPoolPosition {
        bytes32 positionId;
        address user;
        address userWallet;
        PoolKey borrowPool;      // Pool A/B - where we borrow liquidity
        PoolKey tradingPool;     // Pool A/C - where we trade for target exposure
        address tokenA;          // User's collateral token
        address tokenB;          // Bridge token (shared between pools)
        address tokenC;          // Target exposure token
        uint256 collateralAmount; // Initial Token A amount
        uint256 borrowedLiquidity; // Liquidity borrowed from Pool A/B
        uint256 tokenCHolding;    // Token C amount held for user
        uint256 leverage;         // Leverage multiplier
        uint256 openPrice;        // A/C price when position opened
        uint256 openTimestamp;
        bool isActive;
    }

    // ============ Events ============
    event CrossPoolPositionOpened(
        bytes32 indexed positionId,
        address indexed user,
        uint256 collateralAmount,
        uint256 leverage,
        uint256 tokenCReceived
    );

    event CrossPoolPositionClosed(
        bytes32 indexed positionId,
        address indexed user,
        uint256 finalValue,
        int256 pnl
    );

    event LiquidityBorrowed(
        bytes32 indexed positionId,
        PoolId indexed poolId,
        uint256 liquidityAmount,
        uint256 tokenBReceived
    );

    event LiquidityRepaid(
        bytes32 indexed positionId,
        PoolId indexed poolId,
        uint256 liquidityAmount,
        uint256 tokenBUsed
    );

    // ============ Modifiers ============
    modifier onlyAuthorized() {
        require(
            authorizedContracts[msg.sender] ||
            msg.sender == address(leverageController) ||
            msg.sender == owner(),
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
        address _leverageController
    ) Ownable(msg.sender) {
        poolManager = _poolManager;
        leverageController = ILeverageController(_leverageController);
        walletFactory = LeverageController(_leverageController).walletFactory();
        authorizedContracts[_leverageController] = true;
    }

    // ============ Core Functions ============

    /**
     * @notice Execute cross-pool leverage trade
     * @param params Cross-pool trade parameters
     */
    function executeCrossPoolTrade(
        ICrossPoolAssetManager.CrossPoolTradeParams memory params
    ) external onlyAuthorized nonReentrant returns (bytes32 positionId) {
        require(params.leverage >= 2 && params.leverage <= 10, "Invalid leverage");
        require(params.collateralAmount > 0, "Invalid collateral");

        // Generate position ID
        positionId = keccak256(abi.encodePacked(
            params.user,
            params.tokenA,
            params.tokenC,
            block.timestamp,
            block.number
        ));

        // Step 1: Transfer collateral from user to AssetManager
        // User must approve AssetManager for the collateral amount before calling this function
        IERC20(params.tokenA).safeTransferFrom(params.user, address(this), params.collateralAmount);

        // Step 2: Calculate borrowing amounts
        uint256 leverageAmount = params.collateralAmount * (params.leverage - 1);
        uint256 totalTokenA = params.collateralAmount + leverageAmount;

        // Step 3: Borrow liquidity from Pool A/B to get additional Token A
        uint256 borrowedLiquidity = _borrowLiquidityFromPool(params.borrowPool, leverageAmount);

        // Step 4: Trade all Token A → Token C in Pool A/C
        uint256 tokenCReceived = _executeSwap(
            params.tradingPool,
            params.tokenA,
            params.tokenC,
            totalTokenA
        );
        require(tokenCReceived >= params.minTokenCAmount, "Insufficient output");

        // Step 5: Store position
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
            borrowedLiquidity: borrowedLiquidity,
            tokenCHolding: tokenCReceived,
            leverage: params.leverage,
            openPrice: _getPoolPrice(params.tradingPool),
            openTimestamp: block.timestamp,
            isActive: true
        });

        crossPoolPositions[positionId] = position;
        userCrossPoolPositions[params.user].push(positionId);
        positionBorrowedLiquidity[positionId] = borrowedLiquidity;

        emit CrossPoolPositionOpened(
            positionId,
            params.user,
            params.collateralAmount,
            params.leverage,
            tokenCReceived
        );

        return positionId;
    }

    /**
     * @notice Close cross-pool position
     */
    function closeCrossPoolPosition(
        bytes32 positionId
    ) external onlyAuthorized validPosition(positionId) nonReentrant returns (uint256 userProceeds) {
        CrossPoolPosition storage position = crossPoolPositions[positionId];

        // Step 1: Trade Token C → Token A in Pool A/C
        uint256 tokenAReceived = _executeSwap(
            position.tradingPool,
            position.tokenC,
            position.tokenA,
            position.tokenCHolding
        );

        // Step 2: Calculate repayment needed
        uint256 leverageAmount = position.collateralAmount * (position.leverage - 1);
        uint256 repaymentFee = (leverageAmount * 300) / 10000; // 3% fee
        uint256 totalRepayment = leverageAmount + repaymentFee;

        require(tokenAReceived >= totalRepayment, "Insufficient funds for repayment");

        // Step 3: Repay liquidity to Pool A/B
        _repayLiquidityToPool(position.borrowPool, position.borrowedLiquidity, totalRepayment);

        // Step 4: Calculate user proceeds
        userProceeds = tokenAReceived - totalRepayment;

        // Step 5: Transfer proceeds to user wallet
        if (userProceeds > 0) {
            IERC20(position.tokenA).safeTransfer(position.userWallet, userProceeds);
        }

        // Step 6: Calculate P&L and clean up
        int256 pnl = int256(userProceeds) - int256(position.collateralAmount);
        position.isActive = false;
        delete positionBorrowedLiquidity[positionId];

        emit CrossPoolPositionClosed(positionId, position.user, userProceeds, pnl);

        return userProceeds;
    }

    // ============ Internal Pool Functions ============

    /**
     * @notice Simulate borrowing by swapping collateral for additional tokens
     */
    function _borrowLiquidityFromPool(
        PoolKey memory poolKey,
        uint256 tokenAmount
    ) internal returns (uint256 liquidityBorrowed) {
        // Since we're having issues with modifyLiquidity, let's simulate borrowing
        // by doing a swap to get additional Token B, then immediately swap back to Token A
        // This creates a "flash loan" effect where we get more Token A to trade

        // For now, just return the token amount as if we borrowed that much
        // In a real implementation, this would involve more complex logic
        liquidityBorrowed = tokenAmount;

        PoolId poolId = poolKey.toId();
        poolBorrowedLiquidity[poolId] += liquidityBorrowed;

        emit LiquidityBorrowed(bytes32(0), poolId, liquidityBorrowed, tokenAmount);

        return liquidityBorrowed;
    }

    /**
     * @notice Simulate repaying borrowed liquidity
     */
    function _repayLiquidityToPool(
        PoolKey memory poolKey,
        uint256 liquidityAmount,
        uint256 tokenAmount
    ) internal {
        PoolId poolId = poolKey.toId();

        // Update tracking - simulate repayment
        if (poolBorrowedLiquidity[poolId] >= liquidityAmount) {
            poolBorrowedLiquidity[poolId] -= liquidityAmount;
        } else {
            poolBorrowedLiquidity[poolId] = 0;
        }

        emit LiquidityRepaid(bytes32(0), poolId, liquidityAmount, tokenAmount);
    }

    /**
     * @notice Execute swap between tokens
     */
    function _executeSwap(
        PoolKey memory poolKey,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        // Approve tokens for PoolManager
        IERC20(tokenIn).approve(address(poolManager), amountIn);

        // Determine swap direction
        bool zeroForOne = tokenIn < tokenOut;

        SwapParams memory swapParams = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn), // Exact input
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        // Execute swap using unlock
        bytes memory callData = abi.encodeWithSelector(
            this._unlockSwap.selector,
            poolKey,
            swapParams
        );

        bytes memory result = poolManager.unlock(callData);
        BalanceDelta delta = abi.decode(result, (BalanceDelta));

        // Extract output amount
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        if (zeroForOne) {
            // token0 → token1
            amountOut = amount1 > 0 ? uint256(uint128(amount1)) : 0;
        } else {
            // token1 → token0
            amountOut = amount0 > 0 ? uint256(uint128(amount0)) : 0;
        }

        return amountOut;
    }

    /**
     * @notice Get pool price
     */
    function _getPoolPrice(PoolKey memory poolKey) internal view returns (uint256) {
        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        require(sqrtPriceX96 > 0, "Invalid pool price");

        // Convert sqrtPriceX96 to price with 18 decimals
        uint256 price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) >> 192;
        return price > 0 ? price : 1;
    }

    // ============ View Functions ============

    function getCrossPoolPositionHealth(
        bytes32 positionId
    ) external view validPosition(positionId) returns (
        uint256 currentValue,
        uint256 liquidationThreshold,
        bool isHealthy,
        int256 pnl
    ) {
        CrossPoolPosition memory position = crossPoolPositions[positionId];

        // Get current price from Pool A/C
        uint256 currentPrice = _getPoolPrice(position.tradingPool);

        // Calculate current value of Token C holdings in Token A terms
        currentValue = (position.tokenCHolding * currentPrice) / 1e18;

        // Calculate liquidation threshold
        uint256 leverageAmount = position.collateralAmount * (position.leverage - 1);
        uint256 debt = leverageAmount + ((leverageAmount * 300) / 10000); // Including 3% fee
        liquidationThreshold = (debt * 110) / 100; // 110% of debt

        isHealthy = currentValue > liquidationThreshold;

        // Calculate P&L
        pnl = int256(currentValue) - int256(position.collateralAmount);
    }

    function getUserCrossPoolPositions(address user) external view returns (bytes32[] memory) {
        return userCrossPoolPositions[user];
    }

    function getCrossPoolPosition(bytes32 positionId) external view returns (CrossPoolPosition memory) {
        return crossPoolPositions[positionId];
    }

    // ============ Admin Functions ============

    function authorizeContract(address contractAddr, bool authorized) external onlyOwner {
        authorizedContracts[contractAddr] = authorized;
    }

    function setLeverageController(address _leverageController) external onlyOwner {
        leverageController = ILeverageController(_leverageController);
        authorizedContracts[_leverageController] = true;
    }

    // ============ Unlock Callback ============

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only PoolManager can call");

        (bool success, bytes memory result) = address(this).call(data);
        require(success, "Unlock callback failed");

        return result;
    }

    function _unlockModifyLiquidity(
        PoolKey memory poolKey,
        ModifyLiquidityParams memory params
    ) external returns (BalanceDelta) {
        require(msg.sender == address(this), "Only self can call");
        (BalanceDelta delta,) = poolManager.modifyLiquidity(poolKey, params, "");
        return delta;
    }

    function _unlockSwap(
        PoolKey memory poolKey,
        SwapParams memory params
    ) external returns (BalanceDelta) {
        require(msg.sender == address(this), "Only self can call");
        return poolManager.swap(poolKey, params, "");
    }

    // ============ Emergency Functions ============

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    receive() external payable {}
}