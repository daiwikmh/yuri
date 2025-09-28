// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

// Import our contracts
import {LeverageController} from "../src/LeverageController.sol";
import {InstantLeverageHook} from "../src/InstantLeverageHook.sol";

/**
 * @title Configure Pools
 * @notice Configures pools for leverage trading after initial deployment
 */
contract ConfigurePools is Script {
    address test0Addr;
    address test1Addr;

    LeverageController public leverageController;
    InstantLeverageHook public leverageHook;
    IPoolManager public poolManager;

    function setUp() public {
        // Load deployed addresses from environment
        leverageController = LeverageController(vm.envAddress("LEVERAGE_CONTROLLER_ADDRESS"));
        leverageHook = InstantLeverageHook(vm.envAddress("INSTANT_LEVERAGE_HOOK_ADDRESS"));
        test0Addr = vm.envAddress("TEST0_ADDRESS");
        test1Addr = vm.envAddress("TEST1_ADDRESS");
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER_ADDRESS"));

        console.log("=== Pool Configuration Setup ===");
        console.log("LeverageController:", address(leverageController));
        console.log("InstantLeverageHook:", address(leverageHook));
        console.log("PoolManager:", address(poolManager));
    }

    function run() public {
        address owner = vm.rememberKey(vm.envUint("OWNER_PRIVATE_KEY"));
        vm.startBroadcast(owner);

        console.log("=== Configuring Pools for Leverage Trading ===");

        // Example pool configuration for TEST0/TEST1
        PoolKey memory testPool = PoolKey({
            currency0: Currency.wrap(test0Addr),
            currency1: Currency.wrap(test1Addr),
            fee: 3000, // 0.3% fee
            tickSpacing: 60,
            hooks: IHooks(address(leverageHook))
        });

        console.log("1. Configuring TEST0/TEST1 pool...");

        // Configure pool in LeverageController
        // Parameters: poolKey, active, maxLeverage, maxUtilization, baseFeeRate
        leverageController.configurePool(
            testPool,
            true,   // active
            5,      // 5x max leverage for this pool
            8000,   // 80% max utilization (8000 basis points)
            500     // 0.5% base fee rate (500 basis points)
        );

        console.log("    TEST0/TEST1 pool configured:");
        console.log("      - Max Leverage: 5x");
        console.log("      - Max Utilization: 80%");
        console.log("      - Base Fee Rate: 0.5%");

        // Optional: Configure ETH/TEST0 pool if needed
        PoolKey memory ethPool = PoolKey({
            currency0: Currency.wrap(address(0)), // ETH
            currency1: Currency.wrap(test0Addr),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(leverageHook))
        });

        console.log("2. Configuring ETH/TEST0 pool...");

        leverageController.configurePool(
            ethPool,
            true,   // active
            3,      // 3x max leverage for ETH pool (more conservative)
            7000,   // 70% max utilization
            300     // 0.3% base fee rate
        );

        console.log("    ETH/TEST0 pool configured:");
        console.log("      - Max Leverage: 3x");
        console.log("      - Max Utilization: 70%");
        console.log("      - Base Fee Rate: 0.3%");

        // Set global parameters
        console.log("3. Setting global parameters...");

        leverageController.setMaxLeverageGlobal(10); // 10x global maximum
        console.log("    Global max leverage set to 10x");

        vm.stopBroadcast();

        console.log("=== Pool Configuration Complete ===");
        console.log("Pools configured for leverage trading!");
        console.log("");
        console.log("Next steps:");
        console.log("1. Initialize pools with InitializePools script");
        console.log("2. Add liquidity with AddLiquidity script");
        console.log("3. Users can create wallets via WalletFactory.createUserAccount()");
        console.log("4. Users can deposit funds via WalletFactory.depositFunds()");
        console.log("5. Users can set trading delegations via UserWallet.setDelegation()");
        console.log("6. Execute leverage trades via LeverageController.requestLeverageTrade()");
    }
}