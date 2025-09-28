# YURI

## 🎯 Project Overview

A sophisticated leverage trading system built on Uniswap V4 that enables atomic cross-pool leverage trading with automated position management. The system allows users to borrow liquidity from one pool, execute leveraged trades in another pool, and maintain positions with built-in liquidation protection.

## 🏗️ System Architecture

### Core Contracts

| Contract | Address (Unichain Sepolia) | Description |
|----------|----------------------------|-------------|
| **PoolManager** | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` | Uniswap V4 core pool manager |
| **PositionManager** | `0xf969Aee60879C54bAAed9F3eD26147Db216Fd664` | Manages liquidity positions |
| **InstantLeverageHook** | `0x3143D8279c90DdFAe5A034874C5d232AF88b03c0` | Custom hook for leverage trading |
| **LeverageController** | `0x725212999a45ABCb651A84b96C70438C6c1d7c43` | Orchestrates leverage operations |
| **AssetManager** | `0x728efba937de96744004290cbea4f4f7563ba0c0` | Cross-pool position management |

### Token Contracts

| Token | Address (Unichain Sepolia) | Symbol | Purpose |
|-------|----------------------------|---------|---------|
| **TEST0** | `0xB08D5e594773C55b2520a646b4EB3AA5fA08aF21` | TEST0 | Collateral token (Token A) |
| **TEST1** | `0xe3A426896Ca307c3fa4A818f2889F44582460954` | TEST1 | Bridge token (Token B) |

### Pool Information

| Pool | Tokens | Status | Liquidity Position |
|------|--------|--------|--------------------|
| **Pool A/B** | TEST0/TEST1 | ✅ Active | Position #5598 (50 tokens each) |
| **Pool B/C** | TEST1/TEST2 | 🚧 Pending | To be deployed |

## 🚀 Key Features

### InstantLeverageHook
A Uniswap V4 hook that enables atomic leverage trading with the following capabilities:

- **Atomic Execution**: All leverage operations happen in a single transaction
- **Cross-Pool Borrowing**: Borrow liquidity from Pool A/B to trade in Pool B/C
- **Position Management**: Automated tracking of leveraged positions
- **Liquidation Protection**: Built-in liquidation mechanism to protect pool liquidity
- **Hook Permissions**:
  - `beforeSwap` & `afterSwap`: Handle leverage trade execution
  - `beforeRemoveLiquidity` & `afterRemoveLiquidity`: Enable pool borrowing

### Key Parameters
- **Maximum Leverage**: 10x global limit
- **Pool Fee**: 3% on leverage operations
- **User Profit Share**: 97% of profits to user
- **Liquidation Threshold**: Dynamic based on leverage multiplier

## 💡 Use Cases

### 1. **Leveraged Token Exposure**
- Users can gain leveraged exposure to Token C using Token A as collateral
- Leverage multipliers from 1x to 10x
- Atomic execution reduces slippage and MEV risks

### 2. **Cross-Pool Arbitrage**
- Exploit price differences between Pool A/B and Pool B/C
- Automated borrowing and repayment mechanism
- Capital efficient trading strategies

### 3. **Yield Amplification**
- Amplify returns on token price movements
- Automated position management reduces manual intervention
- Built-in risk management through liquidation protection

## 🔄 How It Works

### Cross-Pool Leverage Flow

```
User Input: 100 TEST0 + 2x Leverage
│
├─ Step 1: Pool A/B Borrowing
│  ├─ Collateral: 100 TEST0
│  ├─ Borrow: 100 TEST1 (Token B)
│  └─ Total Power: 200 TEST1 equivalent
│
├─ Step 2: Pool B/C Trading
│  ├─ Trade: 200 TEST1 → TEST2
│  ├─ Output: ~200 TEST2 (Token C)
│  └─ Position: 2x leveraged TEST2 exposure
│
├─ Step 3: Position Management
│  ├─ AssetManager holds TEST2
│  ├─ Monitor liquidation threshold
│  └─ Auto-liquidate if needed
│
└─ Step 4: Position Closure
   ├─ Trade: TEST2 → TEST1
   ├─ Repay: 100 TEST1 + fees to Pool A/B
   ├─ Convert: Remaining TEST1 → TEST0
   └─ Result: Profit/Loss in TEST0
```

### Smart Contract Interactions

1. **LeverageController**: Receives user requests and orchestrates the flow
2. **InstantLeverageHook**: Executes leverage logic during pool operations
3. **AssetManager**: Manages cross-pool positions and Token C holdings
4. **PoolManager**: Handles all Uniswap V4 pool interactions

## 🛠️ Technical Implementation

### Hook Architecture
```solidity
contract InstantLeverageHook is BaseHook, Ownable, ReentrancyGuard {
    // Core leverage execution in beforeSwap hook
    function _beforeSwap(...) internal override returns (...) {
        if (hookData.length > 0 && authorizedPlatforms[sender]) {
            InstantLeverageRequest memory request = abi.decode(hookData, (InstantLeverageRequest));
            _handleLeverageRequest(key, request);
        }
    }

    // Pool borrowing via liquidity removal
    function _borrowFromPool(...) internal returns (uint256 borrowed) {
        // Remove liquidity to borrow tokens
        // Execute with safety checks and limits
    }
}
```

### Position Management
```solidity
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
```

## 📊 Current Status

### ✅ Completed
- Core contracts deployed and verified
- Pool A/B created with initial liquidity
- Hook permissions configured
- Basic leverage trading functionality
- Position tracking and management

### 🚧 In Progress
- Pool B/C deployment and configuration
- Cross-pool trading integration
- Frontend interface development
- Comprehensive testing suite

### 🔮 Planned
- Advanced liquidation strategies
- Multi-token support
- Governance token integration
- Yield farming mechanisms

## 🧪 Testing & Development

### Prerequisites
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone repository
git clone <repository-url>
cd uniswap

# Install dependencies
forge install
```

### Deployment Commands
```bash
# Deploy core system
make deploy-lev

# Configure pools
make create-pool

# Initialize pools
make initialize

# Add liquidity
make liquid

# Deploy AssetManager
make deploy-asset-manager
```

### Testing
```bash
# Run all tests
forge test

# Test specific functionality
forge test --match-test testLeverageExecution

# Gas optimization tests
forge test --gas-report
```

## 🔐 Security Features

### Access Control
- Owner-only admin functions
- Authorized platform system
- Reentrancy protection on all external calls

### Risk Management
- Maximum leverage limits (10x global)
- Dynamic liquidation thresholds
- Pool utilization limits (80% max)
- Emergency pause functionality

### Audit Considerations
- All external calls protected by reentrancy guards
- Proper handling of negative BalanceDelta values
- SafeERC20 usage for all token transfers
- Comprehensive input validation

## 📚 Additional Resources

### Documentation
- [Cross-Pool Leverage System Details](./uniswap/CROSS_POOL_LEVERAGE_SYSTEM.md)
- [Deployment Flow Guide](./uniswap/DEPLOYMENT_FLOW.md)
- [Frontend Integration](./uniswap/FRONTEND_FLOW_FUNCTIONS.md)

### Links
- **Uniswap V4 Docs**: https://docs.uniswap.org/contracts/v4/overview
- **Unichain Sepolia Explorer**: https://sepolia.explorer.unichain.org/
- **Foundry Documentation**: https://book.getfoundry.sh/

## 🤝 Contributing

This project was built for ETHGlobal hackathon. Contributions welcome for:
- Additional token pair support
- Frontend improvements
- Testing enhancements
- Documentation updates

## 📄 License

MIT License - see LICENSE file for details.

---

**Built with ❤️ using Uniswap V4 + Foundry + Solidity**