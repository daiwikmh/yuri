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

contract InitializePools is Script {
    InstantLeverageHook public leverageHook;
    IPoolManager public poolManager;
    MockERC20 public test0;
    MockERC20 public test1;

    // Initialize at 1:1 price (sqrtPriceX96)
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function setUp() public {
        leverageHook = InstantLeverageHook(vm.envAddress("INSTANT_LEVERAGE_HOOK_ADDRESS"));
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER_ADDRESS"));
        test0 = MockERC20(vm.envAddress("TEST0_ADDRESS"));
        test1 = MockERC20(vm.envAddress("TEST1_ADDRESS"));

        console.log("=== Pool Initialization Setup ===");
        console.log("InstantLeverageHook:", address(leverageHook));
        console.log("PoolManager:", address(poolManager));
        console.log("TEST0:", address(test0));
        console.log("TEST1:", address(test1));
    }

    function run() public {
        address owner = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.startBroadcast(owner);

        console.log("=== Initializing Pools ===");
        console.log("Owner address:", owner);

        // Ensure token addresses are in the correct order (lower address first)
        address token0 = address(test0) < address(test1) ? address(test0) : address(test1);
        address token1 = address(test0) < address(test1) ? address(test1) : address(test0);

        // Initialize TEST0/TEST1 pool
        PoolKey memory testPool = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000, // 0.3% fee
            tickSpacing: 60,
            hooks: IHooks(address(leverageHook))
        });

        console.log("1. Initializing TEST0/TEST1 pool...");

        try poolManager.initialize(testPool, SQRT_PRICE_1_1) returns (int24 tick) {
            console.log("    TEST0/TEST1 pool initialized successfully");
            console.log("    Initial tick:", vm.toString(tick));
            console.log("    Pool price: 1:1 ratio");
        } catch Error(string memory reason) {
            console.log("    TEST0/TEST1 pool initialization failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("    TEST0/TEST1 pool initialization failed with low-level error:");
            console.logBytes(lowLevelData);
        }


        vm.stopBroadcast();

        console.log("=== Pool Initialization Complete ===");
        console.log("Pools are now ready for liquidity provision!");
        console.log("Next step: Add liquidity with AddLiquidity script");
    }
}