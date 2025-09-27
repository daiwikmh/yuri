// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {InstantLeverageHook} from "../src/InstantLeverageHook.sol";

contract InitializePoolAC is Script {
    InstantLeverageHook public leverageHook;
    IPoolManager public poolManager;
    MockERC20 public test0; // Token A
    MockERC20 public test2; // Token C

    // Initialize at 1:1 price (sqrtPriceX96)
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function setUp() public {
        leverageHook = InstantLeverageHook(vm.envAddress("INSTANT_LEVERAGE_HOOK_ADDRESS"));
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER_ADDRESS"));
        test0 = MockERC20(vm.envAddress("TEST0_ADDRESS"));
        test2 = MockERC20(vm.envAddress("TEST2_ADDRESS"));

        console.log("=== Pool A/C Initialization Setup ===");
        console.log("InstantLeverageHook:", address(leverageHook));
        console.log("PoolManager:", address(poolManager));
        console.log("TEST0 (Token A):", address(test0));
        console.log("TEST2 (Token C):", address(test2));
    }

    function run() public {
        address owner = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.startBroadcast(owner);

        console.log("=== Initializing Pool A/C ===");
        console.log("Owner address:", owner);

        // Ensure token addresses are in the correct order (lower address first)
        address token0 = address(test0) < address(test2) ? address(test0) : address(test2);
        address token1 = address(test0) < address(test2) ? address(test2) : address(test0);

        // Initialize TEST0/TEST2 pool (Pool A/C)
        PoolKey memory poolAC = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000, // 0.3% fee
            tickSpacing: 60,
            hooks: IHooks(address(leverageHook))
        });

        console.log("1. Initializing Pool A/C (TEST0/TEST2)...");

        try poolManager.initialize(poolAC, SQRT_PRICE_1_1) returns (int24 tick) {
            console.log("    Pool A/C initialized successfully");
            console.log("    Initial tick:", vm.toString(tick));
            console.log("    Pool price: 1:1 ratio");
        } catch Error(string memory reason) {
            console.log("    Pool A/C initialization failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("    Pool A/C initialization failed with low-level error:");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();

        console.log("=== Pool A/C Initialization Complete ===");
        console.log("Pool A/C is now ready for liquidity provision!");
        console.log("Next step: Add liquidity with AddLiquidityAC script");
        console.log("");
        console.log("Cross-Pool System Status:");
        console.log(" Pool A/B (TEST0/TEST1) - Ready with liquidity");
        console.log(" Pool A/C (TEST0/TEST2) - Initialized");
        console.log(" Pool A/C liquidity - Next step");
    }
}