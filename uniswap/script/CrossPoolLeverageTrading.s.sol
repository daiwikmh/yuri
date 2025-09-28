// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Import our contracts
import "../src/AssetManagerFixed.sol";
import "../src/WalletFactory.sol";
import "../src/LeverageController.sol";
import "../src/InstantLeverageHook.sol";
import "../src/ILeverageInterfaces.sol";

/**
 * @title Cross-Pool Leverage Trading Script
 * @notice Execute cross-pool leverage trades: Pool A/B (borrow) + Pool A/C (trade)
 */
contract CrossPoolLeverageTrading is Script {
    address leverageControllerAddr;
    address instantLeverageHookAddr;
    address poolManagerAddr;
    address test0Addr; // Token A
    address test1Addr; // Token B
    address test2Addr; // Token C

    AssetManagerFixed public assetManager;
    IWalletFactory public walletFactory;
    LeverageController public leverageController;
    InstantLeverageHook public leverageHook;

    address public user;
    address public userWallet;

    function setUp() public {
        user = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        leverageControllerAddr = vm.envAddress("LEVERAGE_CONTROLLER_ADDRESS");
        instantLeverageHookAddr = vm.envAddress("INSTANT_LEVERAGE_HOOK_ADDRESS");
        poolManagerAddr = vm.envAddress("POOL_MANAGER_ADDRESS");
        test0Addr = vm.envAddress("TEST0_ADDRESS");
        test1Addr = vm.envAddress("TEST1_ADDRESS");
        test2Addr = vm.envAddress("TEST2_ADDRESS");

        leverageController = LeverageController(leverageControllerAddr);
        leverageHook = InstantLeverageHook(instantLeverageHookAddr);
        walletFactory = leverageController.walletFactory();
        assetManager = AssetManagerFixed(payable(vm.envAddress("ASSET_MANAGER_ADDRESS")));

        console.log("=== Cross-Pool Leverage Trading System ===");
        console.log("User: %s", user);
        console.log("AssetManager: %s", address(assetManager));
        console.log("LeverageController: %s", address(leverageController));
        console.log("InstantLeverageHook: %s", address(leverageHook));
        console.log("PoolManager: %s", poolManagerAddr);
    }

    function run() public {
        vm.startBroadcast(user);

        _setupUserWallet();

        // Deposit tokens for trading
        uint8 decimals = IERC20Metadata(test0Addr).decimals();
        uint256 amount = 100 * (10 ** decimals); // e.g., 100 tokens
        depositTokenA(amount);

        vm.stopBroadcast();

        console.log("\n=== Cross-Pool Leverage Trading Ready ===");
        console.log("Your wallet: %s", userWallet);
        console.log("\nAvailable Commands:");
        console.log("1. make cross-pool-trade AMOUNT=1000000000000000000 LEVERAGE=5");
        console.log("2. make close-cross-pool-position POSITION_ID=0x...");
    }

    function _setupUserWallet() internal {
        try walletFactory.userAccounts(user) returns (
            address payable walletAddress,
            bool exists,
            uint256 createdAt
        ) {
            if (exists && walletAddress != address(0)) {
                userWallet = walletAddress;
                console.log("Using existing wallet: %s", userWallet);
                return;
            }
        } catch {
            console.log("No existing wallet found");
        }

        // Create new wallet
        console.log("Creating new wallet...");
        userWallet = walletFactory.createUserAccount();
        console.log("Wallet created: %s", userWallet);
    }

    // ============ CROSS-POOL TRADING FUNCTIONS ============

    /**
     * @notice Execute cross-pool leverage trade
     * @param collateralAmount Amount of Token A to use as collateral
     * @param leverage Leverage multiplier (2-10)
     */
    function executeCrossPoolTrade(
        uint256 collateralAmount,
        uint8 leverage
    ) public returns (bytes32 positionId) {
        require(address(assetManager) != address(0), "AssetManager not deployed");
        vm.startBroadcast(user);

        // Get token decimals for proper logging
        uint8 decimals = IERC20Metadata(test0Addr).decimals();
        console.log("Executing Cross-Pool Leverage Trade:");
        console.log("  Collateral (Token A): %s", collateralAmount / (10 ** decimals));
        console.log("  Leverage: %s x", leverage);
        console.log("  Strategy: A/B (borrow) + A/C (trade)");

        if (userWallet == address(0)) {
            _setupUserWallet();
        }

        address token0_AB = test0Addr < test1Addr ? test0Addr : test1Addr;
        address token1_AB = test0Addr < test1Addr ? test1Addr : test0Addr;
        address token0_AC = test0Addr < test2Addr ? test0Addr : test2Addr;
        address token1_AC = test0Addr < test2Addr ? test2Addr : test0Addr;

        PoolKey memory poolAB = PoolKey({
            currency0: Currency.wrap(token0_AB),
            currency1: Currency.wrap(token1_AB),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(leverageHook))
        });

        PoolKey memory poolAC = PoolKey({
            currency0: Currency.wrap(token0_AC),
            currency1: Currency.wrap(token1_AC),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(leverageHook))
        });

        console.log("Using existing initialized pools");

        ICrossPoolAssetManager.CrossPoolTradeParams memory params = ICrossPoolAssetManager.CrossPoolTradeParams({
            user: user,
            userWallet: userWallet,
            borrowPool: poolAB,
            tradingPool: poolAC,
            tokenA: test0Addr,
            tokenB: test1Addr,
            tokenC: test2Addr,
            collateralAmount: collateralAmount,
            leverage: leverage,
            minTokenCAmount: (collateralAmount * 95) / 100 // Realistic expectation for simplified swap
        });

        console.log("Approving AssetManager for collateral...");
        IERC20(test0Addr).approve(address(assetManager), collateralAmount);
        console.log("Approval set for %s tokens", collateralAmount / (10 ** decimals));

        positionId = assetManager.executeCrossPoolTrade(params);
        console.log("Cross-pool position opened: %s", vm.toString(positionId));

        vm.stopBroadcast();
        return positionId;
    }

    /**
     * @notice Close cross-pool position
     * @param positionId The ID of the position to close
     */
    function closeCrossPoolPosition(bytes32 positionId) public {
        vm.startBroadcast(user);

        console.log("Closing Cross-Pool Position: %s", vm.toString(positionId));

        if (userWallet == address(0)) {
            _setupUserWallet();
        }

        uint256 initialBalance = IERC20(test0Addr).balanceOf(userWallet);
        uint8 decimals = IERC20Metadata(test0Addr).decimals();

        // Close position
        uint256 userProceeds = assetManager.closeCrossPoolPosition(positionId);

        // Check final balance
        uint256 finalBalance = IERC20(test0Addr).balanceOf(userWallet);
        int256 pnl = int256(finalBalance) - int256(initialBalance);

        console.log("Cross-pool position closed");
        console.log("User proceeds: %s Token A", userProceeds / (10 ** decimals));
        if (pnl >= 0) {
            console.log("Net P&L: +%s Token A", uint256(pnl) / (10 ** decimals));
        } else {
            console.log("Net P&L: -%s Token A", uint256(-pnl) / (10 ** decimals));
        }

        vm.stopBroadcast();
    }

    /**
     * @notice Quick cross-pool trade: 5x leverage A→C exposure
     * @param collateralAmount Amount of Token A to use as collateral
     */
    function quickCrossPoolTrade(uint256 collateralAmount) public returns (bytes32) {
        return executeCrossPoolTrade(collateralAmount, 5);
    }

    /**
     * @notice Deposit Token A for cross-pool trading
     * @param amount Amount of Token A to deposit
     */
    function depositTokenA(uint256 amount) public {
        vm.startBroadcast(user);

        uint8 decimals = IERC20Metadata(test0Addr).decimals();
        console.log("Depositing %s Token A for cross-pool trading...", amount / (10 ** decimals));

        // Check balance
        uint256 userBalance = IERC20(test0Addr).balanceOf(user);
        require(userBalance >= amount, "Insufficient Token A balance");

        // Deposit via WalletFactory
        IERC20(test0Addr).approve(address(walletFactory), amount);
        walletFactory.depositFunds(test0Addr, amount);

        console.log("Deposited successfully");

        vm.stopBroadcast();
    }

    /**
     * @notice Get cross-pool system status
     */
    function getCrossPoolSystemStatus() public view {
        console.log("Cross-Pool System Status:");
        console.log("AssetManager deployed: %s", address(assetManager) != address(0) ? "YES" : "NO");
        console.log("AssetManager address: %s", address(assetManager));
        console.log("LeverageController: %s", address(leverageController));
        console.log("InstantLeverageHook: %s", address(leverageHook));
        console.log("PoolManager: %s", poolManagerAddr);
    }

    /**
     * @notice Check if a position exists and is active
     */
    function checkPosition(bytes32 positionId) public view {
        console.log("Checking position: %s", vm.toString(positionId));
        bool isActive = assetManager.isPositionActive(positionId);
        console.log("Position active: %s", isActive ? "YES" : "NO");
    }
}
