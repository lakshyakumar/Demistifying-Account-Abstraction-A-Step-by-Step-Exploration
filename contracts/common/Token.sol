// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Token
 * @dev An ERC20 token contract with an initial supply minted to the contract deployer.
 * @notice initialOwner The initial owner of the tokens.
 */
contract Token is ERC20, Ownable {
    /**
     * @dev Constructor function to initialize the token contract.
     * @param initialOwner The initial owner of the tokens.
     */
    constructor(
        address initialOwner
    ) ERC20("TestToken", "TTK") Ownable(initialOwner) {
        _mint(initialOwner, 5000 * (10 ** uint256(decimals())));
    }
}
