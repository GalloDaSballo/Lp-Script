// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {LiquidityProvider, UniV3Translator} from "../src/LiquidityProvider.sol";

import {IUniV3Factory, IV3NFTManager, IUnIV3Pool} from "../src/interfaces/IUni.sol";
import {ICurveFactory, ICurvePool} from "../src/interfaces/ICurve.sol";
import {ERC20} from "../src/mocks/ERC20.sol";

contract LiquidityProviderTest is Test {
    // Deploy and check that it actually works
    // 2 Tokens you deploy in Fork Test
    // You just run it
    // Check that you get the intended result
    LiquidityProvider deployer;

    /// === UNIV3 Example Config === ///
    // Deploy new pool
    IUniV3Factory public UNIV3_FACTORY = IUniV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    // // Add liquidity
    IV3NFTManager public UNIV3_NFT_MANAGER = IV3NFTManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    int24 TICK_SPACING = 60;
    uint24 DEFAULT_FEE = 3000;


    // TODO: TEST and check
    function test_deployAndCheck_univ3() public {
        deployer = new LiquidityProvider();

        // tER20 x 2
        // Param stuff
        // Deploy and check
        ERC20 tokenA = new ERC20("0", "Token0");
        ERC20 tokenB = new ERC20("1", "Token1");

        tokenA.mint(address(deployer), 1e18);
        tokenB.mint(address(deployer), 1e18);

        LiquidityProvider.UniV3ConfigParams memory configParams = LiquidityProvider.UniV3ConfigParams({
            UNIV3_FACTORY: address(UNIV3_FACTORY),
            UNIV3_NFT_MANAGER: address(UNIV3_NFT_MANAGER),

            TICK_SPACING: 60,
            DEFAULT_FEE: 3000
        });

        // Send the tokens to the deployer
        LiquidityProvider.UniV3LpParams memory lpParams = LiquidityProvider.UniV3LpParams({
            tokenA: address(tokenA),
            tokenB: address(tokenB),
            amtA: 1e18,
            amtB: 1e18,
            expectedAmtA: 1e18,
            expectedAmtB: 1e18,
            sendTo: address(this), // We'll sweep the rest to address | amtOfOtherTokenToLP / amtToLP IS the Price we will use
            sweepTo: address(this),
            tickToInitializeAt: int24(0), // 1e18 | 1e18
            multipleTicksA: int24(100), // How many ticks to LP around?
            multipleTicksB: int24(100) // How many ticks to LP around?
        });

        (address pool, uint256 tokenId) = deployer.deployAndProvideToUniV3(configParams, lpParams);

        // TEST:

        // Pool is deployed
        // Pool is initialized
        // Pool has expected price
        assertTrue(address(deployer.translator()) != address(0), "Traslator was deployed");
        assertTrue(pool.code.length > 0, "Pool has been deployed");
        assertTrue(IUnIV3Pool(pool).slot0().sqrtPriceX96 != 0, "Pool is initialized");



        // We have the nft
        {
            assertEq(UNIV3_NFT_MANAGER.ownerOf(tokenId), lpParams.sendTo, "We have an NFT for LPing");
        }

        // Check basic math stuff
        {
            UniV3Translator translator = deployer.translator();

            uint160 expectedPrice = translator.getSqrtPriceX96GivenRatio(1e18, 1e18);
            int24 expectedMiddle = translator.getTickAtSqrtRatio(expectedPrice);
            _checkTicks(tokenId, expectedMiddle);
            assertEq(IUnIV3Pool(pool).slot0().sqrtPriceX96, expectedPrice, "Pool price is the intended one");
        }


        // TODO: Try to LP in an imbalanced way
        // Verify that it will work as intended, very important!


        tokenA.mint(address(deployer), 1e18);
        tokenB.mint(address(deployer), 1e18);

        {
            LiquidityProvider.AddLiquidityFromRatioParams memory lpParams2 = LiquidityProvider.AddLiquidityFromRatioParams({
                pool: address(pool),
                firstToken: IUnIV3Pool(pool).token0(),
                secondToken: IUnIV3Pool(pool).token1(),
                firstAmount: 1e18,
                secondAmount: 1e18,
                // By using [1, 1e18]: 1e18 we basically want to put 100% of token0 and w/e we can of tokenA
                expectedFirstAmount: 1e18,
                expectedSecondAmount: 0,
                tokenANumeratorLow: 1,
                tokenANumeratorHigh: 1e18,
                tokenBDenominator: 1e18,
                sendTo: address(this),
                sweepTo: address(this)
            });

            uint256 id = deployer.provideToUniV3WithCustomRatios(
                configParams,
                lpParams2
            );
            
            {
                assertEq(UNIV3_NFT_MANAGER.ownerOf(id), lpParams2.sendTo, "New NFT");
            }
        }
    }

    function _checkTicks(uint256 tokenId, int24 expectedMiddle) internal view {
            (,,,,,int24 tickLower, int24 tickUpper,,,,,) =
                UNIV3_NFT_MANAGER.positions(tokenId);

            assertLe(tickLower, expectedMiddle, "tick lower is less than middle");
            assertGe(tickUpper, expectedMiddle, "tick upper is higher than middle");
    }


    /// TODO: Set up test with realistic numbers
    /**

        400_000e18
        1e18
        300_000e18 - 1e18

        Write test that does that


        Example to deploy only on one side
     */
    
    function test_uniV3_realistic() public {
        // A test similar to the one above but with values that are closer to realistic
        deployer = new LiquidityProvider();

        ERC20 tokenA = new ERC20("Corn", "CORN");
        ERC20 tokenB = new ERC20("Bitcorn", "BTCN");

        uint64 ratioCorn = 400_000;

        uint256 bitcornAmount = 5.76e18; // 500k in USD
        uint256 cornAmount = bitcornAmount * ratioCorn; // 400_000k times the Bitcorn
    
        tokenA.mint(address(deployer), cornAmount);
        tokenB.mint(address(deployer), bitcornAmount);

        vm.label(address(tokenA), "CORN");
        vm.label(address(tokenB), "BTCN");

        UniV3Translator translator = deployer.translator();

        // 30 BPS pool, tick spacing from governance
        LiquidityProvider.UniV3ConfigParams memory configParams = LiquidityProvider.UniV3ConfigParams({
            UNIV3_FACTORY: address(UNIV3_FACTORY),
            UNIV3_NFT_MANAGER: address(UNIV3_NFT_MANAGER),

            TICK_SPACING: 60,
            DEFAULT_FEE: 3000
        });

        // Send the tokens to the deployer
        LiquidityProvider.UniV3LpParams memory lpParams = LiquidityProvider.UniV3LpParams({
            tokenA: address(tokenA),
            tokenB: address(tokenB),
            amtA: cornAmount,
            amtB: bitcornAmount,
            // We expect to use basically all tokens
            // TODO: Figure this out better | We use 100% of BTCN but not all of Corn cause of how it's skewed
            expectedAmtA: 0,
            expectedAmtB: 0,
            sendTo: address(this), // We'll sweep the rest to address | amtOfOtherTokenToLP / amtToLP IS the Price we will use
            sweepTo: address(this),
            tickToInitializeAt: translator.getTickAtSqrtRatio(translator.getSqrtPriceX96GivenRatio(1, ratioCorn)),
            // 1.001 ^ 1500 == 1.1618255296 // We're moving 16% above and below to offer a big range of liquidity
            multipleTicksA: int24(1500), // How many ticks to LP around?
            multipleTicksB: int24(1500) // How many ticks to LP around?
        });

        (address pool, uint256 tokenId) = deployer.deployAndProvideToUniV3(configParams, lpParams);

        // TEST:
        // TODO: Prove tick makes sense and log it so we can test on mainnet
        {   
            // Pool has expected price
            assertTrue(IUnIV3Pool(pool).slot0().sqrtPriceX96 != 0, "Pool is initialized");
            assertTrue(IUnIV3Pool(pool).slot0().tick == -128999, "Tick matches test_sanity_ticks_mainnet");
            // We have the nft
            assertEq(UNIV3_NFT_MANAGER.ownerOf(tokenId), lpParams.sendTo, "We have an NFT for LPing");
            assertTrue(IUnIV3Pool(pool).token1() == address(tokenB), "BTCN is 1");
        }

        /// Imabalanced LP provision "defende the price"
        /// We have LPd at the right price (15% around 1e18 | 400_000e18)
        // let's LP to defend at 500k | 1e18 


        /// Another $500k
        tokenB.mint(address(deployer), bitcornAmount);
        

        {
            LiquidityProvider.AddLiquidityFromRatioParams memory lpParams2 = LiquidityProvider.AddLiquidityFromRatioParams({
                pool: address(pool),
                firstToken: IUnIV3Pool(pool).token0(),
                secondToken: IUnIV3Pool(pool).token1(),
                firstAmount: 0,
                secondAmount: bitcornAmount,

                expectedFirstAmount: 0,
                expectedSecondAmount: bitcornAmount,
                // Current Price is 400_000 : 1 so bidding below means we only use BTCN
                tokenANumeratorLow: 500_000,
                tokenANumeratorHigh: 600_000, 
                tokenBDenominator: 1,
                sendTo: address(this),
                sweepTo: address(this)
            });

            uint256 id = deployer.provideToUniV3WithCustomRatios(
                configParams,
                lpParams2
            );
            
            {
                assertEq(UNIV3_NFT_MANAGER.ownerOf(id), lpParams2.sendTo, "New NFT");

                // TODO: Assert ticks upper and lower for the position
            }
        }


    }

    ICurveFactory CURVE_FACTORY = ICurveFactory(0xF18056Bbd320E96A48e3Fbf8bC061322531aac99);


    function test_deployAndCheck_curve() public {
        deployer = new LiquidityProvider();

        // tER20 x 2
        // Param stuff
        // Deploy and check
        ERC20 tokenA = new ERC20("0", "Token0");
        ERC20 tokenB = new ERC20("1", "Token1");

        tokenA.mint(address(deployer), 1e18);
        tokenB.mint(address(deployer), 1e18);

        LiquidityProvider.CurveDeployParams memory deployParams = LiquidityProvider.CurveDeployParams({
            CURVE_FACTORY: address(CURVE_FACTORY),
            
            name: "The Pool",
            symbol: "POOL",

            A: 400000, // uint256 A,
            gamma: 145000000000000, // uint256 gamma,
            mid_fee: 26000000, // uint256 mid_fee,
            out_fee: 45000000, // uint256 out_fee,
            allowed_extra_profit: 2000000000000, // uint256 allowed_extra_profit,
            fee_gamma: 230000000000000, // uint256 fee_gamma,
            adjustment_step: 146000000000000, // uint256 adjustment_step,
            admin_fee: 5000000000, // uint256 admin_fee,
            ma_half_time: 600, // uint256 ma_half_time
            initial_price: 1e18
        });


        // Send the tokens to the deployer
        LiquidityProvider.CurveLpParams memory lpParams = LiquidityProvider.CurveLpParams({
            tokenA: address(tokenA),
            tokenB: address(tokenB),
            amtA: 1e18,
            amtB: 1e18,
            sendTo: address(this), // We'll sweep the rest to address | amtOfOtherTokenToLP / amtToLP IS the Price we will use
            sweepTo: address(this)
        });

        (address pool, ) = deployer.deployAndProvideToCurve(deployParams, lpParams);


        // Verify the pool exists
        assertTrue(pool.code.length > 0, "Pool has been deployed");
        // Verify the LP Token exists
        address lpToken = ICurvePool(pool).token();
        assertTrue(lpToken.code.length > 0, "Token has been deployed");

        // Verify we got the LP token
        assertGt(ERC20(lpToken).balanceOf(address(this)), 0, "We got some LP");
        // Verify the pool has the correct amounts
        assertEq(tokenA.balanceOf(pool), lpParams.amtA, "A AMT OK");
        assertEq(tokenB.balanceOf(pool), lpParams.amtB, "B AMT OK");

        // TODO: UNCLEAR | Verify the price
        
    }
}
