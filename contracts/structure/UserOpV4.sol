// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

struct MemoryUserOp {
    address sender;
    uint256 nonce;
    uint256 callGasLimit;
    uint256 verificationGasLimit;
    uint256 preVerificationGas;
    address paymaster;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
}

struct UserOpInfo {
    MemoryUserOp mUserOp;
    bytes32 userOpHash;
    uint256 prefund;
    uint256 contextOffset;
    uint256 preOpGas;
}
