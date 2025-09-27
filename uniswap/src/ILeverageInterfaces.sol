// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/types/PoolKey.sol";

/**
 * @title ILeverageInterfaces
 * @notice Centralized interface definitions for the leverage trading system
 * @dev Prevents duplicate interface declarations across contracts
 */

interface IWalletFactory {
    struct AccountInfo {
        address payable walletAddress;
        bool exists;
        uint256 createdAt;
    }

    function userAccounts(address user) external view returns (address payable, bool, uint256);
    function allowedTokens(address token) external view returns (bool);
    function createUserAccount() external returns (address payable userWallet);
    function depositFunds(address token, uint256 amount) external;
    function depositETH() external payable;
    function addToken(address token) external;
    function removeToken(address token) external;
    function getAllowedTokens() external view returns (address[] memory);
}

interface IUserWallet {
    struct Delegation {
        bool active;
        uint256 maxTradeAmount;
        uint256 expiry;
    }

    function owner() external view returns (address);
    function platform() external view returns (address);
    function balances(address token) external view returns (uint256);
    function delegations(bytes32 hash) external view returns (bool, uint256, uint256);
    function initialize(address _owner, address _platform) external;
    function creditBalance(address token, uint256 amount) external;
    function setDelegation(bytes32 delegationHash, uint256 maxTradeAmount, uint256 expiry, bytes calldata signature) external;
    function executeTrade(address tokenIn, uint256 amount, bytes calldata tradeData, bytes32 delegationHash) external;
    function withdraw(address token, uint256 amount) external;
}

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
        uint256 openPrice;
        uint256 liquidationThreshold;
        uint256 openTimestamp;
        bool isOpen;
    }

    struct InstantLeverageRequest {
        address user;
        address userWallet;
        address tokenIn;
        address tokenOut;
        uint256 userBaseAmount;
        uint256 leverageMultiplier;
        uint256 minOutputAmount;
        bytes32 delegationHash;
        bytes32 requestId;
    }

    function leveragePositions(bytes32 requestId) external view returns (LeveragePosition memory);
    function closeLeveragePosition(bytes32 requestId, uint256 currentPrice) external returns (bool);
    function checkLiquidation(bytes32 requestId, uint256 currentPrice) external returns (bool);
    function getPositionHealth(bytes32 requestId, uint256 currentPrice) external view returns (uint256, uint256, bool, int256);
    function getUserPositions(address user) external view returns (bytes32[] memory);
    function getPoolPrice(PoolKey calldata key) external view returns (uint256);
    function authorizePlatform(address platform) external;
}

interface ILeverageController {
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
        uint256 maxUtilization;
        uint256 baseFeeRate;
    }

    function requestLeverageTrade(
        PoolKey calldata poolKey,
        address tokenIn,
        address tokenOut,
        uint256 baseAmount,
        uint256 leverageMultiplier,
        uint256 minOutputAmount,
        bytes32 delegationHash,
        uint256 deadline
    ) external returns (bytes32 requestId);

    function executeLeverageTrade(bytes32 requestId, PoolKey calldata poolKey) external returns (bool success);
    function closeLeveragePosition(bytes32 requestId, PoolKey calldata poolKey) external returns (bool success);
    function checkLiquidation(bytes32 requestId, PoolKey calldata poolKey) external returns (bool liquidated);
    function getPositionHealth(bytes32 requestId, uint256 currentPrice) external view returns (uint256, uint256, bool, int256);
    function getUserActivePositions(address user) external view returns (bytes32[] memory);
    function canExecuteLeverageTrade(address user, PoolKey calldata poolKey, address tokenIn, uint256 baseAmount, uint256 leverageMultiplier, bytes32 delegationHash) external view returns (bool, string memory);
}