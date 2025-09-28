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

contract AssetManagerFixed is ReentrancyGuard, Ownable, IUnlockCallback {
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    uint256 private constant MAX_INT128 = 170141183460469231731687303715884105727;

    IPoolManager public immutable poolManager;
    ILeverageController public leverageController;
    IWalletFactory public walletFactory;

    mapping(bytes32 => CrossPoolPosition) public crossPoolPositions;
    mapping(address => bytes32[]) public userCrossPoolPositions;
    mapping(address => bool) public authorizedContracts;
    mapping(PoolId => uint256) public poolBorrowedLiquidity;
    mapping(bytes32 => uint256) public positionBorrowedLiquidity;

    struct CrossPoolPosition {
        bytes32 positionId;
        address user;
        address userWallet;
        PoolKey borrowPool;
        PoolKey tradingPool;
        address tokenA;
        address tokenB;
        address tokenC;
        uint256 collateralAmount;
        uint256 borrowedLiquidity;
        uint256 tokenCHolding;
        uint256 leverage;
        uint256 openPrice;
        uint256 openTimestamp;
        bool isActive;
    }

    event CrossPoolPositionOpened(bytes32 indexed positionId, address indexed user, uint256 leverage, uint256 tokenCReceived);
    event CrossPoolPositionClosed(bytes32 indexed positionId, address indexed user, uint256 finalValue);
    event LiquidityBorrowed(bytes32 indexed positionId, PoolId indexed poolId, uint256 liquidityAmount);
    event LiquidityRepaid(bytes32 indexed positionId, PoolId indexed poolId, uint256 liquidityAmount);

    modifier onlyAuthorized() {
        require(
            authorizedContracts[msg.sender] || msg.sender == address(leverageController) || msg.sender == owner(),
            "Unauthorized"
        );
        _;
    }

    modifier validPosition(bytes32 positionId) {
        require(crossPoolPositions[positionId].isActive, "Invalid position");
        _;
    }

    constructor(IPoolManager _poolManager, address _leverageController) Ownable(msg.sender) {
        poolManager = _poolManager;
        leverageController = ILeverageController(_leverageController);
        walletFactory = LeverageController(_leverageController).walletFactory();
        authorizedContracts[_leverageController] = true;
    }

    function executeCrossPoolTrade(
        ICrossPoolAssetManager.CrossPoolTradeParams memory params
    ) external onlyAuthorized nonReentrant returns (bytes32 positionId) {
        require(params.leverage >= 2 && params.leverage <= 10, "Invalid leverage");
        require(params.collateralAmount > 0, "Invalid collateral");
        require(params.tokenA != address(0) && params.tokenB != address(0) && params.tokenC != address(0), "Invalid tokens");
        require(params.user != address(0) && params.userWallet != address(0), "Invalid addresses");

        positionId = keccak256(abi.encodePacked(params.user, params.tokenA, params.tokenC, block.timestamp, block.number));
        IERC20(params.tokenA).safeTransferFrom(params.user, address(this), params.collateralAmount);

        uint256 leverageAmount = params.collateralAmount * (params.leverage - 1);
        require(leverageAmount <= MAX_INT128, "Borrow amount too large");
        uint256 borrowedTokens = _borrowLiquidityFromPool(params.borrowPool, leverageAmount);
        uint256 totalTokenA = params.collateralAmount + borrowedTokens;

        uint256 tokenCReceived = _executeSwap(params.tradingPool, params.tokenA, params.tokenC, totalTokenA);
        require(tokenCReceived >= params.minTokenCAmount, "Insufficient output");

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
            borrowedLiquidity: borrowedTokens,
            tokenCHolding: tokenCReceived,
            leverage: params.leverage,
            openPrice: _getPoolPrice(params.tradingPool),
            openTimestamp: block.timestamp,
            isActive: true
        });

        crossPoolPositions[positionId] = position;
        userCrossPoolPositions[params.user].push(positionId);
        positionBorrowedLiquidity[positionId] = borrowedTokens;

        emit CrossPoolPositionOpened(positionId, params.user, params.leverage, tokenCReceived);
        return positionId;
    }

    function closeCrossPoolPosition(
        bytes32 positionId
    ) external onlyAuthorized validPosition(positionId) nonReentrant returns (uint256 userProceeds) {
        CrossPoolPosition storage position = crossPoolPositions[positionId];
        uint256 tokenAReceived = _executeSwap(position.tradingPool, position.tokenC, position.tokenA, position.tokenCHolding);

        uint256 leverageAmount = position.collateralAmount * (position.leverage - 1);
        uint256 repaymentFee = (leverageAmount * 300) / 10000;
        uint256 totalRepayment = leverageAmount + repaymentFee;
        require(tokenAReceived >= totalRepayment, "Insufficient funds for repayment");

        _repayLiquidityToPool(position.borrowPool, position.borrowedLiquidity, totalRepayment);
        userProceeds = tokenAReceived - totalRepayment;

        if (userProceeds > 0) {
            IERC20(position.tokenA).safeTransfer(position.userWallet, userProceeds);
        }

        position.isActive = false;
        delete positionBorrowedLiquidity[positionId];
        emit CrossPoolPositionClosed(positionId, position.user, userProceeds);
        return userProceeds;
    }

    function _borrowLiquidityFromPool(PoolKey memory poolKey, uint256 tokenAmount) internal returns (uint256 liquidityBorrowed) {
        PoolId poolId = poolKey.toId();
        uint128 availableLiquidity = poolManager.getLiquidity(poolId);
        uint256 liquidityToRemove = availableLiquidity > 0 ? uint256(availableLiquidity) / 1000 : 1;
        if (tokenAmount < 1e18) {
            liquidityToRemove = (liquidityToRemove * tokenAmount) / 1e6;
        }
        if (liquidityToRemove < 1000) {
            liquidityToRemove = 1000;
        }
        if (liquidityToRemove > uint256(availableLiquidity) / 20) {
            liquidityToRemove = uint256(availableLiquidity) / 20;
        }

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -887220,
            tickUpper: 887220,
            liquidityDelta: -int256(liquidityToRemove),
            salt: 0
        });

        bytes memory callData = abi.encodeWithSelector(this._unlockModifyLiquidity.selector, poolKey, params);
        bytes memory result = poolManager.unlock(callData);
        (BalanceDelta callerDelta,) = abi.decode(result, (BalanceDelta, BalanceDelta));

        address tokenA = Currency.unwrap(poolKey.currency0);
        address tokenB = Currency.unwrap(poolKey.currency1);
        liquidityBorrowed = tokenA < tokenB ?
            (callerDelta.amount0() < 0 ? uint256(-int256(callerDelta.amount0())) : uint256(int256(callerDelta.amount0()))) :
            (callerDelta.amount1() < 0 ? uint256(-int256(callerDelta.amount1())) : uint256(int256(callerDelta.amount1())));

        poolBorrowedLiquidity[poolId] += liquidityBorrowed;
        emit LiquidityBorrowed(bytes32(0), poolId, liquidityBorrowed);
        return liquidityBorrowed;
    }

    function _repayLiquidityToPool(PoolKey memory poolKey, uint256 liquidityAmount, uint256 tokenAmount) internal {
        PoolId poolId = poolKey.toId();
        if (poolBorrowedLiquidity[poolId] >= liquidityAmount) {
            poolBorrowedLiquidity[poolId] -= liquidityAmount;
        } else {
            poolBorrowedLiquidity[poolId] = 0;
        }
        emit LiquidityRepaid(bytes32(0), poolId, liquidityAmount);
    }

    function _executeSwap(PoolKey memory poolKey, address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        require(amountIn > 0 && amountIn <= MAX_INT128, "Invalid input amount");
        require(IERC20(tokenIn).balanceOf(address(this)) >= amountIn, "Insufficient token balance");
        require(IERC20(tokenIn).approve(address(poolManager), amountIn), "Approval failed");

        bool zeroForOne = tokenIn < tokenOut;
        SwapParams memory swapParams = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        bytes memory callData = abi.encodeWithSelector(this._unlockSwap.selector, poolKey, swapParams);
        bytes memory result = poolManager.unlock(callData);
        BalanceDelta delta = abi.decode(result, (BalanceDelta));

        amountOut = zeroForOne ?
            (delta.amount1() < 0 ? uint256(-int256(delta.amount1())) : uint256(int256(delta.amount1()))) :
            (delta.amount0() < 0 ? uint256(-int256(delta.amount0())) : uint256(int256(delta.amount0())));
        require(amountOut > 0, "Zero output amount");
    }

    function _getPoolPrice(PoolKey memory poolKey) internal view returns (uint256) {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());
        require(sqrtPriceX96 > 0, "Invalid pool price");
        return (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) >> 192;
    }

    function setLeverageController(address _leverageController) external onlyOwner {
        leverageController = ILeverageController(_leverageController);
        authorizedContracts[_leverageController] = true;
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only PoolManager");
        (bool success, bytes memory result) = address(this).call(data);
        require(success, "Unlock callback failed");
        return result;
    }

    function _unlockModifyLiquidity(PoolKey memory poolKey, ModifyLiquidityParams memory params) external returns (BalanceDelta, BalanceDelta) {
        require(msg.sender == address(this), "Only self");
        (BalanceDelta callerDelta, BalanceDelta feesAccrued) = poolManager.modifyLiquidity(poolKey, params, "");
        
        if (callerDelta.amount0() < 0) {
            address token0 = Currency.unwrap(poolKey.currency0);
            uint256 owed = uint256(uint128(-callerDelta.amount0()));
            require(IERC20(token0).balanceOf(address(this)) >= owed, "Insufficient token0");
            poolManager.sync(poolKey.currency0);
            IERC20(token0).transfer(address(poolManager), owed);
            poolManager.settle();
        } else if (callerDelta.amount0() > 0) {
            poolManager.take(poolKey.currency0, address(this), uint256(uint128(callerDelta.amount0())));
        }

        if (callerDelta.amount1() < 0) {
            address token1 = Currency.unwrap(poolKey.currency1);
            uint256 owed = uint256(uint128(-callerDelta.amount1()));
            require(IERC20(token1).balanceOf(address(this)) >= owed, "Insufficient token1");
            poolManager.sync(poolKey.currency1);
            IERC20(token1).transfer(address(poolManager), owed);
            poolManager.settle();
        } else if (callerDelta.amount1() > 0) {
            poolManager.take(poolKey.currency1, address(this), uint256(uint128(callerDelta.amount1())));
        }

        return (callerDelta, feesAccrued);
    }

    function _unlockSwap(PoolKey memory poolKey, SwapParams memory params) external returns (BalanceDelta) {
        require(msg.sender == address(this), "Only self");
        BalanceDelta delta = poolManager.swap(poolKey, params, "");

        if (delta.amount0() < 0) {
            address token0 = Currency.unwrap(poolKey.currency0);
            uint256 owed = uint256(uint128(-delta.amount0()));
            require(IERC20(token0).balanceOf(address(this)) >= owed, "Insufficient token0");
            poolManager.sync(poolKey.currency0);
            IERC20(token0).transfer(address(poolManager), owed);
            poolManager.settle();
        } else if (delta.amount0() > 0) {
            poolManager.take(poolKey.currency0, address(this), uint256(uint128(delta.amount0())));
        }

        if (delta.amount1() < 0) {
            address token1 = Currency.unwrap(poolKey.currency1);
            uint256 owed = uint256(uint128(-delta.amount1()));
            require(IERC20(token1).balanceOf(address(this)) >= owed, "Insufficient token1");
            poolManager.sync(poolKey.currency1);
            IERC20(token1).transfer(address(poolManager), owed);
            poolManager.settle();
        } else if (delta.amount1() > 0) {
            poolManager.take(poolKey.currency1, address(this), uint256(uint128(delta.amount1())));
        }

        return delta;
    }

    receive() external payable {}
}