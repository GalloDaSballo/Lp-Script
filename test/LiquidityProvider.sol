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
            sendTo: address(this), // We'll sweep the rest to address | amtOfOtherTokenToLP / amtToLP IS the Price we will use
            sweepTo: address(this),
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

            uint160 expectedPrice = translator.getSqrtPriceX96GivenRatio(lpParams.amtA, lpParams.amtB);
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

    function test_deployAndCheck_curve() public {
        deployer = new LiquidityProvider();

        // tER20 x 2
        // Param stuff
        // Deploy and check
        ERC20 tokenA = new ERC20("0", "Token0");
        ERC20 tokenB = new ERC20("1", "Token1");

        tokenA.mint(address(deployer), 1e18);
        tokenB.mint(address(deployer), 1e18);

        // Send the tokens to the deployer
        LiquidityProvider.CurveDeployParams memory lpParams = LiquidityProvider.CurveDeployParams({
            tokenA: address(tokenA),
            tokenB: address(tokenB),
            amtA: 1e18,
            amtB: 1e18,
            sendLpTo: address(this), // We'll sweep the rest to address | amtOfOtherTokenToLP / amtToLP IS the Price we will use
            sweepTo: address(this)
        });

        (address pool, uint256 amtLp) = deployer.deployAndProvideToCurve(lpParams);


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
