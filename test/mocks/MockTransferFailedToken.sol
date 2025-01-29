// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockTransferFailedToken is ERC20 {
    error DecentralizedStableCoin__MustBeMoreThenZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor(
        string memory name,
        string memory symbol,
        address initialAccount,
        uint256 initialBalance
    )
        payable
        ERC20(name, symbol)
    {
        _mint(initialAccount, initialBalance);
    }

    function mint(address to, uint256 amount) external returns (bool) {
        _mint(to, amount);
        return true;
    }

    function transfer(address, uint256) public pure override returns (bool) {
        return false;
    }
}
