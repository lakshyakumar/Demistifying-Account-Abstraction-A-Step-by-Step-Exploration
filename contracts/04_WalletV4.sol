// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./libraries/UserOperationV3.sol";
import "./interface/IEntryPoint.sol";

contract WalletV4 is Ownable {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;
    using UserOperationLib for UserOperation;

    IEntryPoint private immutable _entryPoint;

    uint256 internal constant SIG_VALIDATION_FAILED = 1;

    function _requireFromEntryPoint() internal view virtual {
        require(
            msg.sender == address(entryPoint()),
            "account: not from EntryPoint"
        );
    }

    // Require the function call went through EntryPoint or owner
    function _requireFromEntryPointOrOwner() internal view {
        require(
            msg.sender == address(entryPoint()) || msg.sender == owner(),
            "account: not Owner or EntryPoint"
        );
    }

    constructor(address _admin, IEntryPoint anEntryPoint) Ownable(_admin) {
        _entryPoint = anEntryPoint;
    }
    function entryPoint() public view virtual returns (IEntryPoint) {
        return _entryPoint;
    }

    function getNonce() public view virtual returns (uint256) {
        return entryPoint().getNonce(address(this), 0);
    }

    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    function addDeposit() public payable {
        entryPoint().depositTo{value: msg.value}(address(this));
    }

    function withdrawDepositTo(
        address payable withdrawAddress,
        uint256 amount
    ) public onlyOwner {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    function hashFunction(
        UserOperation calldata userOp
    ) public pure returns (bytes32) {
        return userOp.hash();
    }

    function _validateNonce(uint256 nonce) internal view virtual {}

    function _payPrefund(uint256 missingAccountFunds) public virtual {
        if (missingAccountFunds != 0) {
            (bool success, ) = payable(msg.sender).call{
                value: missingAccountFunds,
                gas: type(uint256).max
            }("");
            (success);
            //ignore failure (its EntryPoint's job to verify, not account.)
        }
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external virtual returns (uint256 validationData) {
        _requireFromEntryPoint();
        validationData = _validateSignature(userOp, userOpHash);
        _validateNonce(userOp.nonce);
        _payPrefund(missingAccountFunds);
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

    function validateSignatureAndSend(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData) {
        validationData = _validateSignature(userOp, userOpHash);
        _validateNonce(userOp.nonce);
        _payPrefund(missingAccountFunds);
    }

    function execute(
        address dest,
        uint256 value,
        bytes calldata func
    ) external {
        _requireFromEntryPointOrOwner();
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

    receive() external payable {
        // Handle received Ether
        // ...
    }
}
