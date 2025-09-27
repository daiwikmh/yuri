// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "solmate/src/test/utils/mocks/MockERC20.sol";
import "../src/WalletFactory.sol";

contract DeployWalletFactory is Script {
    function run() external {
        // Get deployer and test user addresses
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        address testUser = vm.envAddress("TEST_USER_ADDRESS"); // Set in env or replace with actual address
        
        // Start broadcasting transactions
        vm.startBroadcast(deployer);

        // Deploy MockERC20 and mint initial supply
        MockERC20 mockToken = new MockERC20("Test Token 0", "TEST0", 18);
        uint256 initialSupply = 10_000 * 10**18; // 10,000 TEST0 tokens (matches Token.s.sol)
        mockToken.mint(testUser, initialSupply);
        
        // Log MockERC20 address and minted amount
        console.log("MockERC20 (TEST0) deployed at:", address(mockToken));
        console.log("Minted %s TEST0 to:", initialSupply / 10**18, testUser);

        // Deploy UserWallet (implementation contract)
        UserWallet userWalletImpl = new UserWallet();
        address payable userWalletTemplate = payable(address(userWalletImpl));
        
        // Log UserWallet address
        console.log("UserWallet deployed at:", userWalletTemplate);

        // Deploy WalletFactory with UserWallet as template
        WalletFactory factory = new WalletFactory(userWalletTemplate);
        
        // Log WalletFactory address
        console.log("WalletFactory deployed at:", address(factory));

        // Add initial allowed tokens (MockERC20 and ETH)
        address ethAddress = address(0); // ETH
        factory.addToken(address(mockToken));
        factory.addToken(ethAddress);

        // Log token additions
        console.log("Added token TEST0:", address(mockToken));
        console.log("Added token ETH:", ethAddress);

        // Stop broadcasting
        vm.stopBroadcast();
    }
}