// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity 0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IDSCEngine} from "../interfaces/IDSCEngine.sol";
import {DecentralizedStableCoin} from './DecentralizedStableCoin.sol';


/**
 * @title DSCEngine
 * @author 0xNTN
 * This system is desinged to be as minimal as possible, and have the token maintain a 1 token == $1 peg
 * This stablecoin has properties:
 * - Exogenous collateral
 * - Dollar pegged
 * - Algorithmically stable
 *
 * It is simillar as DAI if DAI had no governance, no fee, and was only backed with WETH and WBTC
 *
 * Our DSC system should be aways overcollateralized. At no point, should the value of all collater <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of DSC System. It handles all the login for minting and redeeming DSC, as well as deposit and withdraw collateral.
 *
 * @notice This contract it VERY loosly based on MakerDAO DSS (DAI) system.
 */
contract DSCEngine is IDSCEngine, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__MustBeMoreThenZero();
    error DSCEngine__TokenAddressesAndPriceFeedsAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreakesHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorTooHigh(uint256 healthFactor);
    error DSCEngine__HealthFactorNotImproved();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 private constant ADDITION_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //10% bonus
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds;
    DecentralizedStableCoin private immutable i_dsc;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_amountDscMinted;
    address[] private s_collateralTokens;


    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event DepositCollateral(address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollateral);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed tokenCollateralAddress, uint256 amountCollateral);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier moreThenZero(uint256 amount) {
        if(amount <= 0) {
            revert DSCEngine__MustBeMoreThenZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if(s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     *
     * @param tokenAddresses Allowed tokens
     * @param priceFeedsAddresses Corresponding price feeds
     * @param dscAddress DSC Token
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedsAddresses, address dscAddress) {
        if(tokenAddresses.length != priceFeedsAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsAddressesMustBeSameLength();
        }

        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedsAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     * @notice This function deposits the collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) external override {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice Follwe CEI
     * @notice Deposit collateral for a specific account
     * @param tokenCollateralAddress The account to deposit collateral for
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) public override moreThenZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit DepositCollateral(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if(!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @param tokenCollateralAddress The collaterall address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of decentralized stablecoin to burn
     * @notice This function redeems the collateral and burns DSC in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external override {
        burnDsc(amountDscToBurn);
        redeemCollatera(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollatera(address tokenCollateralAddress, uint256 amountCollateral) public override moreThenZero(amountCollateral) nonReentrant {

        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param amountDsc The amount of decentralized stablecoin to burn
     */
    function burnDsc(uint256 amountDsc) public override moreThenZero(amountDsc) nonReentrant {
        _burnDsc(amountDsc, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param amountDscToMint The amount of DSC to mint
     * @notice they must be more collateral value than minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public override moreThenZero(amountDscToMint) nonReentrant() {
        s_amountDscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if(!minted) {
            revert DSCEngine__MintFailed();
        }
        // emit MintDsc(msg.sender, amountDscToMint);
    }

    /**
     *
     * @param collateral The collateral to liquidate.
     * @param user The user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR.
     * @param debtToCover The amount of DSC you want to burn to improve the users health factor.
     * @notice You can partially liquidate a user.
     * @notice You will get a liquiditaion bonus for taking the users funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order of this to work.
     */
    function liquidate(address collateral, address user, uint256 debtToCover) external override moreThenZero(debtToCover) nonReentrant {
        uint256 startingHealthFactor = _healthFactor(user);

        if(startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorTooHigh(startingHealthFactor);
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 liquidationBonus = (LIQUIDATION_BONUS * PRECISION) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + liquidationBonus;

        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);

        if(endingHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor(
        address account
    ) public view override returns (uint256) {}

    /*//////////////////////////////////////////////////////////////
                     PRIVATE & INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_amountDscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice Return how close to liquidation the user is
     * If a user goes below 1, then they can be liquidated
     * @param user The user to check
     * @return The health factor of the user
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);

        if(userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreakesHealthFactor(userHealthFactor);
        }
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);

        if(!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @dev Low-level internal function, do not call unsless the function calling it is checking for health fasctor being broken
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_amountDscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);

        if(!success) {
            revert DSCEngine__TransferFailed();
        }

        i_dsc.burn(amountDscToBurn);
    }

    /*//////////////////////////////////////////////////////////////
                     PUBLIC & EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        (,int price,,,) = AggregatorV3Interface(s_priceFeeds[token]).latestRoundData();

        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITION_FEED_PRECISION);
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        uint256 numberOfCollateralTokens = s_collateralTokens.length;
        for(uint256 i = 0; i < numberOfCollateralTokens; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }

        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 value) public view returns (uint256) {
        (,int price,,,) = AggregatorV3Interface(s_priceFeeds[token]).latestRoundData();

        return (value * (uint256(price) * ADDITION_FEED_PRECISION)) / PRECISION;
    }

    function getAccountInformation(address user) external view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }
}
