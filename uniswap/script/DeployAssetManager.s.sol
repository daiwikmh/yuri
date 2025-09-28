// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {AssetManagerFixed} from "../src/AssetManagerFixed.sol";
import {LeverageController} from "../src/LeverageController.sol";
import {InstantLeverageHook} from "../src/InstantLeverageHook.sol";

contract DeployAssetManager is Script {
    address leverageControllerAddr;
    address instantLeverageHookAddr;
    address poolManagerAddr;

    AssetManagerFixed public assetManager;
    LeverageController public leverageController;
    InstantLeverageHook public leverageHook;

    function setUp() public {
        leverageControllerAddr = vm.envAddress("LEVERAGE_CONTROLLER_ADDRESS");
        instantLeverageHookAddr = vm.envAddress("INSTANT_LEVERAGE_HOOK_ADDRESS");
        poolManagerAddr = vm.envAddress("POOL_MANAGER_ADDRESS");

        require(leverageControllerAddr != address(0), "Invalid LEVERAGE_CONTROLLER_ADDRESS");
        require(instantLeverageHookAddr != address(0), "Invalid INSTANT_LEVERAGE_HOOK_ADDRESS");
        require(poolManagerAddr != address(0), "Invalid POOL_MANAGER_ADDRESS");

        leverageController = LeverageController(leverageControllerAddr);
        leverageHook = InstantLeverageHook(instantLeverageHookAddr);

        console.log("=== AssetManager Deployment Setup ===");
        console.log("LeverageController: %s", address(leverageController));
        console.log("InstantLeverageHook: %s", address(leverageHook));
        console.log("PoolManager: %s", poolManagerAddr);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        require(deployerPrivateKey != 0, "Invalid PRIVATE_KEY");
        address deployer = vm.rememberKey(deployerPrivateKey);
        vm.startBroadcast(deployer);

        console.log("=== Deploying AssetManager ===");
        console.log("Deployer: %s", deployer);

        console.log("1. Deploying AssetManagerFixed...");
        assetManager = new AssetManagerFixed(
            IPoolManager(poolManagerAddr),
            leverageControllerAddr
        );
        console.log("   AssetManager deployed at: %s", address(assetManager));

        console.log("2. Setting up permissions...");
        leverageController.authorizePlatform(address(assetManager));
        console.log("   AssetManager authorized in LeverageController");

        vm.stopBroadcast();

        console.log("=== AssetManager Deployment Complete ===");
        _printDeploymentSummary();
        _saveDeploymentAddresses();
    }

    function _printDeploymentSummary() internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("AssetManager: %s", address(assetManager));
        console.log("LeverageController: %s", address(leverageController));
        console.log("InstantLeverageHook: %s", address(leverageHook));
        console.log("PoolManager: %s", poolManagerAddr);
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
        console.log("ASSET_MANAGER_ADDRESS=%s", vm.toString(address(assetManager)));
        console.log("LEVERAGE_CONTROLLER_ADDRESS=%s", vm.toString(address(leverageController)));
        console.log("INSTANT_LEVERAGE_HOOK_ADDRESS=%s", vm.toString(address(leverageHook)));
        console.log("POOL_MANAGER_ADDRESS=%s", vm.toString(poolManagerAddr));
    }
}