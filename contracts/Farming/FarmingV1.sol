// SPDX-License-Identifier: MIT

pragma solidity =0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title Token Farming
 * @dev BEP20 compatible token.
 */
contract FarmingV1 is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 pendingRewards;
    }

    struct PoolInfo {
        uint256 lastRewardBlock;
        uint256 accTokenPerShare;
    }

    IERC20 public token;
    IERC20 public lpToken;

    uint256 public tokenPerBlock;
    uint256 public startBlock;
    uint256 public closeBlock;
    uint256 public tokenClaimed;
    uint256 public tokenRewarded;

    PoolInfo public mining;
    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event WithdrawRemaining(address indexed user, uint256 amount);

    event RewardChanged(uint256 reward);
    event StartBlockChanged(uint256 block);
    event CloseBlockChanged(uint256 block);

    function setTokenAddress(IERC20 _token, IERC20 _lpToken) public onlyOwner {
        require(address(_token) != address(0), 'Farming: token address needs to be different than zero!');
        require(address(_lpToken) != address(0), 'Farming: token address needs to be different than zero!');
        require(address(token) == address(0) && address(lpToken) == address(0), 'Farming: tokens already set!');
        token = _token;
        lpToken = _lpToken;
        mining = PoolInfo({
            lastRewardBlock: 0,
            accTokenPerShare: 0
        });
    }

    function setTokenPerBlock(uint256 _tokenPerBlock) public onlyOwner {
        require(_tokenPerBlock > 0, "Farming: amount of tokens per block should be greater than 0!");
        updatePool(); // update pool so it recalculates reward pool before tokenPerBlock change
        tokenPerBlock = _tokenPerBlock;
        emit RewardChanged(tokenPerBlock);
    }

    function setStartBlock(uint256 _startBlock) public onlyOwner {
        require(startBlock == 0, 'Farming: start block already set');
        require(_startBlock > 0, 'Farming: start block needs to be higher than zero!');
        startBlock = _startBlock;
        emit StartBlockChanged(startBlock);
    }

    function setCloseBlock(uint256 _closeBlock) public onlyOwner {
        require(startBlock != 0, 'Farming: start block needs to be set first');
        require(closeBlock == 0, 'Farming: close block already set');
        require(_closeBlock > startBlock, 'Farming: close block needs to be higher than start one!');
        closeBlock = _closeBlock;
        emit CloseBlockChanged(closeBlock);
    }

    function withdrawRemaining() public onlyOwner {
        require(startBlock != 0, 'Farming: start block needs to be set first');
        require(closeBlock != 0, 'Farming: close block needs to be set first');
        require(block.number > closeBlock, 'Farming: withdrawal of remaining funds not ready yet');
        updatePool();

        uint256 reservedAmount = tokenRewarded.sub(tokenClaimed);
        uint256 possibleAmount = token.balanceOf(address(this));
        uint256 unlockedAmount = 0;

        if (possibleAmount > reservedAmount) {
            unlockedAmount = possibleAmount.sub(reservedAmount);
        }
        if (unlockedAmount > 0) {
            token.safeTransfer(owner(), unlockedAmount);
            emit WithdrawRemaining(owner(), unlockedAmount);
        }
    }

    function farmingTokens(address addr) external view returns (uint256) {
        UserInfo storage user = userInfo[addr];
        return user.amount;
    }

    function pendingRewards(address _user) external view returns (uint256) {
        require(startBlock > 0 && block.number >= startBlock, 'Farming: not yet started');
        UserInfo storage user = userInfo[_user];
        uint256 accTokenPerShare = mining.accTokenPerShare;
        uint256 lpSupply = lpToken.balanceOf(address(this));
        uint256 lastMintedBlock = mining.lastRewardBlock;
        if (lastMintedBlock == 0) {
            lastMintedBlock = startBlock;
        }
        uint256 lastRewardBlock = getLastRewardBlock();
        if (lastRewardBlock == 0) {
            return 0;
        }
        if (lastRewardBlock > lastMintedBlock && lpSupply != 0) {
            uint256 multiplier = lastRewardBlock.sub(lastMintedBlock);
            uint256 tokenReward = multiplier.mul(tokenPerBlock);
            accTokenPerShare = mining.accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt).add(user.pendingRewards);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Farming: you need to specify amount higher than zero!");
        require(startBlock > 0 && block.number >= startBlock, 'Farming: not yet started');
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        updatePendingRewards(msg.sender);
        if (amount > 0) {
            user.amount = user.amount.add(amount);
            lpToken.safeTransferFrom(address(msg.sender), address(this), amount);
        }
        user.rewardDebt = user.amount.mul(mining.accTokenPerShare).div(1e12);
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Farming: you need to specify amount higher than zero!");
        require(startBlock > 0 && block.number >= startBlock, 'Farming: not yet started');
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= amount, "Farming: you cannot withdraw more than you have!");
        updatePool();
        updatePendingRewards(msg.sender);
        if (amount > 0) {
            user.amount = user.amount.sub(amount);
            lpToken.safeTransfer(address(msg.sender), amount);
        }
        user.rewardDebt = user.amount.mul(mining.accTokenPerShare).div(1e12);
        emit Withdraw(msg.sender, amount);
    }

    function claim() external {
        require(startBlock > 0 && block.number >= startBlock, 'Farming: not yet started');
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        updatePendingRewards(msg.sender);
        if (user.pendingRewards > 0) {
            uint256 claimedAmount = transferPendingRewards(msg.sender, user.pendingRewards);
            emit Claim(msg.sender, claimedAmount);
            user.pendingRewards = user.pendingRewards.sub(claimedAmount);
            tokenClaimed = tokenClaimed.add(claimedAmount);
        }
        user.rewardDebt = user.amount.mul(mining.accTokenPerShare).div(1e12);
    }

    function updatePool() internal {
        if (startBlock == 0 || block.number < startBlock) {
            return;
        }
        if (mining.lastRewardBlock == 0) {
            mining.lastRewardBlock = startBlock;
        }
        uint256 lastBlock = getLastRewardBlock();
        if (lastBlock <= mining.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            return;
        }
        uint256 multiplier = lastBlock.sub(mining.lastRewardBlock);
        uint256 tokenReward = multiplier.mul(tokenPerBlock);
        tokenRewarded = tokenRewarded.add(tokenReward);
        mining.accTokenPerShare = mining.accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        mining.lastRewardBlock = lastBlock;
    }

    function updatePendingRewards(address owner) internal {
        UserInfo storage user = userInfo[owner];
        uint256 pending = user.amount.mul(mining.accTokenPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            user.pendingRewards = user.pendingRewards.add(pending);
        }
    }

    function transferPendingRewards(address to, uint256 amount) internal returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        uint256 tokenBalance = token.balanceOf(address(this));
        if (tokenBalance == 0) {
            return 0;
        }
        if (tokenBalance > amount) {
            tokenBalance = amount;
        }
        token.safeTransfer(to, tokenBalance);
        return tokenBalance;
    }

    function getLastRewardBlock() internal view returns (uint256) {
        if (startBlock == 0) return 0;
        if (closeBlock == 0) return block.number;
        return (closeBlock < block.number) ? closeBlock : block.number;
    }
}
