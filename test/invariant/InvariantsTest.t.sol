// SPDX-License-Identifier: MIT

// Have our invariant aka properties

// What our invariants?

// 1. The total supply of DSC should be less then the total value of collateral
// 2. Getter view function should never rever <- evergreen invariant

pragma solidity ^0.8.20;

import {console} from 'forge-std/console.sol';
import {Test} from 'forge-std/Test.sol';
import {ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {StdInvariant} from 'forge-std/StdInvariant.sol';
import {DecentralizedStableCoin} from "../../src/contracts/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/contracts/DSCEngine.sol";
import {Handler} from "../invariant/Handler.t.sol";

contract InvariantsTest is StdInvariant, Test  {
    DeployDSC deployer;
    DSCEngine engine;
    HelperConfig config;
    DecentralizedStableCoin dsc;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,,weth, wbtc,) = config.activeNetworkConfig();

        handler = new Handler(engine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();

        uint256 totalWethDeposited = ERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = ERC20(wbtc).balanceOf(address(engine));

        uint256 totalWethUsdValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 totalWbtcUsdValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("Times mint was called: ", handler.timesMintWasCalled());

        assert(totalWethUsdValue + totalWbtcUsdValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {

    }
}
