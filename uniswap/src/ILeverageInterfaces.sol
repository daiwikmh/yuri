// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/types/PoolKey.sol";

// ============ Wallet Interfaces ============

interface IWalletFactory {
    function userAccounts(address user) external view returns (address payable, bool, uint256);
    function createUserAccount() external returns (address payable userWallet);
    function addToken(address token) external;
    function allowedTokens(address token) external view returns (bool);
    function depositFunds(address token, uint256 amount) external;
}

interface IUserWallet {
    function executeTrade(
        address token,
        uint256 amount,
        bytes calldata data,
        bytes32 delegationHash
    ) external returns (bool success);
    function creditBalance(address token, uint256 amount) external;
    function balances(address token) external view returns (uint256);
    function delegations(bytes32 hash) external view returns (bool active, uint256 maxAmount, uint256 expiry);
}

// ============ Leverage System Structs ============

struct InstantLeverageRequest {
    bytes32 requestId;
    address user;
    address userWallet;
    address tokenIn;
    address tokenOut;
    uint256 userBaseAmount;
    uint256 leverageMultiplier;
    uint256 minOutputAmount;
    PoolKey targetPoolKey;
}

// ============ Leverage Controller Interface ============

interface ILeverageController {
    struct TradeRequestParams {
        PoolKey poolKey;
        address tokenIn;
        address tokenOut;
        uint256 baseAmount;
        uint256 leverageMultiplier;
        uint256 minOutputAmount;
        bytes32 delegationHash;
        uint256 deadline;
    }

    function poolConfigs(bytes32 poolId) external view returns (
        bool active,
        uint256 maxLeverageForPool,
        uint256 maxUtilization,
        uint256 baseFeeRate
    );

    function requestLeverageTrade(TradeRequestParams calldata params) external returns (bytes32 requestId);

    function executeLeverageTrade(
        bytes32 requestId,
        PoolKey calldata poolKey
    ) external returns (bool success);

    function closeLeveragePosition(
        bytes32 requestId,
        PoolKey calldata poolKey
    ) external returns (bool success);

    function configurePool(
        PoolKey calldata poolKey,
        bool active,
        uint256 maxLeverage,
        uint256 maxUtilization,
        uint256 baseFeeRate
    ) external;
}

// ============ Leverage Hook Interface ============

interface IInstantLeverageHook {
    struct LeveragePosition {
        address user;
        address userWallet;
        address tokenIn;
        address tokenOut;
        uint256 initialNotional;
        uint256 userContribution;
        uint256 leverageAmount;
        uint256 leverageMultiplier;
        uint256 outputTokenAmount;
        uint256 openPrice;
        uint256 liquidationThreshold;
        uint256 openTimestamp;
        bool isOpen;
    }

    struct ClosePositionParams {
        bytes32 requestId;
        PoolKey poolKey;
    }

    function getPosition(bytes32 requestId) external view returns (LeveragePosition memory);
    function getPoolPrice(PoolKey calldata key) external view returns (uint256);
    function closeLeveragePosition(ClosePositionParams calldata params) external returns (bool);
    function checkLiquidation(bytes32 requestId, uint256 currentPrice) external returns (bool);
    function getPositionHealth(
        bytes32 requestId,
        uint256 currentPrice
    ) external view returns (
        uint256 currentValue,
        uint256 liquidationThreshold,
        bool isHealthy,
        int256 pnl
    );
    function getUserPositions(address user) external view returns (bytes32[] memory);
    function authorizePlatform(address platform) external;
    function executeLeverageTrade(
        PoolKey calldata poolKey,
        InstantLeverageRequest memory request
    ) external returns (uint256 outputAmount, uint256 openPrice);

    function borrowFromPool(
        PoolKey calldata poolKey,
        address token,
        uint256 amount
    ) external returns (uint256 borrowed);

    function repayToPool(
        PoolKey calldata poolKey,
        address token,
        uint256 amount
    ) external;
}

// ============ Cross-Pool Asset Manager Interface ============

interface ICrossPoolAssetManager {
    struct CrossPoolTradeParams {
        address user;
        address userWallet;
        PoolKey borrowPool;      // Pool A/B
        PoolKey tradingPool;     // Pool B/C
        address tokenA;          // Collateral token
        address tokenB;          // Bridge token
        address tokenC;          // Target token
        uint256 collateralAmount;
        uint256 leverage;
        uint256 minTokenCAmount;
    }

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
        uint256 borrowedTokenB;
        uint256 tokenCHolding;
        uint256 leverage;
        uint256 openPrice;
        uint256 openTimestamp;
        bool isActive;
    }

    function executeCrossPoolTrade(
        CrossPoolTradeParams memory params
    ) external returns (bytes32 positionId);

    function closeCrossPoolPosition(
        bytes32 positionId
    ) external returns (uint256 userProceeds);

    function getCrossPoolPositionHealth(
        bytes32 positionId
    ) external view returns (
        uint256 currentValue,
        uint256 liquidationThreshold,
        bool isHealthy,
        int256 pnl
    );

    function getUserCrossPoolPositions(address user) external view returns (bytes32[] memory);
    function getCrossPoolPosition(bytes32 positionId) external view returns (CrossPoolPosition memory);
}