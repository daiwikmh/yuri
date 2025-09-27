# Uniswap V4 Leverage Trading System

A comprehensive leverage trading platform built on Uniswap V4 that enables users to execute leveraged trades without collateral requirements through atomic smart contract interactions.

## System Overview

The system consists of four main contracts that work together to provide seamless leverage trading:

### 1. WalletFactory.sol & UserWallet.sol
- **Purpose**: User onboarding and non-custodial fund management
- **Features**:
  - Clone-based wallet deployment for gas efficiency
  - Delegation-based permission system for secure trade execution
  - Support for TEST0/TEST1/ETH tokens
  - User-controlled fund withdrawal and deposit

### 2. InstantLeverageHook.sol
- **Purpose**: Uniswap V4 hook for atomic leverage execution
- **Features**:
  - Up to 10x leverage without collateral requirements
  - Automatic profit/loss distribution (3% to pool, 97% to user)
  - Real-time liquidation at 1/leverage threshold
  - Pool-sourced temporary liquidity for trades
  - Real-time pricing from Uniswap V4 pools

### 3. LeverageController.sol
- **Purpose**: Main orchestrator for the leverage system
- **Features**:
  - Trade request management and validation
  - Position lifecycle management
  - Risk management and pool utilization monitoring
  - Batch liquidation processing
  - Emergency controls

### 4. ILeverageInterfaces.sol
- **Purpose**: Centralized interface definitions
- **Features**:
  - Prevents code duplication across contracts
  - Ensures consistency in contract interactions
  - Type safety for all system components

## Key Features

### Zero-Collateral Leverage
- Users can open leveraged positions up to 10x without posting collateral
- Leverage is provided by temporarily borrowing from Uniswap V4 pools
- Atomic execution ensures borrowing and repayment happen in single transaction

### Automatic Profit/Loss Settlement
- **Profitable trades**: 97% to user, 3% to pool as fee
- **Loss trades**: Pool gets priority repayment, user receives remainder
- **Liquidations**: Triggered when position value falls below 1/leverage threshold

### Real-Time Risk Management
- Continuous position health monitoring
- Dynamic fee adjustment based on pool utilization
- Emergency pause and liquidation mechanisms
- Batch processing for gas-efficient operations

### Non-Custodial Design
- Users maintain full control of their funds in smart wallets
- Delegation system allows secure trade execution
- Platform cannot access user funds without proper delegation

## Contract Addresses (Testnet)

Configure these in your environment:
```bash
POOL_MANAGER_ADDRESS=<deployed_address>
USER_WALLET_TEMPLATE_ADDRESS=<deployed_address>
WALLET_FACTORY_ADDRESS=<deployed_address>
INSTANT_LEVERAGE_HOOK_ADDRESS=<deployed_address>
LEVERAGE_CONTROLLER_ADDRESS=<deployed_address>
```

## Token Addresses (Testnet)

```bash
TEST0=0x5c4B14CB096229226D6D464Cba948F780c02fbb7
TEST1=0x70bF7e3c25B46331239fD7427A8DD6E45B03CB4c
ETH=0x0000000000000000000000000000000000000000
```

## Usage Flow

### 1. User Onboarding
```solidity
// Create user wallet
address payable userWallet = walletFactory.createUserAccount();

// Deposit funds
walletFactory.depositFunds(TEST0, amount);
```

### 2. Setting Up Delegation
```solidity
// User signs delegation off-chain, then calls:
userWallet.setDelegation(
    delegationHash,
    maxTradeAmount,
    expiry,
    signature
);
```

### 3. Requesting Leverage Trade
```solidity
bytes32 requestId = leverageController.requestLeverageTrade(
    poolKey,
    tokenIn,
    tokenOut,
    baseAmount,
    leverageMultiplier, // 2-10x
    minOutputAmount,
    delegationHash,
    deadline
);
```

### 4. Executing Trade
```solidity
bool success = leverageController.executeLeverageTrade(requestId, poolKey);
```

### 5. Position Management
```solidity
// Check position health
(uint256 currentValue, uint256 liquidationThreshold, bool isHealthy, int256 pnl) =
    leverageController.getPositionHealth(requestId, currentPrice);

// Close position
bool closed = leverageController.closeLeveragePosition(requestId, poolKey);

// Check for liquidation
bool liquidated = leverageController.checkLiquidation(requestId, poolKey);
```

## Security Features

### Input Validation
- Comprehensive parameter validation at all entry points
- Slippage protection for all trades
- Deadline enforcement for time-sensitive operations

### Access Controls
- Owner-only functions for critical system parameters
- Platform authorization for hook interactions
- User-only functions for wallet operations

### Risk Management
- Maximum leverage limits (global and per-pool)
- Pool utilization caps to prevent over-leveraging
- Emergency pause functionality
- Automatic liquidation triggers

### Atomic Execution
- All leverage trades execute atomically or revert completely
- No partial execution states that could leave system in inconsistent state
- Proper reentrancy protection throughout

## Deployment

### Prerequisites
```bash
forge install
# Set up environment variables for deployment
```

### Deploy System
```bash
forge script script/DeployLeverageSystem.s.sol --broadcast --rpc-url $RPC_URL
```

### Configure Pools
```solidity
leverageController.configurePool(
    poolKey,
    true,      // active
    5,         // max 5x leverage for this pool
    8000,      // 80% max utilization
    500        // 0.5% base fee
);
```

### Test System
```bash
forge script script/TestLeverageSystem.s.sol --rpc-url $RPC_URL
```

## Architecture Decisions

### Why Uniswap V4 Hooks?
- Atomic execution ensures borrowing and repayment happen in single transaction
- Access to real-time pool prices and liquidity
- Gas-efficient integration with existing DEX infrastructure

### Why Clone-based Wallets?
- Significant gas savings for user onboarding
- Standardized interface across all user wallets
- Upgradeability through factory contract

### Why Delegation-based Permissions?
- Users maintain full custody of funds
- Fine-grained control over trading permissions
- Revocable access for enhanced security

## Gas Optimization

- Clone pattern for wallet deployment
- Batch operations for liquidations
- Efficient storage layout in all contracts
- Minimal external calls in critical paths

## Testing

Comprehensive test suite covers:
- Happy path scenarios for all user flows
- Edge cases and error conditions
- Gas usage optimization
- Security vulnerabilities

Run tests:
```bash
forge test -vv
```

## Recent Fixes & Improvements

### ✅ Compilation Issues Resolved
- **Fixed duplicate interface declarations** - Created centralized `ILeverageInterfaces.sol`
- **Resolved function visibility conflicts** - Corrected internal/external function calls
- **Fixed Uniswap V4 integration** - Updated to use `StateLibrary.getSlot0` for pool price access
- **Improved hook implementation** - Corrected override functions and selectors

### ✅ Enhanced Security Features
- **Added comprehensive input validation** throughout all contracts
- **Implemented atomic execution safety** with proper try-catch patterns
- **Enhanced price calculation accuracy** with fixed-point arithmetic
- **Added batch liquidation processing** for gas efficiency
- **Emergency controls** for position management

### ✅ Gas Optimizations
- **Internal function restructuring** for better gas efficiency
- **Reduced external calls** in critical execution paths
- **Optimized storage layout** in all contracts

## Security Considerations

⚠️ **Important**: This is a demonstration system for ETHGlobal. Before mainnet deployment:

1. Complete professional security audit
2. Implement formal verification for critical functions
3. Add comprehensive monitoring and alerting
4. Establish proper governance mechanisms
5. Test thoroughly on testnets with various market conditions
6. Verify all hook implementations with Uniswap V4 standards

## License

MIT License - See LICENSE file for details.