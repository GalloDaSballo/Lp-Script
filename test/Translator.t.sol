// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {LiquidityProvider, UniV3Translator} from "../src/LiquidityProvider.sol";

import {IUniV3Factory, IV3NFTManager, IUnIV3Pool} from "../src/interfaces/IUni.sol";
import {ICurveFactory, ICurvePool} from "../src/interfaces/ICurve.sol";
import {ERC20} from "../src/mocks/ERC20.sol";

import {UniV3Translator} from "ebtc-amm-comparer/UniV3Translator.sol";

contract Translator is Test {
    LiquidityProvider deployer;

    // forge test --match-test test_ticks_sanity -vv
    function test_ticks_sanity() public {
        deployer = new LiquidityProvider();

        assertTrue(address(deployer.translator()) != address(0), "Traslator was deployed");

        UniV3Translator translator = deployer.translator();

        // Assert a couple of properties so LPing is feasible
        // low A, high B = low tick
        // high A, low B = high tick
        int24 tickLow = translator.getTickAtSqrtRatio(translator.getSqrtPriceX96GivenRatio(100, 1_000_000e18));
        int24 tickHigh = translator.getTickAtSqrtRatio(translator.getSqrtPriceX96GivenRatio(1_000_000e18, 100));

        console2.log("tickLow", tickLow);
        console2.log("tickHigh", tickHigh);

        assertGt(tickHigh, tickLow, "Ticks go from Low A to High B, to High A and Low B");
    }

    // forge test --match-test test_ticks_sanity_fuzz -vv
    function test_ticks_sanity_fuzz(uint64 amtLow, uint64 amtHigh) public {
        vm.assume(amtLow > 0);
        vm.assume(amtLow < amtHigh);
        deployer = new LiquidityProvider();

        assertTrue(address(deployer.translator()) != address(0), "Traslator was deployed");

        UniV3Translator translator = deployer.translator();

        // Assert a couple of properties so LPing is feasible
        // low A, high B = low tick
        // high A, low B = high tick
        int24 tickLow = translator.getTickAtSqrtRatio(translator.getSqrtPriceX96GivenRatio(amtLow, amtHigh));
        int24 tickHigh = translator.getTickAtSqrtRatio(translator.getSqrtPriceX96GivenRatio(amtHigh, amtLow));

        console2.log("tickLow", tickLow);
        console2.log("tickHigh", tickHigh);

        // NOTE: GTE to avoid gothcas
        assertGe(tickHigh, tickLow, "Ticks go from Low A to High B, to High A and Low B");
    }

   
}
