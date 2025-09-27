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

check-compile:
	forge script script/CheckCompilation.s.sol:CheckCompilation \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast 
token:
	forge script script/ERC20.s.sol:Token \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast

help:
	@echo "make create-wallet   -> Run CreateWallet script"
	@echo "make deploy-contract -> Run DeployContract script"
	@echo "make token           -> Run ERC20 Token script"
