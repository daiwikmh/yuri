# Uniswap V4 Leverage Trading System - Deployment Guide

## 🚀 Quick Start Deployment

### Prerequisites
1. **Foundry installed** - `curl -L https://foundry.paradigm.xyz | bash && foundryup`
2. **Node.js & npm** (for any frontend integration)
3. **Testnet funds** - Ensure deployer account has sufficient gas tokens
4. **Environment setup** - Copy `.env.example` to `.env` and configure

### 📋 Deployment Checklist

#### Step 1: Environment Setup
```bash
# Copy environment template
cp .env.example .env

# Edit .env with your values:
# - PRIVATE_KEY (deployer account)
# - OWNER_PRIVATE_KEY (protocol owner, can be same as deployer)
# - TEST_USER_PRIVATE_KEY (for testing)
# - RPC_URL (your network endpoint)
```

#### Step 2: Deploy PoolManager First
```bash
# Deploy PoolManager separately due to contract size limits
forge script script/DeployPoolManager.s.sol --broadcast --rpc-url $RPC_URL

# Copy the PoolManager address to your .env file
cat pool-manager-address.env >> .env
```

#### Step 3: Deploy Core System
```bash
# Deploy all other contracts (this will take a few minutes due to hook mining)
forge script script/DeployLeverageSystem.s.sol --broadcast --rpc-url $RPC_URL

# Verify deployment addresses are saved to deployed-addresses.env
cat deployed-addresses.env
```

#### Step 4: Update Environment
```bash
# Copy deployed addresses to your .env file
cat deployed-addresses.env >> .env

# Verify all addresses are set
grep "ADDRESS=" .env
```

#### Step 5: Configure Pools
```bash
# Configure pools for leverage trading
forge script script/ConfigurePools.s.sol --broadcast --rpc-url $RPC_URL
```

#### Step 6: Test System
```bash
# Run basic functionality tests
forge script script/TestLeverageSystem.s.sol --rpc-url $RPC_URL

# Optional: Run full test suite
forge test -vv
```

## 🏗️ System Architecture Verification

### Contract Deployment Order
1. **PoolManager** - Uniswap V4 core pool management
2. **UserWallet** (template) - Clone-based user wallet implementation
3. **WalletFactory** - User wallet factory and fund management
4. **InstantLeverageHook** - Uniswap V4 hook with proper salt mining
5. **LeverageController** - Main orchestrator contract

### Hook Configuration Verification
The deployment script automatically:
- Mines correct salt for hook address with required permissions
- Verifies hook permissions match implementation
- Authorizes LeverageController in the hook
- Adds TEST0, TEST1, and ETH to WalletFactory whitelist

### Permission Setup
After deployment, the system will have:
- Hook authorized to execute leverage trades
- Controller authorized as platform in hook
- WalletFactory configured with test tokens
- Protocol owner can configure pools and system parameters

## 🔧 Post-Deployment Configuration

### Required Pool Configuration
```solidity
// Example: Configure TEST0/TEST1 pool for 5x leverage
leverageController.configurePool(
    poolKey,        // PoolKey for TEST0/TEST1
    true,           // active
    5,              // maxLeverage (5x)
    8000,           // maxUtilization (80%)
    500             // baseFeeRate (0.5%)
);
```

### Optional Configuration
```solidity
// Set global leverage limit
leverageController.setMaxLeverageGlobal(10);

// Add additional tokens
walletFactory.addToken(newTokenAddress);

// Emergency pause (if needed)
leverageController.setEmergencyPause(true);
```

## 🧪 Testing Your Deployment

### Manual Testing Workflow
```solidity
// 1. Create user wallet
address userWallet = walletFactory.createUserAccount();

// 2. Deposit funds
walletFactory.depositFunds(TEST0, amount);

// 3. Set delegation (off-chain signature required)
userWallet.setDelegation(delegationHash, maxAmount, expiry, signature);

// 4. Request leverage trade
bytes32 requestId = leverageController.requestLeverageTrade(
    poolKey, tokenIn, tokenOut, baseAmount,
    leverageMultiplier, minOutput, delegationHash, deadline
);

// 5. Execute trade
leverageController.executeLeverageTrade(requestId, poolKey);
```

### Verification Commands
```bash
# Check contract verification
forge verify-contract $LEVERAGE_CONTROLLER_ADDRESS LeverageController --etherscan-api-key $ETHERSCAN_API_KEY

# Check token balances
cast call $WALLET_FACTORY_ADDRESS "allowedTokens(address)(bool)" $TEST0_ADDRESS

# Check hook permissions
cast call $INSTANT_LEVERAGE_HOOK_ADDRESS "getHookPermissions()(bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool)"
```

## 🚨 Troubleshooting

### Common Issues

**1. Hook Mining Takes Too Long**
- Solution: Mining can take 1-5 minutes, this is normal
- Alternative: Pre-compute salt offline and hardcode it

**2. Hook Address Mismatch**
- Check: Hook permissions in getHookPermissions() match deployment flags
- Check: Constructor parameters are encoded correctly

**3. Transaction Reverts on Pool Configuration**
- Check: Owner key is used for LeverageController calls
- Check: Pool exists and is initialized

**4. Price Calculation Fails**
- Check: Pool is initialized and has liquidity
- Check: StateLibrary integration is correct

### Emergency Procedures
```bash
# Pause the system
cast send $LEVERAGE_CONTROLLER_ADDRESS "setEmergencyPause(bool)" true --private-key $OWNER_PRIVATE_KEY

# Close all user positions
cast send $LEVERAGE_CONTROLLER_ADDRESS "emergencyCloseUserPositions(address,PoolKey)" $USER_ADDRESS $POOL_KEY --private-key $OWNER_PRIVATE_KEY
```

## 📊 System Monitoring

### Key Metrics to Monitor
- Pool utilization rates
- Active leverage positions
- Liquidation events
- Gas costs for hook operations
- User wallet balances

### Events to Watch
- `LeveragePositionOpened`
- `LeveragePositionClosed`
- `PositionLiquidated`
- `PoolConfigured`

## 🔒 Security Considerations

### Pre-Mainnet Checklist
- [ ] Complete security audit
- [ ] Formal verification of critical functions
- [ ] Comprehensive testing on testnets
- [ ] Stress testing with high utilization
- [ ] Documentation review
- [ ] Emergency response procedures

### Best Practices
- Use timelock for critical parameter changes
- Implement monitoring and alerting
- Regular security updates
- Community bug bounty program

---

## 📞 Support

If you encounter issues during deployment:
1. Check this guide's troubleshooting section
2. Review contract compilation errors
3. Verify environment variables are set correctly
4. Test on a local network first

**The system is designed for ETHGlobal demonstration. Ensure thorough testing and auditing before any production use.**