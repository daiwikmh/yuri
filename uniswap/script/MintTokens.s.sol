// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract MintTokens is Script {
    MockERC20 public test0;
    MockERC20 public test1;
    MockERC20 public test2;
    MockERC20 public test3;

    function run() public {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.startBroadcast(deployer);

        console.log("=== Deploying and Minting Tokens ===");
        console.log("Deployer address:", deployer);

        // Deploy MockERC20 tokens
        test0 = new MockERC20("Test Token 0", "TEST0", 18);
        test1 = new MockERC20("Test Token 1", "TEST1", 18);
        test2 = new MockERC20("Test Token 2", "TEST2", 18);
        test3 = new MockERC20("Test Token 3", "TEST3", 18);

        // Mint 100,000 tokens to deployer
        uint256 mintAmount = 100000 ether;
        test0.mint(deployer, mintAmount);
        test1.mint(deployer, mintAmount);
        test2.mint(deployer, mintAmount);
        test3.mint(deployer, mintAmount);

        console.log("   TEST0 deployed:", address(test0));
        console.log("   TEST1 deployed:", address(test1));
        console.log("   TEST2 deployed:", address(test2));
        console.log("   TEST3 deployed:", address(test3));
        console.log("   Minted", mintAmount / 1e18, "tokens each to", deployer);

        // Save token addresses to environment
        vm.setEnv("TEST0_ADDRESS", vm.toString(address(test0)));
        vm.setEnv("TEST1_ADDRESS", vm.toString(address(test1)));
        vm.setEnv("TEST2_ADDRESS", vm.toString(address(test2)));
        vm.setEnv("TEST3_ADDRESS", vm.toString(address(test3)));

        vm.stopBroadcast();

        console.log("=== Token Deployment and Minting Complete ===");
        console.log("Token addresses saved to environment variables");
    }
}