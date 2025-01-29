// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from 'forge-std/Test.sol';
import {DSCEngine} from "../../src/contracts/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/contracts/DecentralizedStableCoin.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockTransferFailedToken} from "../mocks/MockTransferFailedToken.sol";
import {MockMintFailedToken} from "../mocks/MockMintFailedToken.sol";
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
    uint256 REDEEM_AMOUT_COLLATERAL = 0.5 ether;
    uint256 AMOUT_DSC_TO_MINT = 2 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        MockERC20(weth).mint(USER, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier depositCollateral() {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), AMOUT_COLLATERAL);
        engine.depositCollateral(weth, AMOUT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositCollateralAndMintDsc() {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), AMOUT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUT_COLLATERAL, AMOUT_DSC_TO_MINT);
        vm.stopPrank();
        _;
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
                         DEPOSIT_COLLATERAL TESTS
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



    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralValueInUsd = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(expectedTotalDscMinted, totalDscMinted);
        assertEq(expectedCollateralValueInUsd, AMOUT_COLLATERAL);
    }

    /*//////////////////////////////////////////////////////////////
                              MINTING TESTS
    //////////////////////////////////////////////////////////////*/
    function testRevertsIfMiningZero() public {
        vm.startBroadcast();
        MockERC20(address(dsc)).approve(address(engine), AMOUT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThenZero.selector);
        engine.mintDsc(0);
        vm.stopBroadcast();
    }

    // function testRevertsIfMintAmountBreaksHealthFactor() public depositCollateral {
    //
    // }

    function testRevertsIfMintingFails() public {
        tokenAddresses = [weth];
        priceFeedAddresses = [wethUsdPriceFeed];
        MockMintFailedToken mockFailedDscToken = new MockMintFailedToken("FailedToken", "FailedToken", msg.sender, 1000e8);

        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockFailedDscToken));

        vm.startPrank(USER);
        MockERC20(weth).approve(address(mockDscEngine), AMOUT_COLLATERAL);
        mockDscEngine.depositCollateral(weth, AMOUT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDscEngine.mintDsc(AMOUT_DSC_TO_MINT);
        vm.stopPrank();
    }

    function testUpdateBalanceAfterMinting() public depositCollateral {
        (uint256 startingTotalDscMinted,) = engine.getAccountInformation(USER);

        vm.prank(USER);
        engine.mintDsc(AMOUT_DSC_TO_MINT);

        (uint256 finalTotalDscMinted,) = engine.getAccountInformation(USER);

        assertEq(startingTotalDscMinted + AMOUT_DSC_TO_MINT, finalTotalDscMinted);
    }

    /*//////////////////////////////////////////////////////////////
                         REDEEM TESTS
    //////////////////////////////////////////////////////////////*/
    function testRedeemRevertsIfAmountIsZero() public depositCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThenZero.selector);
        vm.prank(USER);
        engine.redeemCollateral(weth, 0);
    }

    function testRedeemRevertsIfTransferFails() public {
        MockTransferFailedToken mockFailedCollateralToken = new MockTransferFailedToken("FailedToken", "FailedToken", msg.sender, 1000e8);
        MockTransferFailedToken(mockFailedCollateralToken).mint(USER, 10 ether);

        tokenAddresses = [address(mockFailedCollateralToken)];
        priceFeedAddresses = [wethUsdPriceFeed];

        DSCEngine engineWithFailedTransfer = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        vm.startPrank(USER);
        MockTransferFailedToken(mockFailedCollateralToken).approve(address(engineWithFailedTransfer), AMOUT_COLLATERAL);
        engineWithFailedTransfer.depositCollateral(address(mockFailedCollateralToken), AMOUT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        engineWithFailedTransfer.redeemCollateral(address(mockFailedCollateralToken), REDEEM_AMOUT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemWithZeroDscMined() public depositCollateral {
        vm.startPrank(USER);
        engine.redeemCollateral(weth, REDEEM_AMOUT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertIfRedeemMoreThanDeposited() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotEnoughCollateral.selector);
        engine.redeemCollateral(weth, AMOUT_COLLATERAL + 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           HEALTHFACTOR TESTS
    //////////////////////////////////////////////////////////////*/
    function testHealthFactorIsCorrect() public depositCollateralAndMintDsc {
        /**
         * ETH $2000
         * Collateral 1ETH = $2000
         * Mint 2 DSC
         * 50% liquidation threshold
         * 2000 * 0.5 = 1000
         * 1000 / 2 = 500
         */

        uint256 expectedHealthFactor = 500 ether;

        vm.prank(USER);
        uint256 actualHealthFactor = engine.getHealthFactor(USER);

        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    /*//////////////////////////////////////////////////////////////
                           LIQUIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                      VIEW & PURE FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
}
