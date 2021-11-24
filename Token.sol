// SPDX-License-Identifier: MIT

pragma solidity =0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./AntiBot.sol";

/**
 * @title Token
 * @dev BEP20 compatible token.
 */
contract Token is ERC20Burnable, Ownable, AntiBot {

    /**
     * @dev Mints all tokens to deployer
     * @param amount Initial supply
     * @param name Token name.
     * @param symbol Token symbol.
     */
    constructor(uint256 amount, string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(_msgSender(), amount);
    }

    /**
     * @dev Returns the address of the current owner.
     *
     * IMPORTANT: This method is required to be able to transfer tokens directly between their Binance Chain
     * and Binance Smart Chain. More on this issue can be found in:
     * https://github.com/binance-chain/BEPs/blob/master/BEP20.md#5116-getowner
     */
    function getOwner() external view returns (address) {
        return owner();
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual override transferThrottler(sender, recipient, amount) {
        super._transfer(sender, recipient, amount);
    }
}