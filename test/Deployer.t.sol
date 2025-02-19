// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Deployer} from "../src/Deployer.sol";

import {ERC20} from "../src/mocks/ERC20.sol";

contract DeployerTest is Test {

    // Deploy and check that it actually works
    // 2 Tokens you deploy in Fork Test
    // You just run it
    // Check that you get the intended result

    function test_deployAndCheck() public {
        Deployer deployer = new Deployer();

        // tER20 x 2
        // Param stuff
        // Deploy and check
        ERC20 token1 = new ERC20("0", "Token0");
        ERC20 token2 = new ERC20("1", "Token1");

        token1.mint(address(deployer), 1e18);
        token2.mint(address(deployer), 1e18);



        // Send the tokens to the deployer
        Deployer.ConstructorParams memory params = Deployer.ConstructorParams({
            token: address(token1),
            otherToken: address(token2),
            amtOfOtherTokenToLP: 1e18,
            amtToMint: 0,
            amtToLP: 1e18, // We'll sweep the rest to address | amtOfOtherTokenToLP / amtToLP IS the Price we will use
            sendLpTo: address(this),
            sweepTo: address(this),
        
            tickMultiplierA: int24(100), // How many ticks to LP around? 
            tickMultiplierB: int24(100) // How many ticks to LP around? 
        });

        deployer.initialize(params);

        

    }
}
