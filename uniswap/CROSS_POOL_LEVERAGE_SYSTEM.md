# Cross-Pool Leverage Trading System

## 🎯 System Overview

The Cross-Pool Leverage Trading System enables users to:
1. **Borrow liquidity from Pool A/B** using Token A as collateral
2. **Trade in Pool B/C** with leveraged exposure to Token C
3. **Maintain positions** with automated liquidation protection
4. **Close positions** with automatic repayment to Pool A/B

### Current Status:  Pool A/B Ready

- **Pool A/B**: TEST0/TEST1 with liquidity position #5598
- **Next**: Deploy Pool B/C and AssetManager for cross-pool operations

---

## 🏗️ Architecture Components

### 1. Core Contracts ( Deployed)
- **PoolManager**: `0x00B036B58a818B1BC34d502D3fE730Db729e62AC`
- **PositionManager**: `0xf969Aee60879C54bAAed9F3eD26147Db216Fd664`
- **InstantLeverageHook**: `0x3143D8279c90DdFAe5A034874C5d232AF88b03c0`
- **LeverageController**: `0x725212999a45ABCb651A84b96C70438C6c1d7c43`

### 2. Token Setup ( Ready)
- **TEST0 (Token A)**: `0xB08D5e594773C55b2520a646b4EB3AA5fA08aF21`
- **TEST1 (Token B)**: `0xe3A426896Ca307c3fa4A818f2889F44582460954`
- **Pool A/B Liquidity**: Position #5598 with 50 tokens each

### 3. Next Components (🚧 To Deploy)
- **AssetManager**: Cross-pool position management
- **Pool B/C**: TEST1/TEST2 trading pool
- **Cross-pool trading scripts**

---

## 📋 Deployment Progress

###  Completed Steps

1. **System Deployment** (`make deploy-lev`)
   -  Core contracts deployed
   -  Hook permissions configured
   -  Wallet factory setup

2. **Pool Configuration** (`make create-pool`)
   -  Leverage parameters set
   -  Pool A/B configured for 5x max leverage
   -  Global leverage limit: 10x

3. **Pool Initialization** (`make initialize`)
   -  Pool A/B initialized at 1:1 price
   -  Pool state ready for liquidity

4. **Liquidity Provision** (`make liquid`)
   -  Permit2 approvals configured
   -  50 TEST0 + 50 TEST1 added to Pool A/B
   -  Position token #5598 minted

### 🚧 Next Steps

#### Step 1: Deploy AssetManager
```bash
# Deploy the cross-pool asset manager
make deploy-asset-manager

# Expected output: AssetManager contract address
# Update .env with ASSET_MANAGER_ADDRESS
```

#### Step 2: Create Pool B/C
```bash
# Deploy TEST2 token (Token C)
make deploy-test2

# Initialize Pool B/C (TEST1/TEST2)
make initialize-pool-bc

# Add liquidity to Pool B/C
make liquid-pool-bc
```

#### Step 3: Configure Cross-Pool System
```bash
# Set up cross-pool permissions and parameters
make configure-cross-pool

# Test cross-pool trading functionality
make test-cross-pool
```

---

## 🔄 Cross-Pool Trading Flow

### The Leverage Mechanism

```
User Collateral: 100 TEST0 (Token A)
Leverage: 2x
Expected Flow:

1. Pool A/B Operation:
   ├─ Borrow: 100 TEST1 (Token B) using 100 TEST0 collateral
   ├─ Total trading power: 200 TEST1 equivalent
   └─ Pool A/B liquidity temporarily reduced

2. Pool B/C Operation:
   ├─ Trade: 200 TEST1 → TEST2 (Token C)
   ├─ User holds: ~200 TEST2 (depending on B/C price)
   └─ Position: 2x leveraged exposure to TEST2

3. Position Management:
   ├─ AssetManager holds TEST2 on behalf of user
   ├─ Liquidation threshold: 150 TEST1 equivalent
   └─ Auto-liquidation if TEST2 value < threshold

4. Position Closure:
   ├─ Trade: TEST2 → TEST1 (via Pool B/C)
   ├─ Repay: 100 TEST1 + fees to Pool A/B
   ├─ Return: Remaining TEST1 converted to TEST0
   └─ Profit/Loss: (Final TEST0) - (Initial 100 TEST0)
```

### Key Features

- **Atomic Execution**: All operations happen in single transaction
- **Automated Liquidation**: Protects both user and pool liquidity
- **Cross-Pool Arbitrage**: Enables complex trading strategies
- **Gas Optimization**: Minimal transaction overhead

---

## 🛠️ Development Commands

### Current Working Commands
```bash
# Deploy system
make deploy-lev

# Configure pools
make create-pool

# Initialize pools
make initialize

# Add liquidity
make liquid
```

### Commands To Implement
```bash
# Deploy AssetManager
make deploy-asset-manager

# Deploy TEST2 token
make deploy-test2

# Cross-pool operations
make initialize-pool-bc
make liquid-pool-bc
make configure-cross-pool

# Trading operations
make cross-pool-trade AMOUNT=100 LEVERAGE=2
make check-position POSITION_ID=0x...
make close-position POSITION_ID=0x...
```

---

## 📊 Current System State

### Pool A/B (TEST0/TEST1)
- **Status**:  Active with liquidity
- **Liquidity**: 50 TEST0 + 50 TEST1
- **Position Token**: #5598
- **Price**: 1:1 ratio
- **Max Leverage**: 5x
- **Max Utilization**: 80%

### Pool B/C (TEST1/TEST2)
- **Status**: 🚧 To be created
- **Required**: TEST2 token deployment
- **Purpose**: Trading pool for leveraged positions

### AssetManager
- **Status**: 🚧 To be deployed
- **Purpose**: Cross-pool position management
- **Features**: Token C custody, liquidation logic

---

## 🎮 Testing Scenarios

### Scenario 1: Basic Cross-Pool Trade
```bash
# 1. User deposits 100 TEST0
# 2. Opens 2x leverage position (200 TEST1 → TEST2)
# 3. Holds leveraged TEST2 exposure
# 4. Closes position for profit/loss in TEST0
```

### Scenario 2: Liquidation Protection
```bash
# 1. Open 5x leverage position
# 2. TEST2 price drops 15%
# 3. Position approaches liquidation threshold
# 4. Automatic liquidation protects Pool A/B
```

### Scenario 3: Multiple Positions
```bash
# 1. Multiple users open cross-pool positions
# 2. Pool A/B liquidity partially utilized
# 3. AssetManager manages multiple TOKEN C holdings
# 4. Independent position management
```

---

## 🔧 Technical Notes

### Permit2 Integration
-  Proper token approvals implemented
-  Two-step approval process (Token → Permit2 → PositionManager)
-  Handles both ERC20 and native ETH

### Hook Architecture
-  beforeSwap/afterSwap for leverage execution
-  beforeRemoveLiquidity/afterRemoveLiquidity for borrowing
-  Authorized platform system for security

### Gas Optimization
- 🚧 Batch operations in single transaction
- 🚧 Minimal external calls during trading
- 🚧 Efficient position state management

---

## 🚀 Ready for Next Phase

The system is now ready to proceed with:

1. **AssetManager Deployment** - Cross-pool position management
2. **Pool B/C Creation** - Trading pool for Token C exposure
3. **Integration Testing** - End-to-end cross-pool leverage trades

**Current Achievement**: Successfully created Pool A/B with liquidity, enabling the borrowing side of cross-pool leverage trading.

**Next Milestone**: Deploy AssetManager and Pool B/C to complete the full cross-pool trading system.