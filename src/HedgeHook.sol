pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-periphery/lib/v4-core/src/types/PoolId.sol";
import {Currency} from "v4-periphery/lib/v4-core/src/types/Currency.sol";
import {IHooks} from "v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import {Id} from "Depeg-swap/contracts/libraries/State.sol";
// struct Premium{}

// TODO limit order DS by pooling RA
// maybe use stylus contract to compute the bisection method?
struct LimitOrders {
    uint256 pooled;
    uint256 threshold;
}

contract HedgeHook is BaseHook {
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true, // allow adding liquidity with premium
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true, // allow removing liquidity while redeeming back RA using the premium
            afterRemoveLiquidity: true, // do we need this?
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // allow reserving directly
    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) external returns (bytes4, BalanceDelta) {}

    // allow us to redeem RA with the DS & PA in case of depegs
    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) external returns (bytes4, BalanceDelta) {}

    // maybe execute limit orders on the current pair that's being traded if we can manage to integrate stylus contract
    // to calculate the borrow amount using the bisection method
    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        external
        virtual
        returns (bytes4, BeforeSwapDelta, uint24)
    {}

    // can execute limit orders, allows offchain keepers to call this
    function batchExecuteLimitOrders() external {}

    function cancelLimitOrders() external {}

    function modifyLimitOrders() external {}

    // allow user to directly buy DS on market price, ignoring the limit order
    // can only be called by the liquidity owner
    // TODO maybe use nft or something? currently just use msg.sender for simplicity sake
    function forceExecuteOrder() external {}

    // allow user to hedge their position by depositing RA
    // the RA will be used to buy DS at the specified price
    // this can be executed by 3 things
    // - other user trading -> happens on before swap and if only we manage to integrate the stylus contract
    // - keeper executing limit orders
    // - user forcefully execute the limit order using current market price 
    function hedgeWithLimitOrder() external {}

    // allow user to hedge directly with this pair DS on a particular epoch`
    function hedgeWithDs() external{}

}
