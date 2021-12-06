// SPDX-License-Identifier: MIT

pragma solidity =0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract PresaleStaged is Ownable {
    using Address for address;
    using SafeMath for uint256;

    uint256 public minAmount;
    uint256 public maxAmount;
    uint256 public bnbPrice;
    bool public wasStarted;
    bool public wasStopped;
    uint256 public startedTimestamp;
    uint256 public stoppedTimestamp;

    struct PresaleStage {
        uint256 tokensUSDMaxLimit; // USD needs to be represented with 1e-18 prec!
        uint256 tokensBNBMaxLimit;
        uint256 tokensBNBAcquired;
    }

    uint256 public totalAllocated;
    mapping(address => uint256) public allocations;

    PresaleStage[] public stages;
    uint256 public curStage;
    uint256 public maxStage;

    event SaleStarted();
    event SaleStopped();
    event Allocated(address indexed addr, uint256 alloc, uint256 stage);
    event Withdrawn(uint256 amount);
    event PriceChanged(uint256 price);
    event StageAdded(uint256 usdMaxLimit);

    function startSale(uint256 _minAmount, uint256 _maxAmount) external onlyOwner {
        require(!wasStarted, 'PresaleStaged: Sale was already started');
        require(_minAmount > 0, 'PresaleStaged: Min allocation needs to be larger than 0');
        require(_maxAmount > 0, 'PresaleStaged: Max allocation needs to be larger than 0');
        require(_maxAmount > _minAmount, 'PresaleStaged: Min allocation cannot be larger than max allocation');
        require(bnbPrice > 0, 'PresaleStaged: BNB price needs to be set first');
        require(curStage < maxStage, 'PresaleStaged: Stages need to be set first');

        minAmount = _minAmount;
        maxAmount = _maxAmount;

        startedTimestamp = block.timestamp;
        wasStarted = true;

        emit SaleStarted();
    }

    function closeSale() external onlyOwner {
        require(wasStarted, 'PresaleStaged: Sale was not started yet');
        require(!wasStopped, 'PresaleStaged: Sale was already closed');

        stoppedTimestamp = block.timestamp;
        wasStopped = true;

        emit SaleStopped();
    }

    function setNativePrice(uint256 price) external onlyOwner {
        require(price > 0, 'PresaleStaged: BNB price needs to be larger than 0');
        bnbPrice = price;
        emit PriceChanged(bnbPrice);
    }

    function addStagesArray(uint256[] memory limits) external onlyOwner {
        require(limits.length > 0, 'PresaleStaged: Limit array must be larger than 0 elements');

        for (uint256 i = 0; i < limits.length; ++i) {
            require(limits[i] > 0, 'PresaleStaged: Limit needs to be larger than 0');
        }
        for (uint256 i = 0; i < limits.length; ++i) {
            stages.push(PresaleStage({
                tokensUSDMaxLimit: limits[i],
                tokensBNBMaxLimit: 0,
                tokensBNBAcquired: 0
            }));
            emit StageAdded(limits[i]);
        }
        maxStage = maxStage.add(limits.length);
    }

    function allocate() external payable {
        require(wasStarted, 'PresaleStaged: Cannot allocate yet');
        require(!wasStopped, 'PresaleStaged: Cannot allocate anymore');
        require(msg.value != 0, 'PresaleStaged: Allocation value cannot be 0');
        require(msg.value >= minAmount, 'PresaleStaged: Allocation is too small');
        require(allocations[msg.sender].add(msg.value) <= maxAmount, 'PresaleStaged: Allocation is too large');

        totalAllocated = totalAllocated.add(msg.value);
        allocations[msg.sender] = allocations[msg.sender].add(msg.value);

        allocateInStage(msg.sender, msg.value);
    }

    function withdraw() external onlyOwner {
        uint256 currentBalance = address(this).balance;
        Address.sendValue(payable(owner()), currentBalance);
        emit Withdrawn(currentBalance);
    }

    function allocation(address addr) public view returns (uint256) {
        return allocations[addr];
    }

    function allocateInStage(address addr, uint256 amount) internal {
        require(curStage < maxStage, 'PresaleStaged: Allocation goes over max target');

        PresaleStage storage stage = stages[curStage];
        if (stage.tokensBNBMaxLimit == 0) {
            stage.tokensBNBMaxLimit = stage.tokensUSDMaxLimit.mul(1e18).div(bnbPrice);
        }

        uint256 currAmount = amount;
        uint256 freeAmount = stage.tokensBNBMaxLimit.sub(stage.tokensBNBAcquired);
        if (amount > freeAmount) {
            currAmount = freeAmount;
        }

        stage.tokensBNBAcquired = stage.tokensBNBAcquired.add(currAmount);
        emit Allocated(addr, currAmount, curStage);

        if (amount > freeAmount) {
            curStage = curStage.add(1);
            allocateInStage(addr, amount.sub(freeAmount));
        }
    }
}
