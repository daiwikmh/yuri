// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

// Import our contracts (adjust paths as needed)
import "../src/WalletFactory.sol";
import "../src/InstantLeverageHook.sol";
import "../src/LeverageController.sol";

/**
 * @title Deploy Leverage System
 * @notice Deploys the complete leverage trading system
 */
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
        deployer = vm.rememberKey(vm.envUint("OWNER_PRIVATE_KEY"));

        vm.label(deployer, "Deployer");
        vm.label(deployer, "deployer");

        console.log("=== Leverage System Deployment Setup ===");
        console.log("Deployer:", deployer);
        console.log("Protocol Owner:", deployer);
    }

    function run() public {
    console.log("=== Starting Leverage System Deployment ===");
    vm.startBroadcast(deployer);

    // 1. Deploy PoolManager
    poolManager = IPoolManager(0x00B036B58a818B1BC34d502D3fE730Db729e62AC);


  

    // 2. Deploy UserWallet template
    console.log("2. Deploying UserWallet template...");
    userWalletTemplate = new UserWallet();
    console.log("   UserWallet template deployed at:", address(userWalletTemplate));

    // 3. Deploy WalletFactory
    console.log("3. Deploying WalletFactory...");
    walletFactory = new WalletFactory(payable(address(userWalletTemplate)));
    console.log("   WalletFactory deployed at:", address(walletFactory));

    // 4. Mine salt for InstantLeverageHook
    console.log("4. Mining salt for InstantLeverageHook...");
    uint160 flags = uint160(
        Hooks.AFTER_INITIALIZE_FLAG |
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

    // 5. Deploy InstantLeverageHook with mined salt
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

    // 6. Deploy LeverageController
    console.log("6. Deploying LeverageController...");
    leverageController = new LeverageController(
        IPoolManager(address(poolManager)),
        address(walletFactory),
        address(leverageHook)
    );
    console.log("   LeverageController deployed at:", address(leverageController));

    // 7. Setup permissions
    console.log("7. Setting up permissions...");

    // Authorize controller in hook
    leverageHook.authorizePlatform(address(leverageController));
    console.log("   Authorized LeverageController in hook");

    // Set leverage hook in controller
    leverageController.setLeverageHook(address(leverageHook));
    console.log("   Set leverage hook in controller");

    // Transfer ownership to deployer
    console.log("8. Transferring ownership...");
    leverageHook.transferOwnership(deployer);
    leverageController.transferOwnership(deployer);
    console.log("   Transferred ownership to deployer");

    // Setup tokens
    console.log("9. Setting up tokens...");
    address TEST0 = 0x5c4B14CB096229226D6D464Cba948F780c02fbb7;
    address TEST1 = 0x70bF7e3c25B46331239fD7427A8DD6E45B03CB4c;

    walletFactory.addToken(address(0)); // ETH
    walletFactory.addToken(TEST0);
    walletFactory.addToken(TEST1);
    console.log("   Added ETH, TEST0, TEST1 to WalletFactory");

    vm.stopBroadcast();

    // Configure pool
    console.log("10. Pool configuration ready (configure manually after deployment)");
    console.log("   Use LeverageController.configurePool() to enable leverage on specific pools");

    // Save deployment addresses
    _saveAddresses();

    console.log("=== Leverage System Deployment Complete ===");
    _printDeploymentSummary();
}

    function _saveAddresses() internal {
        string memory addresses = string.concat(
            "# Leverage System Contract Addresses\n",
            "POOL_MANAGER_ADDRESS=", vm.toString(address(poolManager)), "\n",
            "USER_WALLET_TEMPLATE_ADDRESS=", vm.toString(address(userWalletTemplate)), "\n",
            "WALLET_FACTORY_ADDRESS=", vm.toString(address(walletFactory)), "\n",
            "INSTANT_LEVERAGE_HOOK_ADDRESS=", vm.toString(address(leverageHook)), "\n",
            "LEVERAGE_CONTROLLER_ADDRESS=", vm.toString(address(leverageController)), "\n"
        );

    
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
        console.log("1. Copy addresses to .env file from deployed-addresses.env");
        console.log("2. Run: forge script script/ConfigurePools.s.sol --broadcast --rpc-url $RPC_URL");
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
        console.log(" Remember to configure pools before trading!");
    }
}