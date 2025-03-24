pragma solidity ^0.8.26;

import {TestBase} from "./Base.sol";

contract TestHedgeHook is TestBase {

    function setUp() external {
        setupHedgeHookTest();
        initializeProtectedPool();

        // todo
        // mimic what this code does
        seedMoreLiquidity(_key, amount0, amount1);
    }
}