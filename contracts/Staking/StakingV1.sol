// SPDX-License-Identifier: MIT

pragma solidity =0.8.6;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

/**
 * @title Token Staking
 * @dev BEP20 compatible token.
 */
contract StakingV1 is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 pendingRewards;
        uint256 lockedTimestamp;
    }

    struct PoolInfo {
        uint256 poolShare;
        uint256 lastRewardBlock;
        uint256 tokenPerShare;
        uint256 tokenRStaked;
        uint256 tokenClaimed;
        uint256 tokenAwarded;
        uint256 tokenLimited;
        uint256 lockupTimer;
    }

    IERC20 public token;

    uint256 public tokenPerBlock;
    uint256 public startBlock;
    uint256 public closeBlock;

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    uint256 public totalPoolShare;
    uint256 public maxPid;

    uint256 public lastChangeTimestamp;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);
    event WithdrawRemaining(address indexed user, uint256 amount);

    event RewardChanged(uint256 reward);
    event StartBlockChanged(uint256 block);
    event CloseBlockChanged(uint256 block);

    constructor(uint256[] memory poolShare, uint256[] memory poolTimer, uint256[] memory poolLimit) {
        require(poolShare.length == poolTimer.length, 'Staking: Invalid constructor parameters set!');
        require(poolTimer.length == poolLimit.length, 'Staking: Invalid constructor parameters set!');

        for (uint i=0; i<poolShare.length; i++) {
            addPool(poolShare[i], poolTimer[i], poolLimit[i]);
        }
    }

    function setTokenAddress(IERC20 _token) public onlyOwner {
        require(address(_token) != address(0), 'Staking: token address needs to be different than zero!');
        require(address(token) == address(0), 'Staking: token already set!');
        token = _token;
    }

    function setTokenPerBlock(uint256 _tokenPerBlock) public onlyOwner {
        require(_tokenPerBlock > 0, 'Staking: amount of tokens per block should be greater than 0!');
        for (uint256 i=0; i<maxPid; i++) {
            updatePool(i);
        }
        tokenPerBlock = _tokenPerBlock;
        lastChangeTimestamp = block.timestamp;
        emit RewardChanged(tokenPerBlock);
    }

    function setStartBlock(uint256 _startBlock) public onlyOwner {
        require(startBlock == 0, 'Staking: start block already set');
        require(_startBlock > 0, 'Staking: start block needs to be higher than zero!');
        startBlock = _startBlock;
        emit StartBlockChanged(startBlock);
    }

    function setCloseBlock(uint256 _closeBlock) public onlyOwner {
        require(startBlock != 0, 'Staking: start block needs to be set first');
        require(closeBlock == 0, 'Staking: close block already set');
        require(_closeBlock > startBlock, 'Staking: close block needs to be higher than start one!');
        closeBlock = _closeBlock;
        emit CloseBlockChanged(closeBlock);
    }

    function withdrawRemaining() public onlyOwner {
        require(startBlock != 0, 'Staking: start block needs to be set first');
        require(closeBlock != 0, 'Staking: close block needs to be set first');
        require(block.number > closeBlock, 'Staking: withdrawal of remaining funds not ready yet');

        for (uint256 i=0; i<maxPid; i++) {
            updatePool(i);
        }

        uint256 allTokenRStaked = 0;
        uint256 allTokenAwarded = 0;
        uint256 allTokenClaimed = 0;

        for (uint256 i=0; i<maxPid; i++) {
            allTokenRStaked = allTokenRStaked.add(poolInfo[i].tokenRStaked);
            allTokenAwarded = allTokenAwarded.add(poolInfo[i].tokenAwarded);
            allTokenClaimed = allTokenClaimed.add(poolInfo[i].tokenClaimed);
        }

        uint256 reservedAmount = allTokenRStaked.add(allTokenAwarded).sub(allTokenClaimed);
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

    function stakingTokens(uint256 pid, address addr) external view returns (uint256) {
        if (pid >= maxPid) {
            return 0;
        }
        UserInfo storage user = userInfo[pid][addr];
        return user.amount;
    }

    function pendingRewards(uint256 pid, address addr) external view returns (uint256) {
        require(pid < maxPid, 'Staking: invalid pool ID provided');
        require(startBlock > 0 && block.number >= startBlock, 'Staking: not started yet');
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][addr];
        uint256 tokenPerShare = pool.tokenPerShare;
        uint256 lastMintedBlock = pool.lastRewardBlock;
        if (lastMintedBlock == 0) {
            lastMintedBlock = startBlock;
        }
        uint256 lastRewardBlock = getLastRewardBlock();
        if (lastRewardBlock == 0) {
            return 0;
        }
        uint256 poolTokenRStaked = pool.tokenRStaked;
        if (lastRewardBlock > lastMintedBlock && poolTokenRStaked != 0) {
            uint256 multiplier = lastRewardBlock.sub(lastMintedBlock);
            uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.poolShare).div(totalPoolShare);
            tokenPerShare = tokenPerShare.add(tokenReward.mul(1e12).div(poolTokenRStaked));
        }
        return user.amount.mul(tokenPerShare).div(1e12).sub(user.rewardDebt).add(user.pendingRewards);
    }

    function deposit(uint256 pid, uint256 amount) external {
        // amount eq to zero is allowed
        require(pid < maxPid, 'Staking: invalid pool ID provided');
        require(startBlock > 0 && block.number >= startBlock, 'Staking: not started yet');
        require(closeBlock == 0 || block.number <= closeBlock, 'Staking: farming has ended, please withdraw remaining tokens');

        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        require(pool.tokenLimited == 0
            || pool.tokenLimited >= pool.tokenRStaked.add(amount), 'Staking: you cannot deposit over the limit!');

        updatePool(pid);
        updatePendingRewards(pid, msg.sender);

        if (amount > 0) {
            user.amount = user.amount.add(amount);
            pool.tokenRStaked = pool.tokenRStaked.add(amount);
            token.safeTransferFrom(address(msg.sender), address(this), amount);
        }
        user.rewardDebt = user.amount.mul(pool.tokenPerShare).div(1e12);
        user.lockedTimestamp = block.timestamp.add(pool.lockupTimer);
        emit Deposit(msg.sender, pid, amount);
    }

    function withdraw(uint256 pid, uint256 amount) external {
        // amount eq to zero is allowed
        require(pid < maxPid, 'Staking: invalid pool ID provided');
        require(startBlock > 0 && block.number >= startBlock, 'Staking: not started yet');

        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        require((block.timestamp >= user.lockedTimestamp)
            || (closeBlock > 0 && closeBlock <= block.number)
            || (lastChangeTimestamp > 0 && lastChangeTimestamp.add(pool.lockupTimer) > user.lockedTimestamp),
            'Staking: you cannot withdraw yet!');
        require(user.amount >= amount, 'Staking: you cannot withdraw more than you have!');

        updatePool(pid);
        updatePendingRewards(pid, msg.sender);

        if (amount > 0) {
            user.amount = user.amount.sub(amount);
            pool.tokenRStaked = pool.tokenRStaked.sub(amount);
            token.safeTransfer(address(msg.sender), amount);
        }
        user.rewardDebt = user.amount.mul(pool.tokenPerShare).div(1e12);
        user.lockedTimestamp = 0;
        emit Withdraw(msg.sender, pid, amount);
    }

    function claim(uint256 pid) external {
        require(pid < maxPid, 'Staking: invalid pool ID provided');
        require(startBlock > 0 && block.number >= startBlock, 'Staking: not started yet');

        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        updatePool(pid);
        updatePendingRewards(pid, msg.sender);

        if (user.pendingRewards > 0) {
            uint256 claimedAmount = transferPendingRewards(pid, msg.sender, user.pendingRewards);
            emit Claim(msg.sender, pid, claimedAmount);
            user.pendingRewards = user.pendingRewards.sub(claimedAmount);
            pool.tokenClaimed = pool.tokenClaimed.add(claimedAmount);
        }
        user.rewardDebt = user.amount.mul(pool.tokenPerShare).div(1e12);
    }

    function addPool(uint256 _poolShare, uint256 _lockupTimer, uint256 _tokenLimited) internal {
        require(_poolShare > 0, 'Staking: Pool share needs to be higher than zero!');
        require(maxPid < 10, 'Staking: Cannot add more than 10 pools!');

        poolInfo.push(PoolInfo({
            poolShare: _poolShare,
            lastRewardBlock: 0,
            tokenPerShare: 0,
            tokenRStaked: 0,
            tokenClaimed: 0,
            tokenAwarded: 0,
            tokenLimited: _tokenLimited,
            lockupTimer: _lockupTimer
        }));
        totalPoolShare = totalPoolShare.add(_poolShare);
        maxPid = maxPid.add(1);
    }

    function updatePool(uint256 pid) internal {
        if (pid >= maxPid) {
            return;
        }
        if (startBlock == 0 || block.number < startBlock) {
            return;
        }
        PoolInfo storage pool = poolInfo[pid];
        if (pool.lastRewardBlock == 0) {
            pool.lastRewardBlock = startBlock;
        }
        uint256 lastBlock = getLastRewardBlock();
        if (lastBlock <= pool.lastRewardBlock) {
            return;
        }
        uint256 poolTokenRStaked = pool.tokenRStaked;
        if (poolTokenRStaked == 0) {
            return;
        }
        uint256 multiplier = lastBlock.sub(pool.lastRewardBlock);
        uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.poolShare).div(totalPoolShare);
        pool.tokenAwarded = pool.tokenAwarded.add(tokenReward);
        pool.tokenPerShare = pool.tokenPerShare.add(tokenReward.mul(1e12).div(poolTokenRStaked));
        pool.lastRewardBlock = lastBlock;
    }

    function updatePendingRewards(uint256 pid, address addr) internal {
        if (pid >= maxPid) {
            return;
        }
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][addr];
        uint256 pending = user.amount.mul(pool.tokenPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            user.pendingRewards = user.pendingRewards.add(pending);
        }
    }

    function transferPendingRewards(uint256 pid, address to, uint256 amount) internal returns (uint256) {
        if (pid >= maxPid) {
            return 0;
        }
        if (amount == 0) {
            return 0;
        }
        uint256 tokenAmount = token.balanceOf(address(this));
        if (tokenAmount == 0) {
            return 0;
        }
        if (tokenAmount > amount) {
            tokenAmount = amount;
        }
        token.safeTransfer(to, tokenAmount);
        return tokenAmount;
    }

    function getLastRewardBlock() internal view returns (uint256) {
        if (startBlock == 0) return 0;
        if (closeBlock == 0) return block.number;
        return (closeBlock < block.number) ? closeBlock : block.number;
    }
}
