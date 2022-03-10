// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BIGPublicSale is Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  bool public isInit;
  ERC20 public BIG;


 // uint256 public constant PERIOD = 30 days;
  uint256 public constant CLIFF_DURATION = 30 days; // 1 month
  uint256 public VESTING_DURATION = 86400 * 30 * 4; // 4 months
  uint256 public BIG_PRICE =  50000000000000000; // 1 BIG = 0.05 USTD
  uint256 public TOTAL_ALLOCATION = 6000000000000000000000000; // 6.000.000 token REAL
  uint256 public TGE_RELEASE_LOCK_DURATION = 2 hours; // 2 hours
  uint256 public TGE_RELEASE_PERCENT = 20; // 20%
  
  uint256 public startTime;
  uint256 public endTime;
  uint256 public tgeTime;
  // address coldWallet;
  uint8 public stage;

  address[] private whilelists;
  mapping(address => uint256) private locks; // BIG
  mapping(address => uint256) private released; // BIG
  mapping(address => Purchase) public purchases; 

  event Claim(address indexed account, uint256 amount, uint256 time);

  constructor() {}
  
  struct Purchase {
    uint256 purchasedAmount;
    uint256 claimedAmount;
  }

  modifier canClaim() {
    require(stage == 1, "Can not claim now");
    _;
  }

  modifier canSetup() {
    require(stage == 0, "Can not setup now");
    _;
  }

  function initial(ERC20 _big) external onlyOwner {
    require(isInit != true, "Init before!");
    BIG = ERC20(_big);
    stage = 0;

    isInit = true;
  }
  function setTGETime(uint256 _tgeTime) external onlyOwner {
    tgeTime = _tgeTime;
  }

  function setTime(uint256 _time) external canSetup onlyOwner {
    startTime = _time + CLIFF_DURATION ;
    endTime = startTime + VESTING_DURATION;

    stage = 1;

    for (uint256 i = 0; i < whilelists.length; i++) {
      uint256 bigAmount = (locks[whilelists[i]] * TGE_RELEASE_PERCENT) / 1000;
      locks[whilelists[i]] -= bigAmount;
      BIG.transfer(whilelists[i], bigAmount);
    }
  }

  function addWhitelist(address[] calldata _users, uint256[] calldata _balance)
    external
    canSetup
    onlyOwner
  {
    require(_users.length == _balance.length, "Invalid input");
    for (uint256 i = 0; i < _users.length; i++) {
      //calculate
      uint256 bigAmount = (_balance[i] * 10**18) / BIG_PRICE;
      locks[_users[i]] += bigAmount;
      whilelists.push(_users[i]);
    }
  }

  function setBalanceUser(address _user, uint256 _newBalance)
    external
    onlyOwner
  {
    require(locks[_user] > 0, "This new user");
    uint256 bigAmount = (_newBalance * 10**18) / BIG_PRICE;
    locks[_user] = bigAmount;
  }

  function claim() external canClaim nonReentrant {
    require(tgeTime > 0, "BIGPublicSale: CANNOT_CLAIM_NOW");
    require(block.timestamp > startTime, "still locked");
    require(locks[_msgSender()] > released[_msgSender()], "no locked");

    uint256 amount = canUnlockAmount(_msgSender());
    require(amount > 0, "BIGPublicSale: NO_AVAILABLE_CLAIM");

    released[_msgSender()] += amount;
    purchases[_msgSender()].claimedAmount = purchases[_msgSender()]
            .claimedAmount
            .add(amount);
            
    BIG.transfer(_msgSender(), amount);

    emit Claim(_msgSender(), amount, block.timestamp);
  }
// timeline
    // TGE time -------------------------> TGE release ----------------------> After cliff (start vesting) --------------> 1st vesting --------------> 2nd vesting --------------> ...
    // ------------|TGE lock duration|--------------------|Cliff duration|------------------------------------|Period|-------------------|Period|--------------------|Period|---- ...
  function canUnlockAmount(address purchaser) public view returns (uint256) {
    uint256 tgeReleaseTime = tgeTime.add(TGE_RELEASE_LOCK_DURATION);
    if (block.timestamp < tgeReleaseTime) {
      return 0;
    }
    uint256 releasedTime = releasedTimes();
    Purchase memory purchase = purchases[purchaser]; // gas saving

    uint256 tgeReleaseAmount = purchase
          .purchasedAmount
          .mul(TGE_RELEASE_PERCENT)
          .div(100);

  // by the time after cliff duration from TGE release time, i.e. right before vesting time
    uint256 cliffTime = tgeReleaseTime.add(CLIFF_DURATION);
    if (block.timestamp <= cliffTime) {
        return tgeReleaseAmount - purchase.claimedAmount;
    }

  // begin vesting time
    uint256 totalClaimAmount = tgeReleaseAmount;
    uint256 nPeriods = uint256(block.timestamp).sub(cliffTime).div(CLIFF_DURATION);

    uint256 periodicVestingAmount = purchase
        .purchasedAmount
        .sub(tgeReleaseAmount)
        .div(VESTING_DURATION);

    uint256 toDateVestingAmount = nPeriods.mul(periodicVestingAmount);

    totalClaimAmount = totalClaimAmount.add(toDateVestingAmount);
    if (totalClaimAmount > purchase.purchasedAmount)
        totalClaimAmount = purchase.purchasedAmount;

    return totalClaimAmount - purchase.claimedAmount;
  }

  function releasedTimes() public view returns (uint256) {
      uint256 targetNow = (block.timestamp >= endTime)
          ? endTime
          : block.timestamp;
      uint256 releasedTime = targetNow - startTime;
      return releasedTime;
  }

  function info()
    external
    view
    returns (
      uint8,
      uint256,
      uint256
    )
  {
    return (stage, startTime, endTime);
  }

  //For FE
  function infoWallet(address _user)
    external
    view
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    if (stage == 0) return (locks[_user], released[_user], 0);
    return (locks[_user], released[_user], canUnlockAmount(_user));
  }

  /* ========== EMERGENCY ========== */
  function governanceRecoverUnsupported(
    address _token,
    address _to,
    uint256 _amount
  ) external onlyOwner {
    // require(_token != address(BIG), "Token invalid");
    ERC20(_token).transfer(_to, _amount);
  }
}
