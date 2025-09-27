# Uniswap V4 Leverage Trading System

## 📋 Overview

A decentralized leverage trading platform built on Uniswap V4 that enables users to execute leveraged trades using the same pools for both trading and liquidity provision. The system provides atomic execution with real-time position monitoring and automatic profit/loss distribution.

## 🏗️ System Architecture

### Core Components

1. **WalletFactory.sol & UserWallet.sol** - Non-custodial fund management
2. **InstantLeverageHook.sol** - Uniswap V4 hook for atomic leverage execution
3. **LeverageController.sol** - Orchestrates leverage operations and risk management
4. **ILeverageInterfaces.sol** - Interface definitions

## 💰 Fund Flow Mechanics

### Leverage Trade Execution Flow

```
1. User deposits 100 TEST0 → UserWallet
2. User requests 5x leverage trade: TEST0 → TEST1
3. System borrows 400 TEST0 from TEST0/TEST1 pool (temporary)
4. Executes swap: 500 TEST0 → TEST1 on same pool
5. Repays pool: 400 TEST0 equivalent + 3% fee
6. User receives leveraged TEST1 position (97% of profits)
```

### Atomic Execution Details

```solidity
// 1. Borrow from pool (remove liquidity temporarily)
_borrowFromPool(poolKey, tokenIn, leverageAmount);

// 2. Execute leveraged swap
_executeSwap(poolKey, tokenIn, tokenOut, totalAmount);

// 3. Repay pool with fees
_repayPool(poolKey, tokenOut, repaymentAmount);

// 4. Store user position
_createPosition(request, finalOutputAmount, openPrice);
```

## 👤 User Journey

### Step 1: Setup Account
```solidity
// Create user wallet
address userWallet = walletFactory.createUserAccount();

// Deposit funds
walletFactory.depositFunds(TEST0, 1000 * 1e18);
```

### Step 2: Set Trading Delegation
```solidity
// Create delegation for leverage trades
bytes32 delegationHash = keccak256(abi.encode(user, maxAmount, deadline));
userWallet.setDelegation(delegationHash, maxAmount, deadline, signature);
```

### Step 3: Request Leverage Trade
```solidity
ILeverageController.TradeRequestParams memory params = ILeverageController.TradeRequestParams({
    poolKey: poolKey,
    tokenIn: TEST0,
    tokenOut: TEST1,
    baseAmount: 100 * 1e18,
    leverageMultiplier: 5,
    minOutputAmount: 450 * 1e18,
    delegationHash: delegationHash,
    deadline: block.timestamp + 1 hours
});

bytes32 requestId = leverageController.requestLeverageTrade(params);
```

### Step 4: Execute Trade
```solidity
bool success = leverageController.executeLeverageTrade(requestId, poolKey);
```

### Step 5: Monitor Position
```solidity
// Check position health
(uint256 currentValue, uint256 liquidationThreshold, bool isHealthy, int256 pnl) =
    leverageController.getPositionHealth(requestId, currentPrice);

// Get position details
IInstantLeverageHook.LeveragePosition memory position =
    leverageHook.getPosition(requestId);
```

### Step 6: Close Position
```solidity
bool success = leverageController.closeLeveragePosition(requestId, poolKey);
```

## 🔧 Key Functions Reference

### WalletFactory.sol

| Function | Description | Access |
|----------|-------------|--------|
| `createUserAccount()` | Creates new user wallet | Public |
| `depositFunds(token, amount)` | Deposits ERC20 tokens | Public |
| `depositETH()` | Deposits ETH | Public |
| `addToken(token)` | Whitelist new token | Owner |

### UserWallet.sol

| Function | Description | Access |
|----------|-------------|--------|
| `setDelegation(hash, amount, expiry, sig)` | Sets trading delegation | Owner |
| `executeTrade(token, amount, data, hash)` | Executes delegated trade | Platform |
| `withdraw(token, amount)` | Withdraws funds | Owner |
| `balances(token)` | Check token balance | View |

### LeverageController.sol

| Function | Description | Access |
|----------|-------------|--------|
| `requestLeverageTrade(params)` | Request leverage trade | Public |
| `executeLeverageTrade(requestId, poolKey)` | Execute leverage trade | Public |
| `closeLeveragePosition(requestId, poolKey)` | Close position | User |
| `getPositionHealth(requestId, price)` | Check position health | View |
| `getUserActivePositions(user)` | Get user's positions | View |
| `configurePool(poolKey, params)` | Configure pool settings | Owner |

### InstantLeverageHook.sol

| Function | Description | Access |
|----------|-------------|--------|
| `executeLeverageTrade(poolKey, request)` | Execute atomic leverage | Controller |
| `closeLeveragePosition(params)` | Close user position | Authorized |
| `getPoolPrice(poolKey)` | Get current pool price | View |
| `getPosition(requestId)` | Get position details | View |
| `checkLiquidation(requestId, price)` | Check liquidation | Public |

## 🧪 Testing Guide

### Prerequisites

```bash
# Install dependencies
forge install

# Set up environment variables
cp .env.example .env
# Edit .env with your values
```

### Deploy System

```bash
# 1. Check contract sizes
forge script script/CheckSizes.s.sol

# 2. Deploy contracts
forge script script/DeployLeverageSystem.s.sol --broadcast --rpc-url $RPC_URL

# 3. Configure pools
forge script script/ConfigurePools.s.sol --broadcast --rpc-url $RPC_URL
```

### Test Scenarios

#### Test 1: Basic Leverage Trade
```solidity
// Setup
address user = makeAddr("user");
deal(TEST0, user, 1000e18);

// Create wallet and deposit
vm.startPrank(user);
address userWallet = walletFactory.createUserAccount();
IERC20(TEST0).approve(address(walletFactory), 100e18);
walletFactory.depositFunds(TEST0, 100e18);

// Set delegation
bytes32 delegationHash = keccak256(abi.encode(user, 100e18, block.timestamp + 1 hours));
// ... sign delegation
userWallet.setDelegation(delegationHash, 100e18, block.timestamp + 1 hours, signature);

// Request and execute trade
bytes32 requestId = leverageController.requestLeverageTrade(params);
bool success = leverageController.executeLeverageTrade(requestId, poolKey);
vm.stopPrank();

assertEq(success, true);
```

#### Test 2: Position Liquidation
```solidity
// Execute trade with high leverage
bytes32 requestId = _executeLeverageTrade(user, 10); // 10x leverage

// Simulate price drop
_manipulatePoolPrice(poolKey, -50); // 50% price drop

// Check liquidation
bool liquidated = leverageController.checkLiquidation(requestId, poolKey);
assertEq(liquidated, true);
```

#### Test 3: Profitable Position Closure
```solidity
// Execute trade
bytes32 requestId = _executeLeverageTrade(user, 5);

// Simulate price increase
_manipulatePoolPrice(poolKey, 20); // 20% price increase

// Close position
bool success = leverageController.closeLeveragePosition(requestId, poolKey);
assertEq(success, true);

// Check user received profits
uint256 finalBalance = UserWallet(userWallet).balances(TEST0);
assertGt(finalBalance, initialBalance);
```

### Integration Tests

```bash
# Run full test suite
forge test

# Run specific test files
forge test --match-contract LeverageSystemTest
forge test --match-test testBasicLeverageTrade

# Run with verbose output
forge test -vvv
```

## 🛡️ Risk Management

### Position Health Monitoring

```solidity
// Liquidation threshold = initialNotional / leverageMultiplier
// Example: $1000 position with 5x leverage liquidates at $200

uint256 liquidationThreshold = position.initialNotional / position.leverageMultiplier;
bool isHealthy = currentValue > liquidationThreshold;
```

### Safety Features

- **Atomic execution**: All operations succeed or revert entirely
- **Real-time pricing**: Uses pool's own price for position valuation
- **Auto-liquidation**: Positions automatically liquidated when unhealthy
- **Fee distribution**: 97% profits to users, 3% to pools
- **Emergency controls**: Owner can pause system and force-close positions

## 💡 Advanced Usage

### Batch Operations

```solidity
// Check multiple positions for liquidation
bytes32[] memory requestIds = leverageController.getUserActivePositions(user);
uint256 liquidatedCount = leverageController.batchCheckLiquidations(requestIds, poolKey);
```

### Pool Configuration

```solidity
// Configure custom pool parameters
leverageController.configurePool(
    poolKey,
    true,   // active
    8,      // 8x max leverage
    9000,   // 90% max utilization
    250     // 0.25% base fee
);
```

### Price Oracle Integration

```solidity
// Get real-time pool price
uint256 currentPrice = leverageHook.getPoolPrice(poolKey);

// Calculate position value
uint256 positionValue = (position.outputTokenAmount * currentPrice) / position.openPrice;
```

## 🔍 Monitoring & Analytics

### Position Tracking

```solidity
// Get all user positions
bytes32[] memory positions = leverageController.getUserActivePositions(user);

// Check position details
for (uint i = 0; i < positions.length; i++) {
    IInstantLeverageHook.LeveragePosition memory pos = leverageHook.getPosition(positions[i]);
    (uint256 currentValue,,bool isHealthy, int256 pnl) =
        leverageController.getPositionHealth(positions[i], currentPrice);

    console.log("Position:", positions[i]);
    console.log("Current Value:", currentValue);
    console.log("P&L:", pnl);
    console.log("Healthy:", isHealthy);
}
```

### Pool Utilization

```solidity
// Check pool lending status
(uint256 totalLent, uint256 maxLendingLimit,, bool isActive) =
    leverageHook.poolInfo(poolId);

uint256 utilizationRate = (totalLent * 10000) / maxLendingLimit; // basis points
```

## 🚨 Common Issues & Solutions

### Issue: Transaction Reverts

**Cause**: Insufficient user balance or invalid delegation

**Solution**:
```solidity
// Check user balance
uint256 balance = UserWallet(userWallet).balances(tokenIn);
require(balance >= baseAmount, "Insufficient balance");

// Verify delegation
(bool active, uint256 maxAmount, uint256 expiry) =
    UserWallet(userWallet).delegations(delegationHash);
require(active && block.timestamp < expiry, "Invalid delegation");
```

### Issue: Position Liquidated Unexpectedly

**Cause**: High leverage with volatile price movements

**Solution**:
- Use lower leverage multipliers (2-3x instead of 10x)
- Monitor position health regularly
- Set up automated position management

### Issue: Hook Address Mismatch

**Cause**: Incorrect hook mining or deployment

**Solution**:
```bash
# Re-mine hook address with correct parameters
forge script script/DeployLeverageSystem.s.sol --broadcast
```

## 📊 Economics

### Fee Structure

- **Pool Fee**: 3% of profits go to liquidity providers
- **User Profit**: 97% of profits go to users
- **Base Fee**: Configurable per pool (typically 0.3-0.5%)

### Example Trade Economics

```
Initial: 100 TEST0 (5x leverage = 500 TEST0 total)
Pool provides: 400 TEST0 temporarily
Swap: 500 TEST0 → 520 TEST1 (4% gain)
Repay pool: 400 TEST0 equivalent + 3% fee
User receives: ~116 TEST0 equivalent (16% gain on 100 TEST0)
```

## 🔗 Contract Addresses

After deployment, update these addresses in your `.env`:

```bash
POOL_MANAGER_ADDRESS=0x...
USER_WALLET_TEMPLATE_ADDRESS=0x...
WALLET_FACTORY_ADDRESS=0x...
INSTANT_LEVERAGE_HOOK_ADDRESS=0x...
LEVERAGE_CONTROLLER_ADDRESS=0x...
```

## 📝 License

MIT License - See LICENSE file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Add comprehensive tests
4. Submit a pull request

For questions or support, please open an issue on GitHub.