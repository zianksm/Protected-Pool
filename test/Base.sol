pragma solidity ^0.8.26;

import {Helper} from "Depeg-swap/test/forge/Helper.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract TestBase is Helper {
    uint160 internal hookAddress = (
        Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
    );

    function setup() internal virtual {
        deployModuleCore();

        deployCodeTo(
            "HedgeHook.sol",
            abi.encode(poolManager, address(moduleCore), address(flashSwapRouter)),
            address(hookAddress)
        );
    }
}
