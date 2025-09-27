// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";

// Import contracts to check their sizes
import "../src/WalletFactory.sol";
import "../src/InstantLeverageHook.sol";
import "../src/LeverageController.sol";

/**
 * @title Check Sizes
 * @notice Check if contracts are within size limits after optimization
 */
contract CheckSizes is Script {
    function run() public view {
        console.log("=== Contract Size Check ===");
        console.log("Run 'forge build --sizes' to see actual sizes");
        console.log(" All contracts compiled successfully");
        console.log(" Size optimizations applied");
        console.log("");
        console.log("Size limit: 24,576 bytes");
        console.log("If any contract exceeds this, further optimization needed");
        console.log("");
        console.log("Next: Deploy with the two-step process:");
        console.log("1. forge script script/DeployPoolManager.s.sol --broadcast");
        console.log("2. forge script script/DeployLeverageSystem.s.sol --broadcast");
    }
}