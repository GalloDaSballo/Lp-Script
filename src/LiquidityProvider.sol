// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IUniV3Factory, IV3NFTManager, IUnIV3Pool} from "./interfaces/IUni.sol";
import {ICurveFactory, ICurvePool} from "./interfaces/ICurve.sol";
import {UniV3Translator} from "ebtc-amm-comparer/UniV3Translator.sol";
import {ERC20} from "./mocks/ERC20.sol";

contract LiquidityProvider {
    // Addresses for UniV3
    // Settings for LPing
    // Do the whole thing in the constructor

    // NOTE: You need to update these (or can customize the code later)


    // Addresses and Pool Config for UniV3
    struct UniV3ConfigParams {
        address UNIV3_FACTORY;
        address UNIV3_NFT_MANAGER;

        int24 TICK_SPACING;
        uint24 DEFAULT_FEE;
    }

    // LP Info for UniV3
    struct UniV3PoolParams {
        address tokenA;
        address tokenB;
        uint256 amtA;
        uint256 amtB;
        address sendLpTo; // LP token will go here
        address sweepTo; // We'll check for leftovers and send them to this
        int24 tickMultiplierA; // How many ticks to LP around?
        int24 tickMultiplierB; // How many ticks to LP around?
    }

    struct UniV3DeployParams {
        UniV3ConfigParams uniV3ConfigParams;
        UniV3PoolParams uniV3PoolParams;
    }

    UniV3Translator public translator;

    function deployAndProvideToUniV3(UniV3DeployParams memory params) external returns (address, uint256) {
        // Input address factory, address NFT Manager
        // AMT to pass
        // Ticks delta to use (assumes middle)
        // Expected slot0?

        // Deploy translator | NOTE: Better SWE would make this a library, but hey, it's already built
        translator = new UniV3Translator();

        (address pool, uint256 tokenId) = _createNewPoolAndSeed(
            params.uniV3ConfigParams,
            params.uniV3PoolParams
        );

        _sweep(params.uniV3PoolParams.tokenA, params.uniV3PoolParams.sweepTo);
        _sweep(params.uniV3PoolParams.tokenB, params.uniV3PoolParams.sweepTo);

        return (pool, tokenId);
    }

    /// @dev Transfer tokens to to if non-zero balance
    function _sweep(address token, address to) internal {
        uint256 bal = ERC20(token).balanceOf(address(this));
        if (bal > 0) {
            // All tokens are safe to use
            ERC20(token).transfer(to, bal);
        }
    }

    /// @dev Deploys a UniV3 Pool from the factory then provides liquidity via `_addLiquidity`
    /// NOTE: Maintains token-amt even if the pool will change sorting
    function _createNewPoolAndSeed(
        UniV3ConfigParams memory uniV3ConfigParams,
        UniV3PoolParams memory uniV3PoolParams
    ) internal returns (address, uint256) {
        
        (address newPool, AddLiquidityParams memory addParams) = _approveAndMakeAddParams(
            uniV3ConfigParams,
            uniV3PoolParams
        );

        uint256 tokenId = _addLiquidity(uniV3ConfigParams, addParams);

        return (newPool, tokenId);
    }

    function _approveAndMakeAddParams(
        UniV3ConfigParams memory uniV3ConfigParams,
        UniV3PoolParams memory uniV3PoolParams
    ) internal returns (address, AddLiquidityParams memory) {
        // Create the Pool
        address newPool = IUniV3Factory(uniV3ConfigParams.UNIV3_FACTORY).createPool(uniV3PoolParams.tokenA, uniV3PoolParams.tokenB, uniV3ConfigParams.DEFAULT_FEE);

        // QA: Can do in place
        address firstToken = IUnIV3Pool(newPool).token0();
        address secondToken = IUnIV3Pool(newPool).token1();

        uint256 firstAmount = firstToken == uniV3PoolParams.tokenA ? uniV3PoolParams.amtA : uniV3PoolParams.amtB;
        uint256 secondAmount = secondToken == uniV3PoolParams.tokenA ? uniV3PoolParams.amtA : uniV3PoolParams.amtB;

        // We LP via the NFT Manager
        {
            ERC20(firstToken).approve(address(uniV3ConfigParams.UNIV3_NFT_MANAGER), firstAmount);
            ERC20(secondToken).approve(address(uniV3ConfigParams.UNIV3_NFT_MANAGER), secondAmount);
        }

        uint160 priceAtRatio = translator.getSqrtRatioAtTick(0);
        IUnIV3Pool(newPool).initialize(priceAtRatio);

        AddLiquidityParams memory addParams = AddLiquidityParams({
            pool: newPool,
            firstToken: firstToken,
            secondToken: secondToken,
            priceAtRatio: priceAtRatio,
            firstAmount: firstAmount,
            secondAmount: secondAmount,
            multipleTicksA: uniV3PoolParams.tickMultiplierA,
            multipleTicksB: uniV3PoolParams.tickMultiplierB,
            sendTo: uniV3PoolParams.sendLpTo
        });

        return (newPool, addParams);
    }

    struct AddLiquidityParams {
        address pool;
        address firstToken;
        address secondToken;
        uint160 priceAtRatio;
        uint256 firstAmount;
        uint256 secondAmount;
        int24 multipleTicksA;
        int24 multipleTicksB;
        address sendTo;
    }

    /// @dev Adds liquidity in an imbalanced way
    /// NOTE: Always works as long as the tick spacing is enabled
    function _addLiquidity(UniV3ConfigParams memory uniV3ConfigParams, AddLiquidityParams memory addParams) internal returns (uint256) {
        // For ticks Lower we do: Tick of Price
        // For ticks Higher we do: Tick of Price
        {
            int24 targetTick = translator.getTickAtSqrtRatio(addParams.priceAtRatio);

            int24 tickFromPool = (IUnIV3Pool(addParams.pool).slot0()).tick;
            bool unlocked = (IUnIV3Pool(addParams.pool).slot0()).unlocked;
        }

        {
            int24 tickFromPool = (IUnIV3Pool(addParams.pool).slot0()).tick;

            int24 tickLower = (
                translator.getTickAtSqrtRatio(addParams.priceAtRatio) - uniV3ConfigParams.TICK_SPACING * addParams.multipleTicksA
            ) / uniV3ConfigParams.TICK_SPACING * uniV3ConfigParams.TICK_SPACING;
            int24 tickUpper = (
                translator.getTickAtSqrtRatio(addParams.priceAtRatio) + uniV3ConfigParams.TICK_SPACING * addParams.multipleTicksB
            ) / uniV3ConfigParams.TICK_SPACING * uniV3ConfigParams.TICK_SPACING;

            // Mint
            IV3NFTManager.MintParams memory mintParams = IV3NFTManager.MintParams({
                token0: address(addParams.firstToken),
                token1: address(addParams.secondToken),
                fee: uniV3ConfigParams.DEFAULT_FEE,
                tickLower: tickLower,
                tickUpper: tickUpper, // Not inclusive || // Does this forces to fees the other 59 ticks or not?
                amount0Desired: addParams.firstAmount,
                amount1Desired: addParams.secondAmount, // NOTE: Reverse due to something I must have messed up
                amount0Min: 0, // w/e you have?
                amount1Min: 0, // w/e you have?
                recipient: address(addParams.sendTo),
                deadline: block.timestamp
            });
            (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = IV3NFTManager(uniV3ConfigParams.UNIV3_NFT_MANAGER).mint(mintParams);

            // TODO: TEST for Slippage?

            return tokenId;
        }
    }


    struct CurveDeployParams {
        uint256 A;
        uint256 gamma;
        uint256 mid_fee;
        uint256 out_fee;
        uint256 allowed_extra_profit;
        uint256 fee_gamma;
        uint256 adjustment_step;
        uint256 admin_fee;
        uint256 ma_half_time;
        uint256 initial_price;
    }

    struct CurvePoolParams {
        address CURVE_FACTORY;
        address tokenA;
        address tokenB;
        uint256 amtA;
        uint256 amtB;
        address sendLpTo; // LP token will go here
        address sweepTo; // We'll check for leftovers and send them to this
    }

    

    // Factory, etc..
    function deployAndProvideToCurve(CurveDeployParams memory curveDeployParams, CurvePoolParams memory curvePoolParams) external returns (address, uint256) {
        // Call factory
        // Deploy Pool
        // Provide Liquidity
        // Send tokens back

        address[2] memory coins = [curvePoolParams.tokenA, curvePoolParams.tokenB];

        address pool = ICurveFactory(curvePoolParams.CURVE_FACTORY).deploy_pool(
            "name",
            "symbol",
            coins,

            // TODO: Figure these out 
            // TODO: Need to be told these by CURVE
            // NOTE: A few deployment I saw all share these except the initial price
            curveDeployParams.A, // uint256 A,
            curveDeployParams.gamma, // uint256 gamma,
            curveDeployParams.mid_fee, // uint256 mid_fee,
            curveDeployParams.out_fee, // uint256 out_fee,
            curveDeployParams.allowed_extra_profit, // uint256 allowed_extra_profit,
            curveDeployParams.fee_gamma, // uint256 fee_gamma,
            curveDeployParams.adjustment_step, // uint256 adjustment_step,
            curveDeployParams.admin_fee, // uint256 admin_fee,
            curveDeployParams.ma_half_time, // uint256 ma_half_time,
            curveDeployParams.initial_price // uint256 initial_price | // NOTE: 1e18 Price = 1e18 on both sides, not sure how this works, but prob is just A * 1e18 / B
        );

        // We LP via the NFT Manager
        ERC20(curvePoolParams.tokenA).approve(address(pool), curvePoolParams.amtA);
        ERC20(curvePoolParams.tokenB).approve(address(pool), curvePoolParams.amtB);

        uint256 amt = ICurvePool(pool).add_liquidity([curvePoolParams.amtA, curvePoolParams.amtB], 0); // NOTE: Slippage

        _sweep(curvePoolParams.tokenA, curvePoolParams.sweepTo);
        _sweep(curvePoolParams.tokenB, curvePoolParams.sweepTo);

        ERC20(ICurvePool(pool).token()).transfer(curvePoolParams.sendLpTo, amt);

        return (pool, amt);
    }

}
