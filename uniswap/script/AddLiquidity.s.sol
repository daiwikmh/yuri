// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {InstantLeverageHook} from "../src/InstantLeverageHook.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

// Simple Planner implementation
struct Plan {
    bytes actions;
    bytes[] params;
}

library Planner {
    function init() internal pure returns (Plan memory plan) {
        return Plan({actions: bytes(""), params: new bytes[](0)});
    }

    function add(Plan memory plan, uint256 action, bytes memory param) internal pure returns (Plan memory) {
        bytes memory actions = new bytes(plan.params.length + 1);
        bytes[] memory params = new bytes[](plan.params.length + 1);

        for (uint256 i; i < params.length - 1; i++) {
            params[i] = plan.params[i];
            actions[i] = plan.actions[i];
        }
        params[params.length - 1] = param;
        actions[params.length - 1] = bytes1(uint8(action));

        plan.actions = actions;
        plan.params = params;
        return plan;
    }

    function encode(Plan memory plan) internal pure returns (bytes memory) {
        return abi.encode(plan.actions, plan.params);
    }
}

contract AddLiquidity is Script {
    InstantLeverageHook public leverageHook;
    IPoolManager public poolManager;
    IPositionManager public positionManager;
    MockERC20 public test0;
    MockERC20 public test1;
    IAllowanceTransfer public permit2;

    uint256 constant INITIAL_LIQUIDITY_AMOUNT = 50e18; // 50 ETH/tokens
    uint128 constant MAX_SLIPPAGE = type(uint128).max;
    uint256 constant DEADLINE = 1 hours; // Deadline buffer

    // Permit2 is deployed at this address on most networks
    address constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public {
        leverageHook = InstantLeverageHook(vm.envAddress("INSTANT_LEVERAGE_HOOK_ADDRESS"));
        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER_ADDRESS"));
        positionManager = IPositionManager(vm.envAddress("POSITION_MANAGER_ADDRESS"));
        test0 = MockERC20(vm.envAddress("TEST0_ADDRESS"));
        test1 = MockERC20(vm.envAddress("TEST1_ADDRESS"));
        permit2 = IAllowanceTransfer(PERMIT2_ADDRESS);

        console.log("=== Liquidity Addition Setup ===");
        console.log("InstantLeverageHook:", address(leverageHook));
        console.log("PoolManager:", address(poolManager));
        console.log("PositionManager:", address(positionManager));
        console.log("TEST0:", address(test0));
        console.log("TEST1:", address(test1));
    }

    function mintLiquidityPosition(
        PoolKey memory poolKey,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 tokenId) {
        int24 tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        // Use Planner to build the action sequence
        Plan memory plan = Planner.init();

        // Add MINT_POSITION action
        plan = Planner.add(
            plan,
            Actions.MINT_POSITION,
            abi.encode(
                poolKey,
                tickLower,
                tickUpper,
                INITIAL_LIQUIDITY_AMOUNT,
                MAX_SLIPPAGE,
                MAX_SLIPPAGE,
                msg.sender,
                ""
            )
        );

        // Add CLOSE_CURRENCY actions to finalize
        plan = Planner.add(plan, Actions.CLOSE_CURRENCY, abi.encode(poolKey.currency0));
        plan = Planner.add(plan, Actions.CLOSE_CURRENCY, abi.encode(poolKey.currency1));

        bytes memory unlockData = Planner.encode(plan);
        uint256 deadline = block.timestamp + DEADLINE;

        tokenId = positionManager.nextTokenId();
        uint256 ethValue = Currency.unwrap(poolKey.currency0) == address(0) ? amount0 : 0;

        try positionManager.modifyLiquidities{value: ethValue}(unlockData, deadline) {
            console.log("    Minted position token ID:", tokenId);
        } catch Error(string memory reason) {
            console.log("    Liquidity addition failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("    Liquidity addition failed with low-level error:");
            console.logBytes(lowLevelData);
        }
    }

    function run() public {
        address owner = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.startBroadcast(owner);

        console.log("=== Adding Liquidity to Pools ===");
        console.log("Owner address:", owner);
        console.log("Owner ETH balance:", owner.balance);

        address token0 = address(test0) < address(test1) ? address(test0) : address(test1);
        address token1 = address(test0) < address(test1) ? address(test1) : address(test0);

        PoolKey memory testPool = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(leverageHook))
        });

        console.log("1. Adding liquidity to TEST0/TEST1 pool...");

        // Step 1: Approve Permit2 on both tokens
        console.log("Step 1: Approving Permit2 on tokens...");
        IERC20(token0).approve(PERMIT2_ADDRESS, type(uint256).max);
        IERC20(token1).approve(PERMIT2_ADDRESS, type(uint256).max);

        // Step 2: Approve Position Manager as spender on Permit2
        console.log("Step 2: Approving Position Manager on Permit2...");
        permit2.approve(token0, address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(token1, address(positionManager), type(uint160).max, type(uint48).max);

        uint256 testPoolTokenId = mintLiquidityPosition(
            testPool,
            INITIAL_LIQUIDITY_AMOUNT,
            INITIAL_LIQUIDITY_AMOUNT
        );

        vm.stopBroadcast();

        console.log("=== Liquidity Addition Complete ===");
        console.log("Liquidity positions created:");
        if (testPoolTokenId > 0) {
            console.log("- TEST0/TEST1 Pool Token ID:", testPoolTokenId);
        } else {
            console.log("- TEST0/TEST1 Pool: Failed to add liquidity");
        }
        console.log("");
        console.log("The leverage system is now ready for trading!");
        console.log("");
        console.log("Next steps:");
        console.log("1. Users can create wallets via WalletFactory.createUserAccount()");
        console.log("2. Users can deposit funds via WalletFactory.depositFunds()");
        console.log("3. Users can set trading delegations via UserWallet.setDelegation()");
        console.log("4. Execute leverage trades via LeverageController.requestLeverageTrade()");
    }
}