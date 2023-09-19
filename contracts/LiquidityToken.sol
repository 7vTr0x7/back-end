// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;



contract LiquidityToken {
    mapping(address => uint256) private balances;
    uint256 private totalSupply_;

    function _mint(address account, uint256 amount) internal   {
        totalSupply_ += amount;
        balances[account] += amount;
    }

    function _burn(address account, uint256 amount) internal   {
        require(balances[account] >= amount, "Insufficient balance");
        totalSupply_ -= amount;
        balances[account] -= amount;
    }

    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }

    function totalSupply() public view returns (uint256) {
        return totalSupply_;
    }

    // Other functions and code...

}
