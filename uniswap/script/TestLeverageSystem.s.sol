// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

// Import our contracts
import "../src/WalletFactory.sol";
import "../src/InstantLeverageHook.sol";
import "../src/LeverageController.sol";

/**
 * @title Test Leverage System
 * @notice Test script for the leverage trading system
 */
contract TestLeverageSystem is Script {
    address constant TEST0 = 0x5c4B14CB096229226D6D464Cba948F780c02fbb7;
    address constant TEST1 = 0x70bF7e3c25B46331239fD7427A8DD6E45B03CB4c;

    WalletFactory public walletFactory;
    InstantLeverageHook public leverageHook;
    LeverageController public leverageController;
    IPoolManager public poolManager;

    function setUp() public {
        // Load deployed addresses from environment or hardcode for testing
        walletFactory = WalletFactory(vm.envAddress("WALLET_FACTORY_ADDRESS"));
        leverageHook = InstantLeverageHook(vm.envAddress("INSTANT_LEVERAGE_HOOK_ADDRESS"));
        leverageController = LeverageController(vm.envAddress("LEVERAGE_CONTROLLER_ADDRESS"));
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER_ADDRESS"));
    }

    function run() public {
        console.log("=== Testing Leverage System ===");

        address user = vm.rememberKey(vm.envUint("TEST_USER_PRIVATE_KEY"));
        vm.startBroadcast(user);

        // Test 1: Create user wallet
        console.log("1. Creating user wallet...");
        address payable userWallet = walletFactory.createUserAccount();
        console.log("   User wallet created at:", userWallet);

        // Test 2: Check allowed tokens
        console.log("2. Checking allowed tokens...");
        address[] memory allowedTokens = walletFactory.getAllowedTokens();
        console.log("   Allowed tokens count:", allowedTokens.length);
        for (uint i = 0; i < allowedTokens.length; i++) {
            console.log("   Token", i, ":", allowedTokens[i]);
        }

        // Test 3: Check pool price functionality
        console.log("3. Testing pool price calculation...");
        PoolKey memory testPool = PoolKey({
            currency0: Currency.wrap(TEST0),
            currency1: Currency.wrap(TEST1),
            fee: 3000,
            tickSpacing: 60,
            hooks: leverageHook
        });

        try leverageHook.getPoolPrice(testPool) returns (uint256 price) {
            console.log("   Pool price:", price);
        } catch {
            console.log("   Pool price calculation failed (pool may not exist)");
        }

        // Test 4: Configure pool in controller
        console.log("4. Configuring pool in controller...");
        // This would require owner permissions
        // leverageController.configurePool(testPool, true, 5, 8000, 500);

        vm.stopBroadcast();

        console.log("=== Testing Complete ===");
    }

    function testUserCapacity(address user, uint256 amount) public view {
        // Test user capacity for leverage trading
        (address payable userWallet, bool exists,) = walletFactory.userAccounts(user);

        if (!exists) {
            console.log("User has no wallet");
            return;
        }

        uint256 balance = IUserWallet(userWallet).balances(TEST0);
        console.log("User TEST0 balance:", balance);
        console.log("Required amount:", amount);
        console.log("Sufficient funds:", balance >= amount);
    }
}