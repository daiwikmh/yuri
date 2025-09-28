// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {WalletFactory} from "../src/WalletFactory.sol";
import {InstantLeverageHook} from "../src/InstantLeverageHook.sol";
import {LeverageController} from "../src/LeverageController.sol";
import {UserWallet} from "../src/WalletFactory.sol";

contract DeployLeverageSystem is Script {
    address internal deployer;
    
    // Contracts to deploy
    IPoolManager public poolManager;
    UserWallet public userWalletTemplate;
    WalletFactory public walletFactory;
    InstantLeverageHook public leverageHook;
    LeverageController public leverageController;

    // Standard Foundry CREATE2 deployer
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function setUp() public {
        deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.label(deployer, "Deployer");

        console.log("=== Leverage System Deployment Setup ===");
        console.log("Deployer:", deployer);
    }

    function run() public {
        console.log("=== Starting Leverage System Deployment ===");
        vm.startBroadcast(deployer);

        // Deploy PoolManager
        console.log("1. Deploying PoolManager...");
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER_ADDRESS"));  
        console.log("   PoolManager deployed at:", address(poolManager));

        // Deploy UserWallet template
        console.log("2. Deploying UserWallet template...");
        userWalletTemplate = new UserWallet();
        console.log("   UserWallet template deployed at:", address(userWalletTemplate));

        // Deploy WalletFactory
        console.log("3. Deploying WalletFactory...");
        walletFactory = new WalletFactory(payable(address(userWalletTemplate)));
        console.log("   WalletFactory deployed at:", address(walletFactory));

        // Mine salt for InstantLeverageHook
        console.log("4. Mining salt for InstantLeverageHook...");
        uint160 flags = uint160(
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.AFTER_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG
        );
        console.log("   Required hook flags:", flags);

        bytes memory constructorArgs = abi.encode(
            address(poolManager),
            address(walletFactory),
            address(0), // leverageController (set later)
            deployer    // poolFeeRecipient
        );
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(InstantLeverageHook).creationCode,
            constructorArgs
        );

        console.log("   Mined hook address:", hookAddress);
        console.log("   Mined salt:", vm.toString(salt));

        // Verify flags before deploy
        uint160 ALL_HOOK_MASK = uint160((1 << 14) - 1);
        uint160 addressFlags = uint160(hookAddress) & ALL_HOOK_MASK;
        require(addressFlags == flags, "Hook flags verification failed");
        console.log("   Hook flags verified successfully");

        // Deploy InstantLeverageHook with mined salt
        console.log("5. Deploying InstantLeverageHook...");
        leverageHook = new InstantLeverageHook{salt: salt}(
            IPoolManager(address(poolManager)),
            address(walletFactory),
            address(0), // leverageController (set later)
            deployer    // poolFeeRecipient
        );
        console.log("   InstantLeverageHook deployed at:", address(leverageHook));

        // Verify hook deployment
        require(address(leverageHook) == hookAddress, "Hook address mismatch");
        uint160 deployedFlags = uint160(address(leverageHook)) & ALL_HOOK_MASK;
        require(deployedFlags == flags, "Hook flags mismatch after deployment");
        console.log("   Hook deployment verified successfully");

        // Deploy LeverageController
        console.log("6. Deploying LeverageController...");
        leverageController = new LeverageController(
            IPoolManager(address(poolManager)),
            address(walletFactory),
            address(leverageHook)
        );
        console.log("   LeverageController deployed at:", address(leverageController));

        // Setup permissions
        console.log("7. Setting up permissions...");
        leverageHook.authorizePlatform(address(leverageController));
        console.log("   Authorized LeverageController in hook");
        leverageController.setLeverageHook(address(leverageHook));
        console.log("   Set leverage hook in controller");

        // Transfer ownership
        console.log("8. Transferring ownership...");
        leverageHook.transferOwnership(deployer);
        leverageController.transferOwnership(deployer);
        console.log("   Transferred ownership to deployer");

        // Setup tokens
        console.log("9. Setting up tokens...");
        address TEST0 = vm.envAddress("TEST0_ADDRESS");
        address TEST1 = vm.envAddress("TEST1_ADDRESS");
       

        walletFactory.addToken(address(0)); // ETH
        walletFactory.addToken(TEST0);
        walletFactory.addToken(TEST1);
       

        console.log("   Added ETH, TEST0, TEST1, TEST2, TEST3 to WalletFactory");

        vm.stopBroadcast();

        // Save deployment addresses
        _saveAddresses();

        console.log("=== Leverage System Deployment Complete ===");
        _printDeploymentSummary();
    }

    function _saveAddresses() internal {
        vm.setEnv("POOL_MANAGER_ADDRESS", vm.toString(address(poolManager)));
        vm.setEnv("USER_WALLET_TEMPLATE_ADDRESS", vm.toString(address(userWalletTemplate)));
        vm.setEnv("WALLET_FACTORY_ADDRESS", vm.toString(address(walletFactory)));
        vm.setEnv("INSTANT_LEVERAGE_HOOK_ADDRESS", vm.toString(address(leverageHook)));
        vm.setEnv("LEVERAGE_CONTROLLER_ADDRESS", vm.toString(address(leverageController)));

        console.log("   Saved contract addresses to environment variables");
    }

    function _printDeploymentSummary() internal view {
        console.log("=== Deployment Summary ===");
        console.log("PoolManager:", address(poolManager));
        console.log("UserWallet Template:", address(userWalletTemplate));
        console.log("WalletFactory:", address(walletFactory));
        console.log("InstantLeverageHook:", address(leverageHook));
        console.log("LeverageController:", address(leverageController));
        console.log("==========================================");
        console.log(" Deployment successful! Next steps:");
        console.log("1. Run: forge script script/InitializePools.s.sol --broadcast --rpc-url $RPC_URL");
        console.log("2. Run: forge script script/AddLiquidity.s.sol --broadcast --rpc-url $RPC_URL");
        console.log("3. Optional: Add more tokens via walletFactory.addToken(tokenAddress)");
        console.log("");
        console.log("Cross-Pool Leverage Trading Flow:");
        console.log("- TokenA/TokenB pool: Source of leverage");
        console.log("- TokenB/TokenC pool: Target trading pool");
        console.log("- Hook holds TokenC for users (users never control TokenC directly)");
        console.log("- Position closure: TokenC -> TokenB -> TokenA for pool repayment");
        console.log("");
        console.log("Important contract interactions:");
        console.log("- Users create wallets: walletFactory.createUserAccount()");
        console.log("- Users deposit funds: walletFactory.depositFunds(token, amount)");
        console.log("- Execute leverage: leverageController.requestLeverageTrade(poolKey, tokenA, tokenB, tokenC, ...)");
        console.log("- Close positions: leverageController.closeLeveragePosition(requestId, currentPrice)");
        console.log("");
        console.log(" Remember to initialize pools and add liquidity!");
    }
}