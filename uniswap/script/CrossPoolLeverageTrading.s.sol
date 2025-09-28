// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Import our contracts
import "../src/AssetManagerFixed.sol";
import "../src/WalletFactory.sol";
import "../src/LeverageController.sol";
import "../src/InstantLeverageHook.sol";
import "../src/ILeverageInterfaces.sol";
import "forge-std/console.sol";

/**
 * @title Cross-Pool Leverage Trading Script
 * @notice Execute cross-pool leverage trades: Pool A/B (borrow) + Pool B/C (trade)
 */
contract CrossPoolLeverageTrading is Script {
    // Load addresses from environment
    address leverageControllerAddr;
    address instantLeverageHookAddr;
    address test0Addr; // Token A
    address test1Addr; // Token B
    address test2Addr; // Token C

   
    // Contract instances
    AssetManagerFixed public assetManager;
    IWalletFactory public walletFactory;
    LeverageController public leverageController;
    InstantLeverageHook public leverageHook;

    address public user;
    address public userWallet;

    function setUp() public {
        user = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        // Load addresses from environment
        leverageControllerAddr = vm.envAddress("LEVERAGE_CONTROLLER_ADDRESS");
        instantLeverageHookAddr = vm.envAddress("INSTANT_LEVERAGE_HOOK_ADDRESS");
        test0Addr = vm.envAddress("TEST0_ADDRESS");
        test1Addr = vm.envAddress("TEST1_ADDRESS");
        test2Addr = vm.envAddress("TEST2_ADDRESS");

        // Connect to deployed contracts
        leverageController = LeverageController(leverageControllerAddr);
        leverageHook = InstantLeverageHook(instantLeverageHookAddr);
        walletFactory = leverageController.walletFactory();

        // Load AssetManagerFixed
        assetManager = AssetManagerFixed(payable(vm.envAddress("ASSET_MANAGER_ADDRESS")));

        console.log("=== Cross-Pool Leverage Trading System ===");
        console.log("User:", user);
        console.log("AssetManager:", address(assetManager));
        console.log("LeverageController:", address(leverageController));
    }

    function run() public {
        vm.startBroadcast(user);

        // Setup user wallet
        _setupUserWallet();

        vm.stopBroadcast();

        console.log("\n=== Cross-Pool Leverage Trading Ready ===");
        console.log("Your wallet:", userWallet);
        console.log("\nAvailable Commands:");
        console.log("1. make cross-pool-trade AMOUNT=100 LEVERAGE=5");
        console.log("2. make check-cross-pool-position POSITION_ID=0x...");
        console.log("3. make close-cross-pool-position POSITION_ID=0x...");
    }

    function _setupUserWallet() internal {
        // Check if user has existing wallet
        try walletFactory.userAccounts(user) returns (
            address payable walletAddress,
            bool exists,
            uint256 createdAt
        ) {
            if (exists && walletAddress != address(0)) {
                userWallet = walletAddress;
                console.log(" Using existing wallet:", userWallet);
                return;
            }
        } catch {}

        // Create new wallet
        console.log(" Creating new wallet...");
        userWallet = walletFactory.createUserAccount();
        console.log(" Wallet created:", userWallet);
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

        console.log(" Executing Cross-Pool Leverage Trade:");
        console.log("   Collateral (Token A):", collateralAmount / 1e18);
        console.log("   Leverage:", leverage, "x");
        console.log("   Strategy: A/B (borrow) + B/C (trade)");

        // Setup user wallet if not already set
        if (userWallet == address(0)) {
            _setupUserWallet();
        }

        // Create pool keys with proper currency ordering
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

        // Pool A/C for trading (TEST0/TEST2)
        PoolKey memory poolAC = PoolKey({
            currency0: Currency.wrap(token0_AC),
            currency1: Currency.wrap(token1_AC),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(leverageHook))
        });

        // Prepare cross-pool trade parameters
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
            minTokenCAmount: (collateralAmount * leverage * 95) / 100, // 5% slippage
            deadline: block.timestamp + 1 hours
        });

        // Skip delegation for now - test direct AssetManager functionality
        console.log("Skipping delegation for testing...");

        // Approve AssetManager to spend collateral tokens
        console.log(" Approving AssetManager for collateral...");
        IERC20(test0Addr).approve(address(assetManager), collateralAmount);
        console.log(" Approval set for", collateralAmount / 1e18, "tokens");

        // Execute cross-pool trade
        positionId = assetManager.executeCrossPoolTrade(params);
        console.log(" Cross-pool position opened:", vm.toString(positionId));

        vm.stopBroadcast();
        return positionId;
    }

    /**
     * @notice Check cross-pool position health
     */
    function checkCrossPoolPosition(bytes32 positionId) public view {
        console.log("Cross-Pool Position Health:");
        console.log("Position ID:", vm.toString(positionId));

        // Get position details
        AssetManagerFixed.CrossPoolPosition memory position = assetManager.getCrossPoolPosition(positionId);

        console.log("User:", position.user);
        console.log("Collateral (Token A):", position.collateralAmount / 1e18);
        console.log("Borrowed Liquidity:", position.borrowedLiquidity);
        console.log("Holding (Token C):", position.tokenCHolding / 1e18);
        console.log("Leverage:", position.leverage, "x");
        console.log("Open Price:", position.openPrice);

        // Get position health
        (uint256 currentValue, uint256 liquidationThreshold, bool isHealthy, int256 pnl) =
            assetManager.getCrossPoolPositionHealth(positionId);

        console.log("Current Value:", currentValue / 1e18, "Token B");
        console.log("Liquidation Threshold:", liquidationThreshold / 1e18, "Token B");
        console.log("Is Healthy:", isHealthy ? "YES" : "NO");

        if (!isHealthy) {
            console.log(" POSITION AT RISK OF LIQUIDATION!");
        }
    }

    /**
     * @notice Close cross-pool position
     */
    function closeCrossPoolPosition(bytes32 positionId) public {
        vm.startBroadcast(user);

        console.log(" Closing Cross-Pool Position:", vm.toString(positionId));

        // Get initial balance
        uint256 initialBalance = UserWallet(payable(userWallet)).balances(test0Addr);

        // Close position
        uint256 userProceeds = assetManager.closeCrossPoolPosition(positionId);

        // Check final balance
        uint256 finalBalance = UserWallet(payable(userWallet)).balances(test0Addr);
        int256 pnl = int256(finalBalance) - int256(initialBalance);

        console.log(" Cross-pool position closed");
        console.log("User proceeds:", userProceeds / 1e18, "Token A");
        if (pnl >= 0) {
            console.log("Net P&L: +", uint256(pnl) / 1e18, "Token A");
        } else {
            console.log("Net P&L: -", uint256(-pnl) / 1e18, "Token A");
        }

        if (pnl > 0) {
            console.log(" Profit:", uint256(pnl) / 1e18, "Token A");
        } else if (pnl < 0) {
            console.log(" Loss:", uint256(-pnl) / 1e18, "Token A");
        } else {
            console.log(" Break-even");
        }

        vm.stopBroadcast();
    }

    // ============ UTILITY FUNCTIONS ============

    /**
     * @notice Quick cross-pool trade: 5x leverage A→C exposure
     */
    function quickCrossPoolTrade(uint256 collateralAmount) public returns (bytes32) {
        return executeCrossPoolTrade(collateralAmount, 5);
    }

    /**
     * @notice Get user's cross-pool positions
     */
    function getUserCrossPoolPositions() public view {
        console.log(" User's Cross-Pool Positions:");
        bytes32[] memory positions = assetManager.getUserCrossPoolPositions(user);

        if (positions.length == 0) {
            console.log("No active cross-pool positions");
            return;
        }

        for (uint i = 0; i < positions.length; i++) {
            AssetManagerFixed.CrossPoolPosition memory position = assetManager.getCrossPoolPosition(positions[i]);
            if (position.isActive) {
                console.log("Position", i + 1, ":", vm.toString(positions[i]));
                console.log("  - Leverage:", position.leverage, "x");
                console.log("  - Token C Holdings:", position.tokenCHolding / 1e18);
                console.log("  - Open Price:", position.openPrice);
            }
        }
    }

    /**
     * @notice Deposit Token A for cross-pool trading
     */
    function depositTokenA(uint256 amount) public {
        vm.startBroadcast(user);

        console.log(" Depositing", amount / 1e18, "Token A for cross-pool trading...");

        // Check balance
        uint256 userBalance = IERC20(test0Addr).balanceOf(user);
        require(userBalance >= amount, "Insufficient Token A balance");

        // Deposit via WalletFactory
        WalletFactory concreteFactory = WalletFactory(address(walletFactory));
        IERC20(test0Addr).approve(address(walletFactory), amount);
        concreteFactory.depositFunds(test0Addr, amount);

        console.log(" Deposited successfully");

        vm.stopBroadcast();
    }

    /**
     * @notice Get cross-pool system status
     */
    function getCrossPoolSystemStatus() public view {
        console.log(" Cross-Pool System Status:");

        // Check AssetManager authorization
        console.log("AssetManager deployed:", address(assetManager) != address(0) ? "YES" : "NO");

        if (address(assetManager) != address(0)) {
            console.log("AssetManager address:", address(assetManager));

            // Check user positions
            bytes32[] memory positions = assetManager.getUserCrossPoolPositions(user);
            console.log("User active positions:", positions.length);
        }

        console.log("LeverageController:", address(leverageController));
        console.log("InstantLeverageHook:", address(leverageHook));
    }
}