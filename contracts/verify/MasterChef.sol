

pragma solidity 0.6.12;

import "./IBEP20.sol";
import "./SafeBEP20.sol";
import "./EnumerableSet.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./LibToken.sol";
interface IUniswapRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);

    function swapExactTokensForTokens(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
}
interface IMigratorChef {
    // Perform LP token migration from legacy UniswapV2 to libreSwap.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.
    //
    // XXX Migrator must have allowance access to UniswapV2 LP tokens.
    // libreSwap must mint EXACTLY the same amount of libreSwap LP tokens or
    // else something bad will happen. Traditional UniswapV2 does not
    // do that so be careful!
    function migrate(IBEP20 token) external returns (IBEP20);
}
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of SUSHIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSushiPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accSushiPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. SUSHIs to distribute per block.
        uint256 lastRewardBlock; // Last block number that SUSHIs distribution occurs.
        address[] lpPath;
        uint256 accLibPerShare; // Accumulated LIBs per share, times 1e12. See below.
        bool isLibrePair; // non-Libre LP will be charged 5% fee on withdraw
    }
    // The LIB TOKEN!
    LibToken public lib;
    // Dev address.
    address public devaddr;
    // Lib tokens created per block.
    uint256 public libPerBlock = 1*10**18;
    // Lib tokens burn per block.
    // uint256 public burnPerBlock = 3*10**18;
    IMigratorChef public migrator;
    IUniswapRouter uniRouter;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when SUSHI mining starts.
    uint256 public startBlock;
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        address[]memory _lib,
        address _devaddr,
        address _uniRouter,
        uint256 _startBlock
    ) public {
        lib = LibToken(_lib[0]);
        uniRouter = IUniswapRouter(_uniRouter);
        devaddr = _devaddr;
        startBlock = _startBlock;
        poolInfo.push(
            PoolInfo({
                lpToken: lib,
                allocPoint: 10,
                lpPath:_lib,
                lastRewardBlock: 0,
                accLibPerShare: 0,
                isLibrePair: true
            })
        );
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IBEP20 _lpToken,
        address[] memory _lpPath,
        bool _withUpdate,
        bool _isLibrePair
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
            block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        IBEP20 token0 = IBEP20(_lpPath[0]);
        IBEP20 token1 = IBEP20(_lpPath[1]);
        
        token0.approve(address(uniRouter),10**64);
        token1.approve(address(uniRouter),10**64);

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lpPath:_lpPath,
                lastRewardBlock: lastRewardBlock,
                accLibPerShare: 0,
                isLibrePair: _isLibrePair
            })
        );
    }
    
    // Update the given pool's allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IBEP20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IBEP20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256){
        return _to.sub(_from);
    }

    // View function to see pending SUSHIs on frontend.
    function pendingLib(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accLibPerShare = pool.accLibPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 libReward =  multiplier.mul(libPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accLibPerShare = accLibPerShare.add(
                libReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accLibPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 libReward =
            multiplier.mul(libPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );

        //maximim mint amout = 80000000 * 10**18
        lib.mint(address(this),libReward);
        pool.accLibPerShare = pool.accLibPerShare.add(
            libReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }
    function stake(uint256 _amount) public{
        lib.transferFrom(msg.sender, address(this), _amount);
        
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accLibPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            uint256 fee = pending.mul(2).div(100);

            safeLibreTransfer(msg.sender, pending.sub(fee));
            safeLibreTransfer(devaddr, fee);
        }
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accLibPerShare).div(1e12);
        emit Deposit(msg.sender, 0, _amount);
    }
    function unstake(uint256 _amount)public{
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending =
            user.amount.mul(pool.accLibPerShare).div(1e12).sub(
                user.rewardDebt
            );
        uint256 fee = pending.mul(2).div(100);

        // if(!pool.isLibrePair){// burn 5% of Libre reward
        //     lib.burn(address(this),pending.mul(5).div(100));
        //     pending = pending.mul(95).div(100);
        // }
        user.amount = user.amount.sub(_amount);
        safeLibreTransfer(msg.sender, pending.sub(fee));
        safeLibreTransfer(devaddr, fee);
        user.rewardDebt = user.amount.mul(pool.accLibPerShare).div(1e12);
        // pool.lpToken.safeTransfer(address(msg.sender), _amount);
        safeLibreTransfer(address(msg.sender),_amount);
        emit Withdraw(msg.sender, 0, _amount);
    }
    // Deposit LP tokens to MasterChef for SUSHI allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        require(_pid>0,"pool 0 is for staking");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accLibPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            uint256 fee = pending.mul(2).div(100);

            safeLibreTransfer(msg.sender, pending.sub(fee));
            safeLibreTransfer(devaddr, fee);
        }
        IBEP20 token0 = IBEP20(pool.lpPath[0]);
        IBEP20 token1 = IBEP20(pool.lpPath[1]);
        uint256 lpBefore = pool.lpToken.balanceOf(address(this));
        token0.transferFrom(msg.sender, address(this), _amount);

        uint256 token0Before = token0.balanceOf(address(this));
        uint256 token1Before = token1.balanceOf(address(this));
        uniRouter.swapExactTokensForTokens(_amount.div(2), 0, pool.lpPath, address(this), block.timestamp);
        uint256 token0Amount = token0Before.sub(token0.balanceOf(address(this))); 
        uint256 token1Amount = token1.balanceOf(address(this)).sub(token1Before);
        uniRouter.addLiquidity(address(token0), address(token1), token0Amount, token1Amount, 0 , 0, address(this), block.timestamp);

        uint256 lpAmount = pool.lpToken.balanceOf(address(this)).sub(lpBefore);

        uint256 fee = lpAmount.mul(2).div(100);
        lpAmount = lpAmount.sub(fee);
        pool.lpToken.transfer(devaddr,fee);
        user.amount = user.amount.add(lpAmount);
        user.rewardDebt = user.amount.mul(pool.accLibPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }
 
    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        require(_pid>0,"pool 0 is for staking");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        IBEP20 token0 = IBEP20(pool.lpPath[0]);
        IBEP20 token1 = IBEP20(pool.lpPath[1]);

        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending =
            user.amount.mul(pool.accLibPerShare).div(1e12).sub(
                user.rewardDebt
            );
        uint256 fee = pending.mul(2).div(100);
        uint256 token0Before = token0.balanceOf(address(this));
        uint256 token1Before = token1.balanceOf(address(this));
        uniRouter.removeLiquidity(address(token0), address(token1), _amount, 0 , 0, address(this), block.timestamp);
        uint256 token0Amount = token0.balanceOf(address(this)).sub(token0Before);
        uint256 token1Amount = token1.balanceOf(address(this)).sub(token1Before);

        // if(!pool.isLibrePair){// burn 5% of Libre reward
        //     lib.burn(address(this),pending.mul(5).div(100));
        //     pending = pending.mul(95).div(100);
        // }
        user.amount = user.amount.sub(_amount);
        safeLibreTransfer(msg.sender, pending.sub(fee));
        safeLibreTransfer(devaddr, fee);
        user.rewardDebt = user.amount.mul(pool.accLibPerShare).div(1e12);
        // pool.lpToken.safeTransfer(address(msg.sender), _amount);
        token0.safeTransfer(address(msg.sender),token0Amount);
        token1.safeTransfer(address(msg.sender),token1Amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
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