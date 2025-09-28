// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Deposit For Cross Pool
 * @notice Simple script to deposit tokens and approve AssetManager
 */
contract DepositForCrossPool is Script {
    function run() public {
        address user = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        address test0Addr = vm.envAddress("TEST0_ADDRESS");
        address assetManagerAddr = vm.envAddress("ASSET_MANAGER_ADDRESS");

        vm.startBroadcast(user);

        console.log("=== Preparing for Cross-Pool Trading ===");
        console.log("User:", user);
        console.log("TEST0 Token:", test0Addr);
        console.log("AssetManager:", assetManagerAddr);

        // Check user balance
        uint256 userBalance = IERC20(test0Addr).balanceOf(user);
        console.log("User TEST0 balance:", userBalance / 1e18);

        // Approve AssetManager for 100 TEST0 tokens
        uint256 approvalAmount = 100e18;
        IERC20(test0Addr).approve(assetManagerAddr, approvalAmount);
        console.log("Approved AssetManager for:", approvalAmount / 1e18, "TEST0");

        vm.stopBroadcast();

        console.log("=== Ready for Cross-Pool Trading ===");
        console.log("Now you can run: make cross-pool-trade AMOUNT=10 LEVERAGE=2");
    }
}