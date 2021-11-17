// SPDX-License-Identifier: MIT

pragma solidity =0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title TokenVesting
 * @dev Vesting for BEP20 compatible token.
 */
contract TokenVesting is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    bool private locked;

    IERC20 public token;

    uint256 public immutable stopTime;
    uint256 public immutable initTime;
    uint256 public immutable initPercent;

    mapping (address => uint256) public currentBalances;
    mapping (address => uint256) public initialBalances;

    event TokensReleased(address beneficiary, uint256 amount);

    /**
     * @dev Configures vesting for specified accounts.
     * @param initTimestamp Timestamp after which initial amount of tokens is released.
     * @param stopTimestamp Timestamp after which entire amount of tokens is released.
     * @param initPercentValue Percent of tokens available after initial release.
     */
    constructor(uint256 initTimestamp, uint256 stopTimestamp, uint8 initPercentValue) {
        require(initPercentValue <= 100, "TokenVesting: Percent of tokens available after initial time cannot be greater than 100");
        require(stopTimestamp > initTimestamp, "TokenVesting: End time must be greater than start time");

        stopTime = stopTimestamp;
        initTime = initTimestamp;
        initPercent = initPercentValue;
    }

    /**
     * @dev Add beneficiaries
     */
    function addBeneficiaries(address[] memory beneficiaries, uint256[] memory balances) public onlyOwner {
        require(beneficiaries.length == balances.length, "TokenVesting: Beneficiaries and amounts must have the same length");
        require(!isLocked(), "TokenVesting: Contract has already been locked");

        for (uint256 i = 0; i < beneficiaries.length; ++i) {
            currentBalances[beneficiaries[i]] = balances[i];
            initialBalances[beneficiaries[i]] = balances[i];
        }
    }

    /**
     * @dev Lock the contract
     */
    function lock() public onlyOwner {
        locked = true;
    }

    /**
     * @dev Check if contract is locked
     */
    function isLocked() public view returns (bool) {
        return locked;
    }

    /**
     * @dev Sets token address.
     * @param tokenAddress Token address.
     */
    function setToken(IERC20 tokenAddress) public onlyOwner {
        require(address(token) == address(0), "TokenVesting: Token address already set");
        token = tokenAddress;
    }

    /**
     * @dev Sends all releases tokens (if any) to the caller.
     */
    function release() external {
        require(address(token) != address(0), "TokenVesting: Not configured yet");
        require(isLocked(), "TokenVesting: Not locked yet");
        require(block.timestamp >= initTime, "TokenVesting: Cannot release yet");
        require(initialBalances[msg.sender] > 0, "TokenVesting: Invalid beneficiary");
        require(currentBalances[msg.sender] > 0, "TokenVesting: Balance was already emptied");

        uint256 amount = unlockedBalance(msg.sender);

        require(amount > 0, "TokenVesting: Nothing to withdraw at this time");
        require(currentBalances[msg.sender] >= amount, "TokenVesting: Invalid amount");

        currentBalances[msg.sender] = currentBalances[msg.sender].sub(amount);

        token.safeTransfer(msg.sender, amount);

        emit TokensReleased(msg.sender, amount);
    }

    /**
     * @dev Returns current balance for given address.
     * @param beneficiary Address to check.
     */
    function currentBalance(address beneficiary) public view returns (uint256) {
        return currentBalances[beneficiary];
    }

    /**
     * @dev Returns initial balance for given address.
     * @param beneficiary Address to check.
     */
    function initialBalance(address beneficiary) public view returns (uint256) {
        return initialBalances[beneficiary];
    }

    /**
     * @dev Returns total withdrawn for given address.
     * @param beneficiary Address to check.
     */
    function releasedBalance(address beneficiary) public view returns (uint256) {
        return (initialBalances[beneficiary].sub(currentBalances[beneficiary]));
    }

    /**
     * @dev Returns withdrawal limit for given address.
     * @param beneficiary Address to check.
     */
    function unlockedBalance(address beneficiary) public view returns (uint256) {
        return (amountAllowedToWithdraw(initialBalances[beneficiary]).sub(releasedBalance(beneficiary)));
    }

    /**
     * @dev Returns withdrawal limit for given address.
     * @param beneficiary Address to check.
     */
    function assignedBalance(address beneficiary) public view returns (uint256) {
        return amountAllowedToWithdraw(initialBalances[beneficiary]);
    }

    /**
     * @dev Returns amount allowed to withdraw for given initial initialBalanceValue.
     * @param initialBalanceValue Initial initialBalanceValue.
     */
    function amountAllowedToWithdraw(uint256 initialBalanceValue) internal view returns (uint256) {
        if (initialBalanceValue == 0 || address(token) == address(0) || block.timestamp < initTime) {
            return 0;
        }

        if (block.timestamp >= stopTime) {
            return initialBalanceValue;
        }

        uint256 curTimeDiff = block.timestamp.sub(initTime);
        uint256 maxTimeDiff = stopTime.sub(initTime);

        uint256 beginPromile = initPercent.mul(10);
        uint256 otherPromile = curTimeDiff.mul(uint256(1000).sub(beginPromile)).div(maxTimeDiff);
        uint256 promile = beginPromile.add(otherPromile);

        if (promile >= 1000) {
            return initialBalanceValue;
        }

        return promile.mul(initialBalanceValue).div(1000);
    }

    /**
     * @dev Returns current token balance.
     */
    function balance() public view returns (uint256) {
        if (address(token) == address(0)) {
            return 0;
        }
        return token.balanceOf(address(this));
    }
}