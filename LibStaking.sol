
pragma solidity 0.6.12;

import "./token/BEP20/IBEP20.sol";
import "./token/BEP20/SafeBEP20.sol";
import "./utils/EnumerableSet.sol";
import "./math/SafeMath.sol";
import "./access/Ownable.sol";
import "./LibToken.sol";

contract LibStaking is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many Lib tokens the user has provided.
        uint256 rewardDebt; 
    }
    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 lastRewardBlock; // Last block number that SUSHIs distribution occurs.
        uint256 accLibPerShare; // Accumulated LIBs per share, times 1e12. See below.
        uint256 lpSupply;
    }
    PoolInfo public pool;
    LibToken public lib;
    address public devaddr;
    uint256 public libPerBlock;//= 10*10**18;
    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;
    uint256 public startBlock;
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 amount
    );
    constructor(
        LibToken _lib,
        address _devaddr,
        uint256 _startBlock
    ) public {
        lib = _lib;
        devaddr = _devaddr;
        startBlock = _startBlock;
        pool =  PoolInfo({
                lpToken: _lib,
                lastRewardBlock: _startBlock,
                accLibPerShare: 0,
                lpSupply: 0
            });
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256){
        return _to.sub(_from);
    }

    // View function to see pending SUSHIs on frontend.
    function pendingLib(address _user)
        external
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[_user];
        uint256 accLibPerShare = pool.accLibPerShare;
        uint256 lpSupply = pool.lpSupply;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 libReward =  multiplier.mul(libPerBlock);
            accLibPerShare = accLibPerShare.add(
                libReward.mul(1e18).div(lpSupply)
            );
        }
        return user.amount.mul(accLibPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public {
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        pool.lpSupply = pool.lpToken.balanceOf(address(this));
        if (pool.lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 libReward =
            multiplier.mul(libPerBlock);

        lib.mint(address(this),libReward);
        pool.accLibPerShare = pool.accLibPerShare.add(
            libReward.mul(1e18).div(pool.lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for SUSHI allocation.
    function deposit( uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        pool.lpToken.transferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accLibPerShare).div(1e18);
        pool.lpSupply = pool.lpToken.balanceOf(address(this));

        emit Deposit(msg.sender, _amount);
    }
 
    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool();
        uint256 pending =
            user.amount.mul(pool.accLibPerShare).div(1e18).sub(
                user.rewardDebt
            );
        user.amount = user.amount.sub(_amount);
        safeLibreTransfer(msg.sender, pending);
        user.rewardDebt = user.amount.mul(pool.accLibPerShare).div(1e18);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        pool.lpSupply = pool.lpToken.balanceOf(address(this));
        emit Withdraw(msg.sender, _amount);
    }

    // Safe sushi transfer function, just in case if rounding error causes pool to not have enough Libres.
    function safeLibreTransfer(address _to, uint256 _amount) internal {
        uint256 libBal = lib.balanceOf(address(this));
        if (_amount > libBal) {
            lib.transfer(_to, libBal);
        } else {
            lib.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}