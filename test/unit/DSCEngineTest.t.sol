// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from 'forge-std/Test.sol';
import {DSCEngine} from "../../src/contracts/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/contracts/DecentralizedStableCoin.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DSCEngine engine ;
    HelperConfig config;
    DecentralizedStableCoin dsc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;

    address USER = makeAddr('User');
    uint256 AMOUT_COLLATERAL = 1 ether;


    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        MockERC20(weth).mint(USER, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses = [weth];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedsAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE TESTS
    //////////////////////////////////////////////////////////////*/
    function testGetUsdValue() public view {
        uint256 ethAmount = 5 ether;
        uint256 expectedUsdValue = 10000e18;
        uint256 actualUsdValue = engine.getUsdValue(weth, ethAmount);

        assertEq(expectedUsdValue, actualUsdValue);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedTokenValue = 0.05 ether;
        uint256 actualTokenValue = engine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(expectedTokenValue, actualTokenValue);
    }

    /*//////////////////////////////////////////////////////////////
                         DEPOSIT_COLLATERAL TEST
    //////////////////////////////////////////////////////////////*/
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(USER), AMOUT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThenZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnApprovalCollateral() public {
        MockERC20 ranToken = new MockERC20("RanToken", "RanToken", msg.sender, 1000e8);

        vm.startPrank(USER);
        MockERC20(ranToken).approve(address(USER), AMOUT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), AMOUT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), AMOUT_COLLATERAL);
        engine.depositCollateral(weth, AMOUT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralValueInUsd = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(expectedTotalDscMinted, totalDscMinted);
        assertEq(expectedCollateralValueInUsd, AMOUT_COLLATERAL);
    }
}
