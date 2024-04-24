// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title WalletV1
 * @dev A smart contract wallet that allows the owner to execute transactions.
 * @notice _admin The initial owner of the contract.
 */
contract WalletV1 is Ownable {
    /**
     * @dev Constructor function to initialize the contract.
     * @param _admin The initial owner of the contract.
     */
    constructor(address _admin) Ownable(_admin) {}

    /**
     * @dev Execute a transaction from the smart contract wallet.
     * @param _target The address of the recipient.
     * @param _value The amount of ether (in wei) to send along with the call.
     * @param _calldata The data to be passed to the target contract.
     */
    function execute(
        address _target,
        uint256 _value,
        bytes calldata _calldata
    ) external onlyOwner {
        _call(_target, _value, _calldata);
    }

    /**
     * @dev Internal function to perform the low-level call to the target contract.
     * @param _target The address of the recipient.
     * @param value The amount of ether (in wei) to send along with the call.
     * @param _calldata The data to be passed to the target contract.
     */
    function _call(
        address _target,
        uint256 value,
        bytes memory _calldata
    ) internal {
        (bool success, bytes memory result) = _target.call{value: value}(
            _calldata
        );
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
