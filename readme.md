I'm building a Uniswap V4 leverage trading ecosystem with the following architecture:

## System Overview
A leverage trading platform where users execute leveraged trades on TEST0/TEST1 pools, with temporary liquidity borrowed from the same pools they're trading on.

## Trading Flow Example
1. User deposits 100 TEST0 to their UserWallet
2. User requests 5x leverage trade: TEST0 → TEST1 on TEST0/TEST1 pool
3. System borrows 400 TEST0 from the TEST0/TEST1 pool temporarily
4. Executes 500 TEST0 → TEST1 swap on the same pool
5. Immediately repays pool 400 TEST0 equivalent + fees
6. User receives leveraged TEST1 position

## Contract Architecture

### 1. WalletFactory.sol & UserWallet.sol (Existing)
- Non-custodial fund management with delegation
- Supports TEST0 (0x5c4B14CB096229226D6D464Cba948F780c02fbb7),
 TEST1 (0x70bF7e3c25B46331239fD7427A8DD6E45B03CB4c), ETH

### 2. InstantLeverageHook.sol
- Uniswap V4 hook for atomic leverage execution
- Borrows from pool → combines with user funds → executes swap → repays pool
- Profit distribution: 3% to pool, 97% to user
- Auto-liquidation when position value ≤ 1/leverage of initial notional
- Real-time pricing from the same pool being traded on

### 3. LeverageController.sol
- Orchestrates user requests with hook execution
- Position lifecycle management and risk validation
- Pool configuration and leverage limits

### 4. Pool Integration Details
- TEST0/TEST1 pool serves dual purpose: trading venue + liquidity source
- Hook temporarily removes liquidity (borrows) → executes trade → repays
- Price discovery from pool's sqrtPriceX96 for position valuation
- Pool earns fees on both the leverage provision and the actual trade

## Key Technical Challenges
1. Atomic execution: borrow → trade → repay must succeed or revert entirely
2. Pool price calculation from sqrtPriceX96 for position tracking
3. Hook permission mining for correct address flags
4. Circular dependency: getting prices from pool we're borrowing from
5. Position health monitoring using real-time pool prices

## Current Issues
- Missing `getPoolPrice` in IInstantLeverageHook interface
- Function visibility conflicts between contracts
- Need proper sqrtPriceX96 → price conversion
- Hook deployment salt mining
- Testing atomic execution safety

## Request
Help me build a robust leverage ecosystem where:
- Users trade on TEST0/TEST1 pools with borrowed liquidity from same pools
- All operations are atomic and safe
- Real-time position monitoring using pool prices
- Automatic profit/loss distribution
- Clean contract interactions and gas optimization

Focus on the circular nature of using pools for both trading and liquidity provision, ensuring no conflicts arise from this dual usage pattern.