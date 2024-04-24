// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

struct UserOperation {
    address target;
    uint256 value;
    bytes _calldata;
    bytes signature;
}

contract WalletV2 is Ownable {
    constructor(address _admin) Ownable(_admin) {}

    function getEthSignedMessageHash(
        bytes32 _hash
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", _hash)
            );
    }

    function getMessageHash(
        address _target,
        uint256 _value,
        bytes calldata _calldata
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(_target, _value, _calldata));
    }

    function splitSignature(
        bytes memory _signature
    ) internal pure returns (uint8, bytes32, bytes32) {
        require(_signature.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            // First 32 bytes stores the length of the signature
            // Add 32 to get the next memory slot where the signature starts
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            // The last byte of the signature contains the `v` parameter
            // (even=0, odd=1)
            v := byte(0, mload(add(_signature, 96)))
        }
        return (v, r, s);
    }

    function recoverSigner(
        bytes32 _message,
        bytes memory _signature
    ) internal pure returns (address) {
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = splitSignature(_signature);
        return ecrecover(_message, v, r, s);
    }

    function execute(UserOperation calldata op) external {
        bytes32 messageHash = getMessageHash(op.target, op.value, op._calldata);
        bytes32 prefixedMessageHash = getEthSignedMessageHash(messageHash);
        require(
            recoverSigner(prefixedMessageHash, op.signature) == owner(),
            "Invalid signature"
        );
        _call(op.target, op.value, op._calldata);
    }

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
