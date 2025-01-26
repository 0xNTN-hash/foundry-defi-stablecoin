// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {DSCEngine} from "../src/contracts/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/contracts/DecentralizedStableCoin.sol";
import {HelperConfig} from './HelperConfig.s.sol';

contract DeployDSC is Script {
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    address USER = makeAddr("USER");

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns(DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) = config.activeNetworkConfig();
        address deployerAddress = address(uint160((deployerKey)));

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerAddress);
        dsc = new DecentralizedStableCoin(deployerAddress);
        dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(dscEngine));

        vm.stopBroadcast();

        return (dsc, dscEngine, config);
    }
}
