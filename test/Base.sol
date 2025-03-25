pragma solidity ^0.8.26;

import {Helper} from "Depeg-swap/test/forge/Helper.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import "./../src/HedgeHook.sol";
import "v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {Asset} from "Depeg-swap/contracts/core/assets/Asset.sol";
import {DummyWETH} from "Depeg-swap/contracts/dummy/DummyWETH.sol";
import {IHooks} from "v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import "v4-core/libraries/StateLibrary.sol";
import "forge-std/console.sol";

contract TestBase is Helper {
    uint160 internal hookAddress = (
        Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG
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

        _maxApprove(token0);
        _maxApprove(token1);
        _maxMint();
    }

    function initializeProtectedPool() public {
        (defaultKey,) = initPool(
            Currency.wrap(address(token0)),
            Currency.wrap(address(token1)),
            IHooks(address(hookAddress)),
            100,
            SQRT_PRICE_1_1
        );
    }

    function _maxApprove(Asset token) internal {
        address[12] memory toApprove = [
            address(swapRouter),
            address(swapRouterNoChecks),
            address(modifyLiquidityRouter),
            address(modifyLiquidityNoChecks),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(nestedActionRouter.executor()),
            address(actionsRouter),
            address(moduleCore),
            address(flashSwapRouter),
            address(hedgehook)
        ];

        for (uint256 i = 0; i < toApprove.length; i++) {
            token.approve(toApprove[i], type(uint256).max);
        }
    }

    function _maxApprove(address token) internal {
        _maxApprove(Asset(token));
    }

    function _maxMint() public {
        (, address msgSender,) = vm.readCallers();

        vm.deal(msgSender, type(uint128).max);
        DummyWETH(payable(address(token0))).deposit{value: type(uint128).max}();

        vm.deal(msgSender, type(uint128).max);
        DummyWETH(payable(address(token1))).deposit{value: type(uint128).max}();
    }

    function addLiquidity(uint256 amount0, uint256 amount1, bytes memory data) internal {
        _maxApprove(token0);
        _maxApprove(token1);

        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(manager, defaultKey.toId());
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(LIQUIDITY_PARAMS.tickLower),
            TickMath.getSqrtPriceAtTick(LIQUIDITY_PARAMS.tickUpper),
            amount0,
            amount1
        );

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: LIQUIDITY_PARAMS.tickLower,
            tickUpper: LIQUIDITY_PARAMS.tickUpper,
            liquidityDelta: int128(liquidityDelta),
            salt: 0
        });

        console.log(address(modifyLiquidityRouter));
        modifyLiquidityRouter.modifyLiquidity(defaultKey, params, data);
    }

    function buildHedgeWithDsParams(uint256 amount) internal returns (HedgeWithDsParams memory params) {
        params.uniswapPoolKey = defaultKey;
        params.corkMarketId = defaultCurrencyId;
        params.amount = amount;
    }

    function buildHedgeWithRaParams(uint256 amount) internal returns (HedgeWithRaParams memory params) {
        params.uniswapPoolKey = defaultKey;
        params.corkMarketId = defaultCurrencyId;
        params.amount = amount;
        params.amountOutMin = 0;
        params.approxParams = defaultBuyApproxParams();
        params.offchainGuess = defaultOffchainGuessParams();
    }
}
