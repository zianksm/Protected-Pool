pragma solidity ^0.8.0;

import "./Base.sol";
import "forge-std/console.sol";
import {PoolIdLibrary, PoolId} from "v4-periphery/lib/v4-core/src/types/PoolId.sol";

contract TestHook is TestBase {
    function setUp() external {
        vm.startPrank(DEFAULT_ADDRESS);
        setupHedgeHookTest();
        moduleCore.depositLv(defaultCurrencyId, 10 ether, 0, 0);
    }

    function testHedgeDirectDs() external {
        addLiquidity(10 ether, 10 ether, "");

        uint256 depositAmount = 10 ether;
        moduleCore.depositPsm(defaultCurrencyId, depositAmount);

        (, address ds) = moduleCore.swapAsset(defaultCurrencyId, 1);
        _maxApprove(ds);

        HedgeWithDsParams memory params = buildHedgeWithDsParams(depositAmount);

        hedgehook.hedgeWithDs(params);

        Hedges memory hedge = hedgehook.getHedge(defaultKey, defaultCurrencyId);

        assertEq(hedge.dsBalance, depositAmount);
    }

    function testHedgeInDirectWithDs() external {
        uint256 depositAmount = 10 ether;
        moduleCore.depositPsm(defaultCurrencyId, depositAmount);

        (, address ds) = moduleCore.swapAsset(defaultCurrencyId, 1);
        _maxApprove(ds);

        HedgeWithDsParams memory params = buildHedgeWithDsParams(depositAmount);

        addLiquidity(10 ether, 10 ether, abi.encode(DEFAULT_ADDRESS, params));

        Hedges memory hedge = hedgehook.getHedge(defaultKey, defaultCurrencyId);

        assertEq(hedge.dsBalance, depositAmount);
    }

    function testHedgeDirectRa() external {
        uint256 depositAmount = 10 ether;
        addLiquidity(10 ether, 10 ether, "");

        HedgeWithRaParams memory params = buildHedgeWithRaParams(depositAmount);

        hedgehook.hedgeWithRa(params);

        Hedges memory hedge = hedgehook.getHedge(defaultKey, defaultCurrencyId);

        assertGe(hedge.dsBalance, depositAmount);
    }

    function testFuzzRedeemDirect(uint256 depositAmount) external {
        uint256 liquidityAmount = 10 ether;
        vm.assume(depositAmount < liquidityAmount && depositAmount > 0);

        addLiquidity(liquidityAmount, liquidityAmount, "");

        corkConfig.updatePsmBaseRedemptionFeePercentage(defaultCurrencyId, 0);
        moduleCore.depositPsm(defaultCurrencyId, depositAmount);

        (, address ds) = moduleCore.swapAsset(defaultCurrencyId, 1);
        _maxApprove(ds);

        HedgeWithDsParams memory params = buildHedgeWithDsParams(depositAmount);

        hedgehook.hedgeWithDs(params);

        (, address caller,) = vm.readCallers();

        (uint128 liquidity,,) = StateLibrary.getPositionInfo(
            poolManager,
            PoolIdLibrary.toId(defaultKey),
            address(modifyLiquidityRouter),
            LIQUIDITY_PARAMS.tickLower,
            LIQUIDITY_PARAMS.tickUpper,
            0
        );

        IPoolManager.ModifyLiquidityParams memory modifyParams;
        modifyParams.salt = 0;
        modifyParams.tickLower = LIQUIDITY_PARAMS.tickLower;
        modifyParams.tickUpper = LIQUIDITY_PARAMS.tickUpper;
        // we take it out
        modifyParams.liquidityDelta = -int128(liquidity);
        RedeemParams memory redeemParams = RedeemParams(defaultCurrencyId, depositAmount, DEFAULT_ADDRESS);

        uint256 paBalanceBefore = pa.balanceOf(DEFAULT_ADDRESS);
        uint256 raBalanceBefore = ra.balanceOf(DEFAULT_ADDRESS);

        modifyLiquidityRouter.modifyLiquidity(defaultKey, modifyParams, abi.encode(redeemParams));

        uint256 paBalanceAfter = pa.balanceOf(DEFAULT_ADDRESS);
        uint256 raBalanceAfter = ra.balanceOf(DEFAULT_ADDRESS);

        // we should receive pa - deposit amount since we used thaat to redeem RA
        assertApproxEqAbs(paBalanceAfter - paBalanceBefore, liquidityAmount - depositAmount, 10);
        // we should receive the original liquidity + the deposit amount since we essentially converted that from the pa
        assertApproxEqAbs(raBalanceAfter - raBalanceBefore, liquidityAmount + depositAmount, 10);
    }
}
