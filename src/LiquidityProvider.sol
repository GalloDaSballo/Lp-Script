// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IUniV3Factory, IV3NFTManager, IUnIV3Pool} from "./interfaces/IUni.sol";
import {ICurveFactory, ICurvePool} from "./interfaces/ICurve.sol";
import {UniV3Translator} from "ebtc-amm-comparer/UniV3Translator.sol";
import {ERC20} from "./mocks/ERC20.sol";

contract LiquidityProvider {

    // Then pass them to the 2 functions
    struct UniV3ConfigParams {
        address UNIV3_FACTORY;
        address UNIV3_NFT_MANAGER;

        int24 TICK_SPACING;
        uint24 DEFAULT_FEE;
    }

    struct UniV3LpParams {
        address tokenA;
        address tokenB;
        uint256 amtA;
        uint256 amtB;
        address sendTo; // LP token will go here
        address sweepTo; // We'll check for leftovers and send them to this
        int24 tickToInitializeAt;
        int24 multipleTicksA; // How many ticks to LP around?
        int24 multipleTicksB; // How many ticks to LP around?
    }

    UniV3Translator public translator;

    constructor() {
        // Deploy translator | NOTE: Better SWE would make this a library, but hey, it's already built
        translator = new UniV3Translator();
    }


    /// @dev Given Config Params and LP Params
    /// Create and initialize a new Pool
    /// Then LP With the intended price
    /// And finally return any leftovers
    /// @notice No slippage checks are performed since we will revert if the pool was already created or initialized
    function deployAndProvideToUniV3(UniV3ConfigParams memory configParams, UniV3LpParams memory lpParams) external returns (address, uint256) {      
        (address pool, uint256 tokenId) = _createNewPoolAndSeed(
            configParams,
            lpParams
        );

        _sweep(lpParams.tokenA, lpParams.sweepTo);
        _sweep(lpParams.tokenB, lpParams.sweepTo);

        // NOTE: Should reset allowances

        return (pool, tokenId);
    }

    function provideToUniV3WithCustomRatios(UniV3ConfigParams memory configParams, AddLiquidityFromRatioParams memory lpParams) external returns (uint256) {      
        ERC20(lpParams.firstToken).approve(configParams.UNIV3_NFT_MANAGER, type(uint256).max);
        ERC20(lpParams.secondToken).approve(configParams.UNIV3_NFT_MANAGER, type(uint256).max);

        (uint256 tokenId) = _addLiquidityFromRatios(configParams, lpParams);

        ERC20(lpParams.firstToken).approve(configParams.UNIV3_NFT_MANAGER, 0);
        ERC20(lpParams.secondToken).approve(configParams.UNIV3_NFT_MANAGER, 0);

        _sweep(lpParams.firstToken, lpParams.sweepTo);
        _sweep(lpParams.secondToken, lpParams.sweepTo);

        return (tokenId);
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
        UniV3ConfigParams memory configParams, UniV3LpParams memory lpParams
    ) internal returns (address newPool, uint256 tokenId) {
        // Create the Pool
        newPool = IUniV3Factory(configParams.UNIV3_FACTORY).createPool(lpParams.tokenA, lpParams.tokenB, configParams.DEFAULT_FEE);

        // QA: Can do in place
        address firstToken = IUnIV3Pool(newPool).token0();
        address secondToken = IUnIV3Pool(newPool).token1();

        uint256 firstAmount = firstToken == lpParams.tokenA ? lpParams.amtA : lpParams.amtB;
        uint256 secondAmount = secondToken == lpParams.tokenA ? lpParams.amtA : lpParams.amtB;

        // We LP via the NFT Manager
        ERC20(firstToken).approve(address(configParams.UNIV3_NFT_MANAGER), firstAmount);
        ERC20(secondToken).approve(address(configParams.UNIV3_NFT_MANAGER), secondAmount);

        {
            uint160 priceAtRatio = translator.getSqrtRatioAtTick(lpParams.tickToInitializeAt);
            IUnIV3Pool(newPool).initialize(priceAtRatio);

            AddLiquidityParams memory addParams = AddLiquidityParams({
                pool: newPool,
                firstToken: firstToken,
                secondToken: secondToken,
                priceAtRatio: priceAtRatio,
                firstAmount: firstAmount,
                secondAmount: secondAmount,
                multipleTicksA: lpParams.multipleTicksA,
                multipleTicksB: lpParams.multipleTicksB,
                sendTo: lpParams.sendTo
            });
            tokenId = _addLiquidity(configParams, addParams);
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

    /// @dev Adds liquidity in an imbalanced way
    /// NOTE: Always works as long as the tick spacing is enabled
    function _addLiquidity(UniV3ConfigParams memory configParams, AddLiquidityParams memory addParams) internal returns (uint256) {
        {
            int24 tickLower = (
                translator.getTickAtSqrtRatio(addParams.priceAtRatio) - configParams.TICK_SPACING * addParams.multipleTicksA
            ) / configParams.TICK_SPACING * configParams.TICK_SPACING;
            int24 tickUpper = (
                translator.getTickAtSqrtRatio(addParams.priceAtRatio) + configParams.TICK_SPACING * addParams.multipleTicksB
            ) / configParams.TICK_SPACING * configParams.TICK_SPACING;

            // Mint
            IV3NFTManager.MintParams memory mintParams = IV3NFTManager.MintParams({
                token0: addParams.firstToken,
                token1: addParams.secondToken,
                fee: configParams.DEFAULT_FEE,
                tickLower: tickLower,
                tickUpper: tickUpper, // Not inclusive || // Does this forces to fees the other 59 ticks or not?
                amount0Desired: addParams.firstAmount,
                amount1Desired: addParams.secondAmount, // NOTE: Reverse due to something I must have messed up
                amount0Min: 0, // w/e you have?
                amount1Min: 0, // w/e you have?
                recipient: addParams.sendTo,
                deadline: block.timestamp
            });
            (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = IV3NFTManager(configParams.UNIV3_NFT_MANAGER).mint(mintParams);

            return tokenId;
        }
    }


    struct AddLiquidityFromRatioParams {
        address pool;
        address firstToken;
        address secondToken;
        uint256 firstAmount;
        uint256 secondAmount;
        uint256 tokenANumeratorLow;
        uint256 tokenANumeratorHigh;
        uint256 tokenBDenominator;
        address sendTo;
        address sweepTo;
    }

    // Compute Tick upper and lower as a ratio of the two
    function _addLiquidityFromRatios(UniV3ConfigParams memory configParams, AddLiquidityFromRatioParams memory addParams) internal returns (uint256) {
        // For ticks Lower we do: Tick of Price
        // For ticks Higher we do: Tick of Price

        // Should be equal exclusively for 1 tick LPing, not even sure if you can do it, I think you need tick size else you get unlabeled revert
        assert(addParams.tokenANumeratorLow < addParams.tokenANumeratorHigh); // This gives us good properties to make LPing simpler to understand and debug

        // Constant on the right e.g. 1e18
        // Moving value on the left e.g. 9e17 to 1.1e18
        // This ensures ordering and simplifies the code
        // NOTE: We need to make them % tick spacing else UniV3 silently reverts
        // NOTE: This can create a few edge cases
        int24 tickLower = translator.getTickAtSqrtRatio(translator.getSqrtPriceX96GivenRatio(addParams.tokenBDenominator, addParams.tokenANumeratorHigh)) / configParams.TICK_SPACING * configParams.TICK_SPACING;
        int24 tickUpper = translator.getTickAtSqrtRatio(translator.getSqrtPriceX96GivenRatio(addParams.tokenBDenominator, addParams.tokenANumeratorLow)) /  configParams.TICK_SPACING * configParams.TICK_SPACING;
        require(tickLower < tickUpper, "Must have a delta"); // Check against edge case

        {
            // Mint
            IV3NFTManager.MintParams memory mintParams = IV3NFTManager.MintParams({
                token0: addParams.firstToken,
                token1: addParams.secondToken,
                fee: configParams.DEFAULT_FEE,
                tickLower: tickLower,
                tickUpper: tickUpper, // Not inclusive || // Does this forces to fees the other 59 ticks or not?
                amount0Desired: addParams.firstAmount,
                amount1Desired: addParams.secondAmount, // NOTE: Reverse due to something I must have messed up
                amount0Min: 0, // w/e you have?
                amount1Min: 0, // w/e you have?
                recipient: addParams.sendTo,
                deadline: block.timestamp
            });
            (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = IV3NFTManager(configParams.UNIV3_NFT_MANAGER).mint(mintParams);

            return tokenId;
        }
    }


    struct CurveDeployParams {
        address CURVE_FACTORY;
        string name;
        string symbol;

        // Coins from LpParams

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

    struct CurveLpParams {
        address tokenA;
        address tokenB;
        uint256 amtA;
        uint256 amtB;
        address sendTo; // LP token will go here
        address sweepTo; // We'll check for leftovers and send them to this
    }


    function _deployCurvePool(address tokenA, address tokenB, CurveDeployParams memory deployParams) internal returns (address) {
        address[2] memory coins = [tokenA, tokenB];

        address pool = ICurveFactory(deployParams.CURVE_FACTORY).deploy_pool(
            "name",
            "symbol",
            coins,
            
            deployParams.A, // uint256 A,
            deployParams.gamma, // uint256 gamma,
            deployParams.mid_fee, // uint256 mid_fee,
            deployParams.out_fee, // uint256 out_fee,
            deployParams.allowed_extra_profit, // uint256 allowed_extra_profit,
            deployParams.fee_gamma, // uint256 fee_gamma,
            deployParams.adjustment_step, // uint256 adjustment_step,
            deployParams.admin_fee, // uint256 admin_fee,
            deployParams.ma_half_time, // uint256 ma_half_time,
            deployParams.initial_price // uint256 initial_price | // NOTE: 1e18 Price = 1e18 on both sides, not sure how this works, but prob is just A * 1e18 / B
        );

        return pool;
    }

    // Factory, etc..
    function deployAndProvideToCurve(CurveDeployParams memory deployParams, CurveLpParams memory lpParams) external returns (address, uint256) {
        // Call factory
        // Deploy Pool
        // Provide Liquidity
        // Send tokens back
        address pool = _deployCurvePool(lpParams.tokenA, lpParams.tokenB, deployParams);
        

        // We LP via the NFT Manager
        ERC20(lpParams.tokenA).approve(address(pool), lpParams.amtA);
        ERC20(lpParams.tokenB).approve(address(pool), lpParams.amtB);

        uint256 amt = ICurvePool(pool).add_liquidity([lpParams.amtA, lpParams.amtB], 0); // NOTE: Slippage

        _sweep(lpParams.tokenA, lpParams.sweepTo);
        _sweep(lpParams.tokenB, lpParams.sweepTo);

        ERC20(ICurvePool(pool).token()).transfer(lpParams.sendTo, amt);

        return (pool, amt);
    }

}
