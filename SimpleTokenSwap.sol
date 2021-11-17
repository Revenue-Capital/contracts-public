// SPDX-License-Identifier: MIT

pragma solidity =0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract SimpleTokenSwap is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public srcToken;
    IERC20 public trgToken;
    uint256 internal srcTokenDecimals;
    uint256 internal trgTokenDecimals;

    uint256 public startBlock;
    uint256 public closeBlock;

    address public swapAddress;
    uint256 public swapSrcRatio;
    uint256 public swapTrgRatio;

    event StartBlockChanged(uint256 block);
    event CloseBlockChanged(uint256 block);
    event SwapAddressChanged(address indexed addr);
    event SwapConversionChanged(uint256 srcRatio, uint256 trgRatio);

    constructor() {
        setSwapAddress(0x000000000000000000000000000000000000dEaD);
        setSwapConversion(1, 1);
    }

    function setTokenPair(IERC20 srcTokenAddress, uint256 srcTokenDec, IERC20 trgTokenAddress, uint256 trgTokenDec)
        public onlyOwner
    {
        require(address(srcToken) == address(0), 'SimpleTokenSwap: token address already set');
        require(address(trgToken) == address(0), 'SimpleTokenSwap: token address already set');
        require(address(srcTokenAddress) != address(0), 'SimpleTokenSwap: cannot set zero-address as one of the tokens');
        require(address(trgTokenAddress) != address(0), 'SimpleTokenSwap: cannot set zero-address as one of the tokens');
        require(srcTokenDec > 0, 'SimpleTokenSwap: token decimals needs to be higher than zero');
        require(trgTokenDec > 0, 'SimpleTokenSwap: token decimals needs to be higher than zero');
        srcToken = srcTokenAddress;
        trgToken = trgTokenAddress;
        srcTokenDecimals = srcTokenDec;
        trgTokenDecimals = trgTokenDec;
    }

    function setStartBlock(uint256 _startBlock) public onlyOwner {
        require(startBlock == 0, 'SimpleTokenSwap: start block already set');
        require(_startBlock > 0, 'SimpleTokenSwap: start block needs to be higher than zero!');
        startBlock = _startBlock;
        emit StartBlockChanged(startBlock);
    }

    function setCloseBlock(uint256 _closeBlock) public onlyOwner {
        require(startBlock != 0, 'SimpleTokenSwap: start block needs to be set first');
        require(closeBlock == 0, 'SimpleTokenSwap: close block already set');
        require(_closeBlock > startBlock, 'SimpleTokenSwap: close block needs to be higher than start one!');
        closeBlock = _closeBlock;
        emit CloseBlockChanged(closeBlock);
    }

    function setSwapAddress(address addr) public onlyOwner {
        swapAddress = addr; // by default swap address is zero, meaning tokens are burned on swap
        emit SwapAddressChanged(addr);
    }

    function setSwapConversion(uint256 srcRatio, uint256 trgRatio) public onlyOwner {
        require(srcRatio > 0 && trgRatio > 0, 'SimpleTokenSwap: conversions need to have be higher than zero!');
        swapSrcRatio = srcRatio; // by default swap conversion is 0
        swapTrgRatio = trgRatio; // by default swap conversion is 0
        emit SwapConversionChanged(srcRatio, trgRatio);
    }

    function withdrawTokens() external onlyOwner {
        srcToken.safeTransfer(owner(), srcToken.balanceOf(address(this)));
        trgToken.safeTransfer(owner(), trgToken.balanceOf(address(this)));
    }

    function exchangeTokens(uint256 amount) external {
        // amount eq to zero is allowed
        require(startBlock > 0 && block.number >= startBlock, 'SimpleTokenSwap: not started yet');
        require(closeBlock == 0 || block.number <= closeBlock, 'SimpleTokenSwap: not active anymore');
        require(amount > 0, 'SimpleTokenSwap: amount needs to be higher than zero');

        uint256 srcAmount = amount;
        uint256 trgAmount = amount;

        if (srcTokenDecimals < trgTokenDecimals) {
            trgAmount = trgAmount.mul(10**(trgTokenDecimals-srcTokenDecimals));
        }
        if (srcTokenDecimals > trgTokenDecimals) {
            trgAmount = trgAmount.div(10**(srcTokenDecimals-trgTokenDecimals));
        }

        trgAmount = trgAmount.mul(swapTrgRatio).div(swapSrcRatio);

        uint256 srcBalance = srcToken.balanceOf(address(msg.sender));
        uint256 trgBalance = trgToken.balanceOf(address(this));

        require(srcAmount <= srcBalance, 'SimpleTokenSwap: you dont have enough tokens to exchange');
        require(trgAmount <= trgBalance, 'SimpleTokenSwap: contract does not have enough tokens to exchange');

        srcToken.safeTransferFrom(address(msg.sender), swapAddress, srcAmount);
        trgToken.safeTransfer(address(msg.sender), trgAmount);
    }
}