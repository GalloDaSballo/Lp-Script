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

    // Deploy new pool
    IUniV3Factory public constant UNIV3_FACTORY = IUniV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    // Add liquidity
    IV3NFTManager public constant UNIV3_NFT_MANAGER = IV3NFTManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    int24 constant TICK_SPACING = 60; // Souce: Docs | TODO
    uint24 constant DEFAULT_FEE = 3000;

    // NOTE / TODO: Prob need to add the rest of the above as params as well

    struct UniV3DeployParams {
        address tokenA;
        address tokenB;
        uint256 amtA;
        uint256 amtB;
        address sendLpTo; // LP token will go here
        address sweepTo; // We'll check for leftovers and send them to this
        int24 tickMultiplierA; // How many ticks to LP around?
        int24 tickMultiplierB; // How many ticks to LP around?
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
            params.tokenA,
            params.tokenB,
            params.amtA,
            params.amtB,
            params.tickMultiplierA,
            params.tickMultiplierB,
            params.sendLpTo
        );

        _sweep(params.tokenA, params.sweepTo);
        _sweep(params.tokenB, params.sweepTo);

        return (pool, tokenId);
    }

    function _sweep(address token, address to) internal {
        uint256 bal = ERC20(token).balanceOf(address(this));
        if (bal > 0) {
            // All tokens are safe to use
            ERC20(token).transfer(to, bal);
        }
    }

    function _createNewPoolAndSeed(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        int24 multipleTicksA,
        int24 multipleTicksB,
        address sendTo
    ) internal returns (address newPool, uint256 tokenId) {
        // Create the Pool
        newPool = UNIV3_FACTORY.createPool(tokenA, tokenB, DEFAULT_FEE);

        // QA: Can do in place
        address firstToken = IUnIV3Pool(newPool).token0();
        address secondToken = IUnIV3Pool(newPool).token1();

        uint256 firstAmount = firstToken == tokenA ? amountA : amountB;
        uint256 secondAmount = secondToken == tokenA ? amountA : amountB;

        // We LP via the NFT Manager
        ERC20(firstToken).approve(address(UNIV3_NFT_MANAGER), firstAmount);
        ERC20(secondToken).approve(address(UNIV3_NFT_MANAGER), secondAmount);

        {
            uint160 priceAtRatio = translator.getSqrtRatioAtTick(0);
            IUnIV3Pool(newPool).initialize(priceAtRatio);

            AddLiquidityParams memory addParams = AddLiquidityParams({
                pool: newPool,
                firstToken: firstToken,
                secondToken: secondToken,
                priceAtRatio: priceAtRatio,
                firstAmount: firstAmount,
                secondAmount: secondAmount,
                multipleTicksA: multipleTicksA,
                multipleTicksB: multipleTicksB,
                sendTo: sendTo
            });
            tokenId = _addLiquidity(addParams);
        }

        return (newPool, tokenId);
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

    function _addLiquidity(AddLiquidityParams memory addParams) internal returns (uint256) {
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
                translator.getTickAtSqrtRatio(addParams.priceAtRatio) - TICK_SPACING * addParams.multipleTicksA
            ) / TICK_SPACING * TICK_SPACING;
            int24 tickUpper = (
                translator.getTickAtSqrtRatio(addParams.priceAtRatio) + TICK_SPACING * addParams.multipleTicksB
            ) / TICK_SPACING * TICK_SPACING;

            // Mint
            IV3NFTManager.MintParams memory mintParams = IV3NFTManager.MintParams({
                token0: address(addParams.firstToken),
                token1: address(addParams.secondToken),
                fee: DEFAULT_FEE,
                tickLower: tickLower,
                tickUpper: tickUpper, // Not inclusive || // Does this forces to fees the other 59 ticks or not?
                amount0Desired: addParams.firstAmount,
                amount1Desired: addParams.secondAmount, // NOTE: Reverse due to something I must have messed up
                amount0Min: 0, // w/e you have?
                amount1Min: 0, // w/e you have?
                recipient: address(addParams.sendTo),
                deadline: block.timestamp
            });
            (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = UNIV3_NFT_MANAGER.mint(mintParams);

            // TODO: TEST for Slippage?

            return tokenId;
        }
    }


    // TODO: Curve logic
    struct CurveDeployParams {
        address tokenA;
        address tokenB;
        uint256 amtA;
        uint256 amtB;
        address sendLpTo; // LP token will go here
        address sweepTo; // We'll check for leftovers and send them to this
    }

    ICurveFactory CURVE_FACTORY = ICurveFactory(0xF18056Bbd320E96A48e3Fbf8bC061322531aac99);

    // Factory, etc..
    function deployAndProvideToCurve(CurveDeployParams memory params) external returns (address, uint256) {
        // Call factory
        // Deploy Pool
        // Provide Liquidity
        // Send tokens back

        address[2] memory coins = [params.tokenA, params.tokenB];

        address pool = CURVE_FACTORY.deploy_pool(
            "name",
            "symbol",
            coins,

            // TODO: Figure these out | TODO: Need to be told these by CURVE
            400000, // uint256 A,
            145000000000000, // uint256 gamma,
            26000000, // uint256 mid_fee,
            45000000, // uint256 out_fee,
            2000000000000, // uint256 allowed_extra_profit,
            230000000000000, // uint256 fee_gamma,
            146000000000000, // uint256 adjustment_step,
            5000000000, // uint256 admin_fee,
            600, // uint256 ma_half_time,
            1e18 // uint256 initial_price | // NOTE: 1e18 Price = 1e18 on both sides, not sure how this works, but prob is just A * 1e18 / B
        
        /**
        A	uint256	400000
        gamma	uint256	145000000000000
        mid_fee	uint256	26000000
        out_fee	uint256	45000000
        allowed_extra_profit	uint256	2000000000000
        fee_gamma	uint256	230000000000000
        adjustment_step	uint256	146000000000000
        admin_fee	uint256	5000000000
        ma_half_time	uint256	600
        initial_price	uint256	2749844362125
         */
        );

        // We LP via the NFT Manager
        ERC20(params.tokenA).approve(address(pool), params.amtA);
        ERC20(params.tokenB).approve(address(pool), params.amtB);

        uint256 amt = ICurvePool(pool).add_liquidity([params.amtA, params.amtB], 0); // NOTE: Slippage

        _sweep(params.tokenA, params.sweepTo);
        _sweep(params.tokenB, params.sweepTo);

        ERC20(ICurvePool(pool).token()).transfer(params.sendLpTo, amt);

        return (pool, amt);
    }

}
