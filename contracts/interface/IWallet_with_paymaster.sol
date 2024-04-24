// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../libraries/UserOperationV7.sol";
interface Wallet {
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData);

    function _payPrefund(uint256 missingAccountFunds) external;

    function validateSignatureAndSend(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256);

    function execute(address dest, uint256 value, bytes calldata func) external;
}
