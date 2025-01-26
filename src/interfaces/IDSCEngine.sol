// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

interface IDSCEngine {
    function depositCollateralAndMintDsc(address, uint256, uint256) external;

    function depositCollateral(address tokenCollateralAddress, uint256 amount) external;

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external;

    function redeemCollatera(address tokenCollateralAddress, uint256 amountCollateral) external;

    function burnDsc(uint256 amountDsc) external;

    function mintDsc(uint256) external;

    function liquidate(address collateral, address user, uint256 debtToCover) external;

    function getHealthFactor(address account) external view returns (uint256);

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) external view returns (uint256);

    function getAccountCollateralValue(address user) external view returns (uint256);

    function getUsdValue(address token, uint256 value) external view returns (uint256);
}
