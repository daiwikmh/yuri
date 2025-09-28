// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

// Import our contracts
import "../src/AssetManagerFixed.sol";
import "../src/LeverageController.sol";
import "../src/InstantLeverageHook.sol";

/**
 * @title Deploy Asset Manager
 * @notice Deploys AssetManager for cross-pool leverage trading
 */
contract DeployAssetManager is Script {
    // Load addresses from environment
    address leverageControllerAddr;
    address instantLeverageHookAddr;
    address poolManagerAddr;

    
    AssetManagerFixed public assetManager;
    LeverageController public leverageController;
    InstantLeverageHook public leverageHook;

    function setUp() public {
        // Load addresses from environment
        leverageControllerAddr = vm.envAddress("LEVERAGE_CONTROLLER_ADDRESS");
        instantLeverageHookAddr = vm.envAddress("INSTANT_LEVERAGE_HOOK_ADDRESS");
        poolManagerAddr = vm.envAddress("POOL_MANAGER_ADDRESS");

        // Connect to existing contracts
        leverageController = LeverageController(leverageControllerAddr);
        leverageHook = InstantLeverageHook(instantLeverageHookAddr);

        console.log("=== AssetManager Deployment Setup ===");
        console.log("LeverageController:", address(leverageController));
        console.log("InstantLeverageHook:", address(leverageHook));
        console.log("PoolManager:", poolManagerAddr);
    }

    function run() public {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.startBroadcast(deployer);

        console.log("=== Deploying AssetManager ===");
        console.log("Deployer:", deployer);

        // Deploy AssetManagerFixed
        console.log("1. Deploying AssetManagerFixed...");
        assetManager = new AssetManagerFixed(
            IPoolManager(poolManagerAddr),
            leverageControllerAddr
        );
        console.log("   AssetManager deployed at:", address(assetManager));

        // Setup permissions
        console.log("2. Setting up permissions...");

        // Authorize AssetManager in LeverageController
        leverageController.authorizePlatform(address(assetManager));
        console.log("   AssetManager authorized in LeverageController");

        vm.stopBroadcast();

        console.log("=== AssetManager Deployment Complete ===");
        _printDeploymentSummary();
        _saveDeploymentAddresses();
    }

    function _printDeploymentSummary() internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("AssetManager:", address(assetManager));
        console.log("LeverageController:", address(leverageController));
        console.log("InstantLeverageHook:", address(leverageHook));
        console.log("PoolManager:", poolManagerAddr);
        console.log("==========================================");
        console.log(" Cross-Pool Leverage System Ready!");
        console.log("");
        console.log("Next steps:");
        console.log("1. Update .env with ASSET_MANAGER_ADDRESS");
        console.log("2. Configure cross-pool parameters");
        console.log("3. Test cross-pool leverage trades");
        console.log("");
        console.log("Cross-Pool Trading Flow:");
        console.log("- Pool A/B: Borrow Token B using Token A collateral");
        console.log("AssetManager: Hold and manage intermediate assets");
    }

    function _saveDeploymentAddresses() internal view {
        console.log("\n=== Contract Addresses for .env ===");
        console.log("ASSET_MANAGER_ADDRESS=", vm.toString(address(assetManager)));
        console.log("LEVERAGE_CONTROLLER_ADDRESS=", vm.toString(address(leverageController)));
        console.log("INSTANT_LEVERAGE_HOOK_ADDRESS=", vm.toString(address(leverageHook)));
        console.log("POOL_MANAGER_ADDRESS=", vm.toString(poolManagerAddr));
    }
}