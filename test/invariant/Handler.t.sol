// SPDX-License-Identifier: MIT
// Handler is going to narrow down the way we call functions

pragma solidity ^0.8.20;

import {Test} from 'forge-std/Test.sol';
import {DecentralizedStableCoin} from "../../src/contracts/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/contracts/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    DeployDSC public deployer;
    MockERC20 public weth;
    MockERC20 public wbtc;
    MockV3Aggregator public wethUsdPriceFeed;
    MockV3Aggregator public wbtcUsdPriceFeed;

    uint256 public timesMintWasCalled = 0;
    address[] public usersWithCollateralDeposited;

    uint256 MAX_DEPOSIT_SIZE = type(uint56).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory tokens = dscEngine.getCollateralTokens();

        weth = MockERC20(tokens[0]);
        wbtc = MockERC20(tokens[1]);
        wethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
        wbtcUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(wbtc)));
    }

    function mindDsc(uint256 amountDscToMint, uint256 addressSeed) public {
        if(usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);

        if(maxDscToMint < 0) {
            return;
        }

        amountDscToMint = bound(amountDscToMint, 0, uint256(maxDscToMint));
        if(amountDscToMint == 0) {
            return;
        }

        vm.startPrank(sender);
        dscEngine.mintDsc(amountDscToMint);
        vm.stopPrank();

        timesMintWasCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        MockERC20 collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        usersWithCollateralDeposited.push(msg.sender);
        vm.stopPrank();
    }

    // This breaks the invariant
    // function updateCollateralPriceFeed(uint96 newWethPrice, uint96 newBtcPrice) public {
    //     wethUsdPriceFeed.updateAnswer(int256(uint256(newWethPrice)));
    //     wbtcUsdPriceFeed.updateAnswer(int256(uint256(newBtcPrice)));
    // }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        MockERC20 collateral = _getCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem-1);

        if(amountCollateral <= 0) {
            return;
        }

        dscEngine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }


    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (MockERC20) {
        if(collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
