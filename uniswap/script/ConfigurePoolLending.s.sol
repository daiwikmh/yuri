// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

// Import our contracts
import {InstantLeverageHook} from "../src/InstantLeverageHook.sol";

/**
 * @title Configure Pool Lending
 * @notice Configures pool lending parameters in the hook after initialization
 */
contract ConfigurePoolLending is Script {
    address constant TEST0 = 0xb9c6b71B84FD94b1e677BDC07ff825f110bCD61f;
    address constant TEST1 = 0xe3A426896Ca307c3fa4A818f2889F44582460954;

    InstantLeverageHook public leverageHook;
    IPoolManager public poolManager;

    // Pool lending limits
    uint256 constant MAX_LENDING_LIMIT = 5000e18; // 5000 tokens max lending per pool

    function setUp() public {
        // Load deployed addresses from environment
        leverageHook = InstantLeverageHook(vm.envAddress("INSTANT_LEVERAGE_HOOK_ADDRESS"));
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER_ADDRESS"));

        console.log("=== Pool Lending Configuration Setup ===");
        console.log("InstantLeverageHook:", address(leverageHook));
        console.log("PoolManager:", address(poolManager));
    }

    function run() public {
        address owner = vm.rememberKey(vm.envUint("OWNER_PRIVATE_KEY"));
        vm.startBroadcast(owner);

        console.log("=== Configuring Pool Lending Settings ===");

        // Configure TEST0/TEST1 pool lending
        PoolKey memory testPool = PoolKey({
            currency0: Currency.wrap(TEST0),
            currency1: Currency.wrap(TEST1),
            fee: 3000, // 0.3% fee
            tickSpacing: 60,
            hooks: IHooks(address(leverageHook))
        });

        console.log("1. Configuring TEST0/TEST1 pool lending...");

        try leverageHook.configurePoolLending(
            testPool,
            MAX_LENDING_LIMIT,
            true // isActive
        ) {
            console.log("    TEST0/TEST1 pool lending configured successfully");
            console.log("    Max lending limit:", MAX_LENDING_LIMIT / 1e18, "tokens");
        } catch Error(string memory reason) {
            console.log("    TEST0/TEST1 pool lending configuration failed:", reason);
        } catch {
            console.log("    TEST0/TEST1 pool lending configuration failed: Unknown error");
        }

        // Configure ETH/TEST0 pool lending
        PoolKey memory ethPool = PoolKey({
            currency0: Currency.wrap(address(0)), // ETH
            currency1: Currency.wrap(TEST0),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(leverageHook))
        });

        console.log("2. Configuring ETH/TEST0 pool lending...");

        try leverageHook.configurePoolLending(
            ethPool,
            MAX_LENDING_LIMIT,
            true // isActive
        ) {
            console.log("    ETH/TEST0 pool lending configured successfully");
            console.log("    Max lending limit:", MAX_LENDING_LIMIT / 1e18, "tokens");
        } catch Error(string memory reason) {
            console.log("    ETH/TEST0 pool lending configuration failed:", reason);
        } catch {
            console.log("    ETH/TEST0 pool lending configuration failed: Unknown error");
        }

        vm.stopBroadcast();

        console.log("=== Pool Lending Configuration Complete ===");
        console.log("Pool lending settings configured!");
        console.log("");
        console.log("Next step: Add liquidity with AddLiquidity script");
    }
}