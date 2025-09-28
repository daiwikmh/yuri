include .env
export $(shell sed 's/=.*//' .env)

# Default target
all: help



create-wallet:
	forge script script/DeployWalletFactory.s.sol:DeployWalletFactory \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast

deploy-lev:
	forge script script/DeployLeverageSystem.s.sol:DeployLeverageSystem \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast --via-ir

liquid:
	forge script script/AddLiquidity.s.sol:AddLiquidity \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast --via-ir

initialize:
	forge script script/InitializePools.s.sol:InitializePools \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast --via-ir

create-pool:
	forge script script/ConfigurePools.s.sol:ConfigurePools \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast --via-ir
token:
	forge script script/MintTokens.s.sol:MintTokens \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast --via-ir

# Initialize Pool A/C (TEST0/TEST2)
initialize-pool-ac:
	forge script script/InitializePoolAC.s.sol:InitializePoolAC \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast --via-ir

# Add liquidity to Pool A/C (TEST0/TEST2)
liquid-ac:
	forge script script/AddLiquidityAC.s.sol:AddLiquidityAC \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast --via-ir


# ============================================================================
# CROSS-POOL LEVERAGE SYSTEM - ASSET MANAGER
# ============================================================================

# Deploy AssetManager for cross-pool leverage
deploy-asset-manager:
	@echo "=== Deploying AssetManager for Cross-Pool Leverage ==="
	forge script script/DeployAssetManager.s.sol:DeployAssetManager \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast --via-ir

# Setup cross-pool leverage trading
setup-cross-pool:
	@echo "=== Setting up Cross-Pool Leverage Trading ==="
	forge script script/CrossPoolLeverageTrading.s.sol:CrossPoolLeverageTrading \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast --via-ir

# Execute cross-pool leverage trade (usage: make cross-pool-trade AMOUNT=100 LEVERAGE=5)
cross-pool-trade:
	@if [ -z "$(AMOUNT)" ] || [ -z "$(LEVERAGE)" ]; then \
		echo "Error: Please provide AMOUNT and LEVERAGE"; \
		echo "Usage: make cross-pool-trade AMOUNT=100 LEVERAGE=2"; \
		exit 1; \
	fi
	@echo "=== Executing Cross-Pool Leverage Trade: $(AMOUNT) Token A with $(LEVERAGE)x leverage ==="
	forge script script/CrossPoolLeverageTrading.s.sol:CrossPoolLeverageTrading \
		--sig "executeCrossPoolTrade(uint256,uint8)" $(AMOUNT)000000000000000000 $(LEVERAGE) \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast --via-ir

# Check cross-pool position health (usage: make check-cross-pool-position POSITION_ID=0x...)
check-cross-pool-position:
	@echo "=== Checking Cross-Pool Position Health ==="
	forge script script/CrossPoolLeverageTrading.s.sol:CrossPoolLeverageTrading \
		--sig "checkCrossPoolPosition(bytes32)" $(POSITION_ID) \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

# Close cross-pool position (usage: make close-cross-pool-position POSITION_ID=0x...)
close-cross-pool-position:
	@echo "=== Closing Cross-Pool Position ==="
	forge script script/CrossPoolLeverageTrading.s.sol:CrossPoolLeverageTrading \
		--sig "closeCrossPoolPosition(bytes32)" $(POSITION_ID) \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast --via-ir

# Check cross-pool system status
check-cross-pool-status:
	@echo "=== Checking Cross-Pool System Status ==="
	forge script script/CrossPoolLeverageTrading.s.sol:CrossPoolLeverageTrading \
		--sig "getCrossPoolSystemStatus()" \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

help:
	@echo "=========================================="
	@echo "UNISWAP V4 LEVERAGE TRADING - MAKEFILE HELP"
	@echo "=========================================="
	@echo ""
	@echo "🚀 DEPLOYMENT:"
	@echo "make deploy-lev          -> Deploy leverage trading system"
	@echo "make create-pool         -> Configure pools for leverage"
	@echo "make deploy-asset-manager-> Deploy AssetManager for cross-pool"
	@echo ""
	@echo "🌉 CROSS-POOL LEVERAGE:"
	@echo "make setup-cross-pool    -> Setup cross-pool leverage trading"
	@echo "make cross-pool-trade AMOUNT=100 LEVERAGE=5 -> Execute A→C leverage via A/B+B/C pools"
	@echo "make check-cross-pool-position POSITION_ID=0x... -> Check position health"
	@echo "make close-cross-pool-position POSITION_ID=0x... -> Close cross-pool position"
	@echo "make check-cross-pool-status -> Check system status"
	@echo ""
	@echo "💧 POOL SETUP:"
	@echo "make initialize         -> Initialize Pool A/B (TEST0/TEST1)"
	@echo "make liquid             -> Add liquidity to Pool A/B"
	@echo "make initialize-pool-ac -> Initialize Pool A/C (TEST0/TEST2)"
	@echo "make liquid-ac          -> Add liquidity to Pool A/C"
	@echo ""
	@echo "🛠️ UTILITIES:"
	@echo "make token              -> Deploy test tokens"
	@echo "make check-compile      -> Check contract compilation"

