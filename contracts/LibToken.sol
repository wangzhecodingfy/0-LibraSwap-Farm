pragma solidity 0.6.12;

import "./token/BEP20/BEP20Limited.sol";
import './math/SafeMath.sol';

contract LibToken is BEP20Limited('Libra', 'LIB', 100000000*10**18) {
    using SafeMath for uint256;
    
    event Burn(address indexed to, uint amount);
    event MintReward(uint reward_left);
    event BurnReward(uint amount_brun);
    
    uint256 total_reward = 80000000*10**18; // 80 million Farming rewards
    uint256 reward_per_block = 10*10**18;
    uint256 burn_per_block = 3*10**18;
    constructor() public{
        _mint(tx.origin, _maximumSupply.sub(total_reward));
    }
    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner.
    // function mint(address _to, uint256 _amount) public onlyOwner {
    //     require(_totalSupply.add(_amount)<=_maximumSupply.sub(80000000*10**18));
    //     _mint(_to, _amount);
    //     emit Mint(_to, _amount);
    // }
/// @notice Destroys `_amount` token to `_to`. , reducing the total supply.
    function burn(address _to, uint256 _amount) public onlyOwner {
        _burn(_to, _amount);
        emit Burn(_to, _amount);
    } 
    function mintReward() public onlyChef {
        require(total_reward.sub(reward_per_block) > 0);
        total_reward=total_reward.sub(reward_per_block);
        _mint(msg.sender, reward_per_block);
        _burn(msg.sender, burn_per_block);
        emit MintReward(total_reward);
    }
    function burnReward(uint256 _amount) external onlyChef { //burn 5% of LIB reward to non-Libra pair
        _burn(msg.sender, _amount);
        emit BurnReward(_amount);
    }

}