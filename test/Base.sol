pragma solidity ^0.8.26;

import {Helper} from "Depeg-swap/test/forge/Helper.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HedgeHook} from "./../src/HedgeHook.sol";
import "v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {Asset} from "Depeg-swap/contracts/core/assets/Asset.sol";
import {DummyWETH} from "Depeg-swap/contracts/dummy/DummyWETH.sol";

contract TestBase is Helper {
    uint160 internal hookAddress = (
        Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
    );

    HedgeHook internal hedgehook;
    PoolKey internal defaultKey;

    function setupHedgeHookTest() internal virtual {
        deployModuleCore();

        deployCodeTo(
            "HedgeHook.sol",
            abi.encode(poolManager, address(moduleCore), address(flashSwapRouter)),
            address(hookAddress)
        );

        hedgehook = HedgeHook(address(hookAddress));

        (DummyWETH ra, DummyWETH pa,) = initializeAndIssueNewDs(10 days);
        (token0, token1) = ra < pa ? (Asset(address(ra)), Asset(address(pa))) : (Asset(address(pa)), Asset(address(ra)));

        initializeProtectedPool();
    }

    function initializeProtectedPool() public {
        defaultKey = PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 0, 1, IHooks(hedgehook));

        poolManager.initialize(key, SQRT_PRICE_1_1);
    }

    function _maxApprove(Asset token) public {
        address[9] memory toApprove = [
            address(swapRouter),
            address(swapRouterNoChecks),
            address(modifyLiquidityRouter),
            address(modifyLiquidityNoChecks),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(nestedActionRouter.executor()),
            address(actionsRouter)
        ];

        for (uint256 i = 0; i < toApprove.length; i++) {
            token.approve(toApprove[i], type(uint256).max);
        }
    }

    function _maxMint() public {
        (, address msgSender,) = vm.readCallers();

        token0.mint(msgSender, type(uint256).max);
        token1.mint(msgSender, type(uint256).max);
    }

    function addLiquidity(bytes calldata hookData) public virtual {
        _maxApprove(token0);
        _maxApprove(token1);

        modifyLiquidityRouter.modifyLiquidity(defaultKey, LIQUIDITY_PARAMS, hookData);
    }
}
