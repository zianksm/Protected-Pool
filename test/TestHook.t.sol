pragma solidity ^0.8.0;

import "./Base.sol";

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

    function testRedeemDirect() external {
        uint256 depositAmount = 10 ether;
        addLiquidity(10 ether, 10 ether, "");

        HedgeWithRaParams memory params = buildHedgeWithRaParams(depositAmount);

        hedgehook.hedgeWithRa(params);
        poolManager.getPositionInfo(manager, poolId, owner, tickLower, tickUpper, salt);

        
    }
}
