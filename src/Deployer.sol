// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {IUniV3Factory, IUniV3Router, IV3NFTManager, IUnIV3Pool} from "./interfaces/IUni.sol";
import {UniV3Translator} from "ebtc-amm-comparer/UniV3Translator.sol";

contract Deployer {
    // Addresses for UniV3 and Curve
    // Settings for LPing
    // Do the whole thing in the constructor

    // NOTE: You need to update these (or can customize the code later)

    // Deploy new pool
    IUniV3Factory constant UNIV3_FACTORY = IUniV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    // Swap
    IUniV3Router constant UNIV3_SWAP_ROUTER_2 = IUniV3Router(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    // Add liquidity
    IV3NFTManager constant UNIV3_NFT_MANAGER = IV3NFTManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    int24 constant TICK_SPACING = 60; // Souce: Docs | TODO
    int24 constant TICK_RANGE_MULTIPLIER = 200;
    uint24 constant DEFAULT_FEE = 3000;

    constructor() {
        // Deploy translator | NOTE: Better SWE would make this a library, but hey, it's already built
        UniV3Translator translator = new UniV3Translator();

        // TODO: Tokens, etc..
        // TODO: Convert eveything down to params

    }

    /// TODO: Params, Tokens, etc...
     function _createNewPoolAndSeed(UniV3Translator translator, uint256 amountA, uint256 amountB, int24 multipleTicksA, int24 multipleTicksB)
        internal
        returns (address newPool)
    {

        // Create the Pool
        newPool = UNIV3_FACTORY.createPool(firstToken, secondToken, DEFAULT_FEE);
        firstToken = IUnIV3Pool(newPool).token0();
        secondToken = IUnIV3Pool(newPool).token1();

        // TODO: Tokens
        uint256 firstAmount = firstToken == tokenA ? amountA : amountB;
        uint256 secondAmount = secondToken == tokenA ? amountA : amountB;

        // TODO: Compute the sqrtRatioAtTick
        uint160 priceAtRatio = translator.getSqrtRatioAtTick(0);
        IUnIV3Pool(newPool).initialize(priceAtRatio);

        {
            AddLiquidityParams memory addParams = AddLiquidityParams({
                pool: newPool,
                firstToken: firstToken,
                secondToken: secondToken,
                priceAtRatio: priceAtRatio,
                firstAmount: firstAmount,
                secondAmount: secondAmount,
                multipleTicksA: multipleTicksA,
                multipleTicksB: multipleTicksB
            });
            _addLiquidity(addParams);
        }

        return (newPool, address(firstToken), address(secondToken));
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
    }

    function _addLiquidity(UniV3Translator translator, AddLiquidityParams memory addParams) internal {
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
                recipient: address(this),
                deadline: block.timestamp
            });
            (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = UNIV3_NFT_MANAGER.mint(mintParams);
        }
    }
}
