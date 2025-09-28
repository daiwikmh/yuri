// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../src/AssetManagerFixed.sol";
import "../src/ILeverageInterfaces.sol";

contract SimpleCrossPoolTest is Script {
    function run() public {
        address user = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        address test0Addr = vm.envAddress("TEST0_ADDRESS");
        address test1Addr = vm.envAddress("TEST1_ADDRESS");
        address test2Addr = vm.envAddress("TEST2_ADDRESS");
        address assetManagerAddr = vm.envAddress("ASSET_MANAGER_ADDRESS");
        address leverageHookAddr = vm.envAddress("INSTANT_LEVERAGE_HOOK_ADDRESS");

        vm.startBroadcast(user);

        console.log("=== Simple Cross-Pool Test ===");
        console.log("User:", user);
        console.log("Tokens:", test0Addr, test1Addr, test2Addr);

        AssetManagerFixed assetManager = AssetManagerFixed(payable(assetManagerAddr));

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
            hooks: IHooks(leverageHookAddr)
        });

        PoolKey memory poolAC = PoolKey({
            currency0: Currency.wrap(token0_AC),
            currency1: Currency.wrap(token1_AC),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(leverageHookAddr)
        });

        // Simple parameters
        ICrossPoolAssetManager.CrossPoolTradeParams memory params = ICrossPoolAssetManager.CrossPoolTradeParams({
            user: user,
            userWallet: user, // Use user directly instead of userWallet
            borrowPool: poolAB,
            tradingPool: poolAC,
            tokenA: test0Addr,
            tokenB: test1Addr,
            tokenC: test2Addr,
            collateralAmount: 5e18, // 5 tokens
            leverage: 2,
            minTokenCAmount: 9e18, // Expecting ~10 tokens out with 2x leverage
            deadline: block.timestamp + 1 hours
        });

        console.log("Executing cross-pool trade...");
        console.log("Collateral:", params.collateralAmount / 1e18);
        console.log("Leverage:", params.leverage);

        try assetManager.executeCrossPoolTrade(params) returns (bytes32 positionId) {
            console.log("SUCCESS! Position ID:", vm.toString(positionId));
        } catch Error(string memory reason) {
            console.log("FAILED:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("FAILED with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();
    }
}