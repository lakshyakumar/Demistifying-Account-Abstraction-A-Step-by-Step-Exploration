/**
 ** Account-Abstraction (EIP-4337) singleton EntryPoint implementation.
 ** Only one instance required on each chain.
 **/
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

contract StakeManager {
    /// maps paymaster to their deposits and stakes
    mapping(address => uint256) public deposits;

    /// return the deposit (for gas payment) of the account
    function balanceOf(address account) public view returns (uint256) {
        return deposits[account];
    }

    receive() external payable {
        uint256 newDeposit = deposits[msg.sender] + msg.value;
        deposits[msg.sender] = newDeposit;
    }

    /**
     * add to the deposit of the given account
     */
    function depositTo(address account) public payable {
        uint256 initBal = deposits[account];
        uint256 balance = initBal + uint256(msg.value);
        deposits[account] = balance;
    }

    function _incrementDeposit(address account, uint256 amount) internal {
        uint256 deposit = deposits[account];
        uint256 newAmount = deposit + amount;
        require(newAmount <= type(uint112).max, "deposit overflow");
        deposits[account] = newAmount;
    }
}
