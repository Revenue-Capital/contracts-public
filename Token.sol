// SPDX-License-Identifier: MIT

pragma solidity =0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title Token
 * @dev BEP20 compatible token.
 */
contract Token is ERC20Burnable, Ownable {

    /**
     * @dev Mints all tokens to deployer
     * @param amount Initial supply
     * @param name Token name.
     * @param symbol Token symbol.
     */
    constructor(uint256 amount, string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(_msgSender(), amount);
    }
}