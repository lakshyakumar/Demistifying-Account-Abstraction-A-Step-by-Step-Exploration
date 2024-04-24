// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../libraries/UserOperationV3.sol";
interface IEntryPoint {
    function handleOps(
        UserOperation[] calldata ops,
        address payable beneficiary
    ) external;

    function getUserOpHash(
        UserOperation calldata userOp
    ) external view returns (bytes32);

    function getNonce(
        address sender,
        uint192 key
    ) external view returns (uint256 nonce);

    function validateNonce(
        uint192 key,
        uint256
    ) external view returns (uint256 nonce);

    function incrementNonce(uint192 key) external;

    function balanceOf(address account) external view returns (uint256);

    function depositTo(address account) external payable;

    function withdrawTo(
        address payable withdrawAddress,
        uint256 withdrawAmount
    ) external;
}
