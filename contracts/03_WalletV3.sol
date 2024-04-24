// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./libraries/UserOperationV3.sol";

contract WalletV3 is Ownable {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;
    using UserOperationLib for UserOperation;

    uint256 internal constant SIG_VALIDATION_FAILED = 1;

    constructor(address _admin) Ownable(_admin) {}

    function hashFunction(
        UserOperation calldata userOp
    ) public pure returns (bytes32) {
        return userOp.hash();
    }

    function _validateSignature(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) public view virtual returns (uint256 validationData) {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        if (owner() != hash.recover(userOp.signature))
            return SIG_VALIDATION_FAILED;
        return 0;
    }
    function execute(
        address dest,
        uint256 value,
        bytes calldata func
    ) external {
        _call(dest, value, func);
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
