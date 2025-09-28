# 🚀 Cross-Pool Leverage System - Complete Deployment Flow

## 📋 System Overview

**Cross-Pool Leverage Architecture:**
- **Pool A/B** (TEST0/TEST1): Source of borrowing/leverage
- **Pool A/C** (TEST0/TEST2): Target trading pool
- **AssetManager**: Coordinates cross-pool positions
- **UserWallet**: Holds user funds with delegation system
- **LeverageController**: Main trading interface
- **InstantLeverageHook**: Pool integration layer

## 🔧 Prerequisites

1. **Environment Setup:**
```bash
# Required in .env
PRIVATE_KEY=0x...
RPC_URL=https://unichain-sepolia.g.alchemy.com/v2/...
```

2. **Install Dependencies:**
```bash
forge install
```

## 📝 Complete Deployment Sequence

### Step 1: Deploy Test Tokens
```bash
make token
```
**Script:** `MintTokens.s.sol`
**Purpose:** Deploy TEST0, TEST1, TEST2 tokens
**Output:** Updates .env with token addresses

### Step 2: Deploy Core Leverage System
```bash
make deploy-lev
```
**Script:** `DeployLeverageSystem.s.sol`
**Deploys:**
- PoolManager (existing address)
- UserWallet template
- WalletFactory
- InstantLeverageHook (with proper flags)
- LeverageController
**Sets up:** Platform authorizations, token allowances

### Step 3: Initialize Pool A/B (TEST0/TEST1)
```bash
make initialize
```
**Script:** `InitializePools.s.sol`
**Purpose:** Initialize Pool A/B at 1:1 price ratio

### Step 4: Add Liquidity to Pool A/B
```bash
make liquid
```
**Script:** `AddLiquidity.s.sol`
**Purpose:** Add 50 TEST0 + 50 TEST1 liquidity
**Uses:** Permit2 approval system + Position Manager

### Step 5: Initialize Pool A/C (TEST0/TEST2)
```bash
make initialize-pool-ac
```
**Script:** `InitializePoolAC.s.sol`
**Purpose:** Initialize Pool A/C at 1:1 price ratio

### Step 6: Add Liquidity to Pool A/C
```bash
make liquid-ac
```
**Script:** `AddLiquidityAC.s.sol`
**Purpose:** Add 50 TEST0 + 50 TEST2 liquidity

### Step 7: Deploy AssetManager
```bash
make deploy-asset-manager
```
**Script:** `DeployAssetManager.s.sol`
**Purpose:** Deploy cross-pool coordinator
**Authorizes:** AssetManager in LeverageController

## 🎯 Cross-Pool Trading Flow

### User Setup
```bash
# 1. Create user wallet
await walletFactory.createUserAccount()

# 2. Deposit collateral
await test0Token.approve(walletFactory.address, amount)
await walletFactory.depositFunds(test0Address, amount)

# 3. Set delegation for AssetManager
await userWallet.setDelegation(delegationHash, amount, deadline, signature)
```

### Execute Cross-Pool Leverage
```bash
# Example: 10 TEST0 → 2x leveraged TEST2 exposure
make cross-pool-trade AMOUNT=10 LEVERAGE=2
```

**Flow:**
1. **Borrow** 10 TEST1 from Pool A/B using 10 TEST0 collateral
2. **Trade** 20 TEST0 → TEST2 in Pool A/C
3. **Hold** TEST2 for user in AssetManager
4. **Close:** TEST2 → TEST0, repay Pool A/B + fees

## 📊 Contract Addresses (After Deployment)

```bash
# Core System
POOL_MANAGER_ADDRESS=0x00B036B58a818B1BC34d502D3fE730Db729e62AC
WALLET_FACTORY_ADDRESS=0x...
LEVERAGE_CONTROLLER_ADDRESS=0x...
INSTANT_LEVERAGE_HOOK_ADDRESS=0x...
ASSET_MANAGER_ADDRESS=0x...

# Tokens
TEST0_ADDRESS=0x...  # Token A (collateral)
TEST1_ADDRESS=0x...  # Token B (bridge)
TEST2_ADDRESS=0x...  # Token C (target exposure)
```

## 🛠️ Available Commands

### Core Deployment
```bash
make token                 # Deploy test tokens
make deploy-lev           # Deploy leverage system
make initialize           # Initialize Pool A/B
make liquid              # Add liquidity to Pool A/B
make initialize-pool-ac  # Initialize Pool A/C
make liquid-ac          # Add liquidity to Pool A/C
make deploy-asset-manager # Deploy AssetManager
```

### Trading Operations
```bash
make setup-cross-pool                           # Setup user wallet
make cross-pool-trade AMOUNT=100 LEVERAGE=5    # Execute leverage trade
make check-cross-pool-position POSITION_ID=0x... # Check position health
make close-cross-pool-position POSITION_ID=0x... # Close position
```

### Utilities
```bash
make check-compile      # Verify compilation
make help              # Show all commands
```

## 🔐 Authorization Flow

The system uses a multi-layer authorization:

1. **LeverageController** ↔ **InstantLeverageHook**: Set in DeployLeverageSystem.s.sol
2. **AssetManager** ↔ **LeverageController**: Set in DeployAssetManager.s.sol
3. **AssetManager** ↔ **WalletFactory**: Via WalletFactory platform system
4. **UserWallet** ↔ **User**: Owner-based delegation system

## ⚠️ Key Integration Points

### Platform Authorization Issue Fix
The "Only platform can execute" error occurs when AssetManager isn't properly authorized in WalletFactory. The fix is to integrate AssetManager authorization into the DeployLeverageSystem.s.sol flow.

### UserWallet Integration
AssetManager must work through the WalletFactory platform system:
- UserWallet.platform = WalletFactory address
- AssetManager must be authorized platform in WalletFactory
- Use WalletFactory methods, not direct UserWallet calls

### Pool Integration
AssetManager uses `poolManager.modifyLiquidity()` for:
- Borrowing liquidity from Pool A/B
- Repaying liquidity to Pool A/B
- Trading via `poolManager.swap()` in Pool A/C

## 🎮 Frontend Integration

**Essential Functions:**
```javascript
// Core user flow
walletFactory.createUserAccount()
walletFactory.depositFunds(token, amount)
assetManager.executeCrossPoolTrade(params)
assetManager.closeCrossPoolPosition(positionId)

// Monitoring
assetManager.getCrossPoolPositionHealth(positionId)
assetManager.getUserCrossPoolPositions(user)
```

See `FRONTEND_FLOW_FUNCTIONS.md` for complete frontend integration guide.

## 🚨 Troubleshooting

**Common Issues:**
1. **"PoolNotInitialized"** → Run initialize scripts first
2. **"AllowanceExpired"** → Use Permit2 approval system
3. **"Only platform can execute"** → Fix AssetManager authorization in WalletFactory
4. **"Insufficient liquidity"** → Add more liquidity to pools
5. **"Invalid leverage"** → Use leverage 2-10x range

**Deployment Order is Critical:**
Must follow: Tokens → Core System → Pool A/B → Pool A/C → AssetManager → Trading