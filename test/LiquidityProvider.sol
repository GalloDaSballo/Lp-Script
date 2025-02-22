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

    // Deploy new pool
    IUniV3Factory public constant UNIV3_FACTORY = IUniV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    // Add liquidity
    IV3NFTManager public constant UNIV3_NFT_MANAGER = IV3NFTManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    int24 constant TICK_SPACING = 60; // Souce: Docs | TODO
    uint24 constant DEFAULT_FEE = 3000;

    function test_deployAndCheck_univ3() public {
        deployer = new LiquidityProvider();

        // tER20 x 2
        // Param stuff
        // Deploy and check
        ERC20 tokenA = new ERC20("0", "Token0");
        ERC20 tokenB = new ERC20("1", "Token1");

        tokenA.mint(address(deployer), 1e18);
        tokenB.mint(address(deployer), 1e18);

        LiquidityProvider.UniV3ConfigParams memory uniV3ConfigParams = LiquidityProvider.UniV3ConfigParams({
            UNIV3_FACTORY: address(UNIV3_FACTORY),
            UNIV3_NFT_MANAGER: address(UNIV3_NFT_MANAGER),
            TICK_SPACING: TICK_SPACING,
            DEFAULT_FEE: DEFAULT_FEE
        });

        LiquidityProvider.UniV3PoolParams memory uniV3PoolParams = LiquidityProvider.UniV3PoolParams({
            tokenA: address(tokenA),
            tokenB: address(tokenB),
            amtA: 1e18,
            amtB: 1e18,
            sendLpTo: address(this), // We'll sweep the rest to address | amtOfOtherTokenToLP / amtToLP IS the Price we will use
            sweepTo: address(this),
            tickMultiplierA: int24(100), // How many ticks to LP around?
            tickMultiplierB: int24(100) // How many ticks to LP around?
        });

        // Send the tokens to the deployer
        LiquidityProvider.UniV3DeployParams memory params = LiquidityProvider.UniV3DeployParams({
            uniV3ConfigParams: uniV3ConfigParams,
            uniV3PoolParams: uniV3PoolParams
        });

        (address pool, uint256 tokenId) = deployer.deployAndProvideToUniV3(params);

        // TEST:

        // Pool is deployed
        // Pool is initialized
        // Pool has expected price
        assertTrue(address(deployer.translator()) != address(0), "Traslator was deployed");
        assertTrue(pool.code.length > 0, "Pool has been deployed");
        assertTrue(IUnIV3Pool(pool).slot0().sqrtPriceX96 != 0, "Pool is initialized");



        // We have the nft
        {
            assertEq(UNIV3_NFT_MANAGER.ownerOf(tokenId), uniV3PoolParams.sendLpTo, "We have an NFT for LPing");
        }

        // Check basic math stuff
        {
            UniV3Translator translator = deployer.translator();

            uint160 expectedPrice = translator.getSqrtPriceX96GivenRatio(uniV3PoolParams.amtA, uniV3PoolParams.amtB);
            int24 expectedMiddle = translator.getTickAtSqrtRatio(expectedPrice);
            _checkTicks(tokenId, expectedMiddle);
            assertEq(IUnIV3Pool(pool).slot0().sqrtPriceX96, expectedPrice, "Pool price is the intended one");
        }
    }

    function _checkTicks(uint256 tokenId, int24 expectedMiddle) internal {
            (,,,,,int24 tickLower, int24 tickUpper,,,,,) =
                UNIV3_NFT_MANAGER.positions(tokenId);

            assertLe(tickLower, expectedMiddle, "tick lower is less than middle");
            assertGe(tickUpper, expectedMiddle, "tick upper is higher than middle");
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


        LiquidityProvider.CurveDeployParams memory curveDeployParams = LiquidityProvider.CurveDeployParams({
            A: 400000,
            gamma: 145000000000000,
            mid_fee: 26000000,
            out_fee: 45000000,
            allowed_extra_profit: 2000000000000,
            fee_gamma: 230000000000000,
            adjustment_step: 146000000000000,
            admin_fee: 5000000000,
            ma_half_time: 600,
            initial_price: 1e18
        });

        // Send the tokens to the deployer
        LiquidityProvider.CurvePoolParams memory params = LiquidityProvider.CurvePoolParams({
            CURVE_FACTORY: address(CURVE_FACTORY),
            tokenA: address(tokenA),
            tokenB: address(tokenB),
            amtA: 1e18,
            amtB: 1e18,
            sendLpTo: address(this), // We'll sweep the rest to address | amtOfOtherTokenToLP / amtToLP IS the Price we will use
            sweepTo: address(this)
        });

        (address pool, uint256 amtLp) = deployer.deployAndProvideToCurve(curveDeployParams, params);


        // Verify the pool exists
        assertTrue(pool.code.length > 0, "Pool has been deployed");
        // Verify the LP Token exists
        address lpToken = ICurvePool(pool).token();
        assertTrue(lpToken.code.length > 0, "Token has been deployed");

        // Verify we got the LP token
        assertGt(ERC20(lpToken).balanceOf(address(this)), 0, "We got some LP");
        // Verify the pool has the correct amounts
        assertEq(tokenA.balanceOf(pool), params.amtA, "A AMT OK");
        assertEq(tokenB.balanceOf(pool), params.amtB, "B AMT OK");

        // TODO: UNCLEAR | Verify the price
        
    }
}
