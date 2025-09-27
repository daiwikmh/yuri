// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

// Import our contracts
import "../src/AssetManager.sol";
import "../src/LeverageController.sol";
import "../src/InstantLeverageHook.sol";

/**
 * @title Deploy Asset Manager
 * @notice Deploys AssetManager for cross-pool leverage trading
 */
contract DeployAssetManager is Script {
    // Existing deployed contract addresses
    address constant LEVERAGE_CONTROLLER = 0xdD55A04AdFD14122c92C0d92D37137fD414E9d1a;
    address constant INSTANT_LEVERAGE_HOOK = 0x8fa16CaB5C983aaf4f721D301bd643aF121053c0;
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;

    // Test tokens
    address constant TEST0 = 0x5c4B14CB096229226D6D464Cba948F780c02fbb7;
    address constant TEST1 = 0x70bF7e3c25B46331239fD7427A8DD6E45B03CB4c;

    AssetManager public assetManager;
    LeverageController public leverageController;
    InstantLeverageHook public leverageHook;

    function setUp() public {
        // Connect to existing contracts
        leverageController = LeverageController(LEVERAGE_CONTROLLER);
        leverageHook = InstantLeverageHook(INSTANT_LEVERAGE_HOOK);

        console.log("=== AssetManager Deployment Setup ===");
        console.log("LeverageController:", address(leverageController));
        console.log("InstantLeverageHook:", address(leverageHook));
        console.log("PoolManager:", POOL_MANAGER);
    }

    function run() public {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.startBroadcast(deployer);

        console.log("=== Deploying AssetManager ===");
        console.log("Deployer:", deployer);

        // Deploy AssetManager
        console.log("1. Deploying AssetManager...");
        assetManager = new AssetManager(
            IPoolManager(POOL_MANAGER),
            address(leverageController),
            address(leverageHook)
        );
        console.log("   AssetManager deployed at:", address(assetManager));

        // Setup permissions
        console.log("2. Setting up permissions...");


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
        console.log("PoolManager:", POOL_MANAGER);
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
        console.log("POOL_MANAGER_ADDRESS=", vm.toString(POOL_MANAGER));
    }
}