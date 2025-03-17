pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary, PoolId} from "v4-periphery/lib/v4-core/src/types/PoolId.sol";
import {Currency} from "v4-periphery/lib/v4-core/src/types/Currency.sol";
import {IHooks} from "v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import {Id} from "Depeg-swap/contracts/libraries/Pair.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {ModuleCore} from "Depeg-swap/contracts/core/ModuleCore.sol";
import {RouterState} from "Depeg-swap/contracts/core/flash-swaps/FlashSwapRouter.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-periphery/lib/v4-core/src/types/BeforeSwapDelta.sol";
import {IDsFlashSwapCore} from "Depeg-swap/contracts/interfaces/IDsFlashSwapRouter.sol";
import {Asset} from "Depeg-swap/contracts/core/assets/Asset.sol";

// TODO limit order DS by pooling RA
// maybe use stylus contract to compute the bisection method?
struct LimitOrders {
    uint256 amount;
    uint256 threshold;
}

// struct Premium{}

struct Hedges {
    uint256 dsBalance;
    uint256 epoch;
}

// lets support just straight up hedging with RA
contract HedgeHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    ModuleCore cork;
    RouterState flashSwapRouter;

    // user -> uniswap market id -> cork market id -> hedges
    // no way around this since technically you can hedge your position on uniswap market using different cork markets
    mapping(address => mapping(PoolId => mapping(Id => Hedges))) hedges;

    // pool id -> cork market id
    mapping(PoolId => Id) corkMarket;

    constructor(IPoolManager _poolManager, address _cork, address _corkFlashSwapRouter) BaseHook(_poolManager) {
        cork = ModuleCore(_cork);
        flashSwapRouter = RouterState(_corkFlashSwapRouter);
    }

    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true, // allow adding liquidity with premium
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false, // allow removing liquidity while redeeming back RA using the premium
            afterRemoveLiquidity: true, // do we need this?
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: true
        });
    }

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

    // allow reserving directly
    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) external override returns (bytes4, BalanceDelta) {}

    // allow us to redeem RA with the DS & PA in case of depegs
    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) external override returns (bytes4, BalanceDelta) {}

    // maybe execute limit orders on the current pair that's being traded if we can manage to integrate stylus contract
    // to calculate the borrow amount using the bisection method
    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {}

    function _redeem(Id corkMarketId, PoolKey calldata uniswapPoolKey, uint256 amountPa)
        internal
        returns (uint256 received, uint256 dsUsed)
    {
        MarketInfo memory market = _getCurrentMarketInfo(corkMarketId);
        Hedges storage hedgeStorageRef = _getHedge(uniswapPoolKey, corkMarketId);

        _ensureHedged(hedgeStorageRef, market);

        Asset(market.pa).approve(address(cork), amountPa);
        // we'll set the allowance to 0 later don't worry
        Asset(market.ds).approve(address(cork), type(uint256).max);

        (received,,, dsUsed) = cork.redeemRaWithDsPa(corkMarketId, market.epoch, amountPa);

        hedgeStorageRef.dsBalance -= dsUsed;

        // be a good blockchain citizen, set the allowance to 0
        Asset(market.ds).approve(address(cork), 0);
    }

    function hedgeWithRa(
        PoolKey calldata uniswapPoolKey,
        Id corkMarketId,
        uint256 amount,
        uint256 amountOutMin,
        IDsFlashSwapCore.BuyAprroxParams calldata approxParams,
        IDsFlashSwapCore.OffchainGuess calldata offchainGuess
    ) external returns (uint256 amountOut) {
        _ensureCorrectMarkets(uniswapPoolKey, corkMarketId);

        (address ra,) = cork.underlyingAsset(corkMarketId);
        uint256 epoch = cork.lastDsId(corkMarketId);
        Asset(ra).transferFrom(msg.sender, address(this), amount);

        Asset(ra).approve(address(flashSwapRouter), amount);
        // should handle refunded ct, but we'll skip it for now for simplicity sake lol
        IDsFlashSwapCore.SwapRaForDsReturn memory result =
            flashSwapRouter.swapRaforDs(corkMarketId, epoch, amount, amountOutMin, approxParams, offchainGuess);

        _updateHedgeStatus(uniswapPoolKey, corkMarketId, result.amountOut);

        // TODO event
    }

    // allow user to hedge directly with this pair DS on a particular epoch
    function hedgeWithDs(PoolKey calldata uniswapPoolKey, Id corkMarketId, uint256 amount) external {
        _ensureCorrectMarkets(uniswapPoolKey, corkMarketId);

        _updateHedgeStatus(uniswapPoolKey, corkMarketId, amount);

        MarketInfo memory market = _getCurrentMarketInfo(corkMarketId);

        Asset(market.ds).transferFrom(msg.sender, address(this), amount);

        // TODO event
    }

    struct MarketInfo {
        address ra;
        address pa;
        address ct;
        address ds;
        uint256 epoch;
    }

    function _getCurrentMarketInfo(Id corkMarketId) internal view returns (MarketInfo memory market) {
        (market.ra, market.pa) = cork.underlyingAsset(corkMarketId);
        market.epoch = cork.lastDsId(corkMarketId);
        (market.ct, market.ds) = cork.swapAsset(corkMarketId, market.epoch);
    }

    function _updateHedgeStatus(PoolKey calldata uniswapPoolKey, Id corkMarketId, uint256 amount) internal {
        MarketInfo memory market = _getCurrentMarketInfo(corkMarketId);

        Hedges storage hedge = _getHedge(uniswapPoolKey, corkMarketId);

        if (hedge.epoch < market.epoch) {
            hedge.dsBalance = amount;
            hedge.epoch = market.epoch;
        } else {
            hedge.dsBalance += amount;
        }
    }

    function _ensureCorrectMarkets(PoolKey calldata uniswapPoolKey, Id corkMarketId) internal view {
        (address ra, address pa) = cork.underlyingAsset(corkMarketId);

        address token0 = Currency.unwrap(uniswapPoolKey.currency0);
        address token1 = Currency.unwrap(uniswapPoolKey.currency1);

        bool isCorrectRa = ra == token0 || ra == token1;
        bool isCorrectPa = pa == token0 || pa == token1;

        if (!isCorrectPa || !isCorrectRa) {
            // TODO custom errors
            revert("invalid market");
        }
    }

    function _getHedge(PoolKey calldata uniswapPoolKey, Id corkMarketId) internal view returns (Hedges storage hedge) {
        _ensureCorrectMarkets(uniswapPoolKey, corkMarketId);

        hedge = hedges[msg.sender][uniswapPoolKey.toId()][corkMarketId];
    }

    function _ensureHedged(Hedges storage hedgeStorageRef, MarketInfo memory market) internal view {
        if (market.epoch > hedgeStorageRef.epoch) {
            // TODO  custom errors
            revert("no hedge position");
        }
    }

    function getHedge(PoolKey calldata uniswapPoolKey, Id corkMarketId) external returns (Hedges memory hedge) {
        MarketInfo memory currentDsMarket = _getCurrentMarketInfo(corkMarketId);
        Hedges storage hedgeStorageRef = _getHedge(uniswapPoolKey, corkMarketId);

        // we basically return an empty hedge position since the current DS can't be used to redeem RA back
        if (hedgeStorageRef.epoch < currentDsMarket.epoch) {
            return hedge;
        } else {
            hedge = hedgeStorageRef;
        }
    }
}
