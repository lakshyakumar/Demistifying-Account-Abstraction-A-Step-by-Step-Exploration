// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./libraries/UserOperationV7.sol";
import "./interface/IEntryPoint_with_paymaster.sol";

contract VerifyingPaymasterV7 is Ownable {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;
    using UserOperationLib for UserOperation;

    address public immutable verifyingSigner;
    uint256 private constant VALID_TIMESTAMP_OFFSET = 20;

    uint256 private constant SIGNATURE_OFFSET = 84;
    mapping(address => uint256) public senderNonce;

    enum PostOpMode {
        opSucceeded, // user op succeeded
        opReverted, // user op reverted. still has to pay for gas.
        postOpReverted //user op succeeded, but caused postOp to revert. Now it's a 2nd call, after user's op was deliberately reverted.
    }
    IEntryPoint public immutable _entryPoint;

    constructor(
        IEntryPoint _entryPointValue,
        address _verifyingSigner
    ) Ownable(_verifyingSigner) {
        verifyingSigner = _verifyingSigner;
        _entryPoint = _entryPointValue;
    }

    function _requireFromEntryPoint() internal virtual {
        require(msg.sender == address(_entryPoint), "Sender not EntryPoint");
    }

    function entryPoint() public view virtual returns (IEntryPoint) {
        return _entryPoint;
    }

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

    function pack(
        UserOperation calldata userOp
    ) internal pure returns (bytes memory ret) {
        // lighter signature scheme. must match UserOp.ts#packUserOp
        bytes calldata pnd = userOp.paymasterAndData;
        // copy directly the userOp from calldata up to (but not including) the paymasterAndData.
        // this encoding depends on the ABI encoding of calldata, but is much lighter to copy
        // than referencing each field separately.
        assembly {
            let ofs := userOp
            let len := sub(sub(pnd.offset, ofs), 32)
            ret := mload(0x40)
            mstore(0x40, add(ret, add(len, 32)))
            mstore(ret, len)
            calldatacopy(add(ret, 32), ofs, len)
        }
    }

    function anotherPack(
        UserOperation calldata userOp
    ) internal pure returns (bytes memory ret) {
        address sender = userOp.sender;
        uint256 nonce = userOp.nonce;
        bytes32 hashCallData = calldataKeccak(userOp.callData);
        uint256 callGasLimit = userOp.callGasLimit;
        uint256 verificationGasLimit = userOp.verificationGasLimit;
        uint256 preVerificationGas = userOp.preVerificationGas;
        uint256 maxFeePerGas = userOp.maxFeePerGas;
        uint256 maxPriorityFeePerGas = userOp.maxPriorityFeePerGas;

        return
            abi.encode(
                sender,
                nonce,
                hashCallData,
                callGasLimit,
                verificationGasLimit,
                preVerificationGas,
                maxFeePerGas,
                maxPriorityFeePerGas
            );
    }

    function calldataKeccak(
        bytes calldata data
    ) internal pure returns (bytes32 ret) {
        assembly {
            let mem := mload(0x40)
            let len := data.length
            calldatacopy(mem, data.offset, len)
            ret := keccak256(mem, len)
        }
    }

    function _packValidationData(
        bool sigFailed,
        uint48 validUntil,
        uint48 validAfter
    ) public pure returns (uint256) {
        return
            (sigFailed ? 1 : 0) |
            (uint256(validUntil) << 160) |
            (uint256(validAfter) << (160 + 48));
    }

    function getHash(
        UserOperation calldata userOp,
        uint48 validUntil,
        uint48 validAfter
    ) public view returns (bytes32 hash) {
        //can't use userOp.hash(), since it contains also the paymasterAndData itself.
        hash = keccak256(
            abi.encode(
                anotherPack(userOp),
                block.chainid,
                address(this),
                senderNonce[userOp.getSender()],
                validUntil,
                validAfter
            )
        );
    }

    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external returns (bytes memory context, uint256 validationData) {
        (userOpHash);
        _requireFromEntryPoint();
        return _validatePaymasterUserOp(userOp, maxCost);
    }

    function _validatePaymasterUserOp(
        UserOperation calldata userOp,
        uint256 maxCost
    ) public returns (bytes memory context, uint256 validationData) {
        (
            uint48 validUntil,
            uint48 validAfter,
            bytes calldata signature
        ) = parsePaymasterAndData(userOp.paymasterAndData);
        //ECDSA library supports both 64 and 65-byte long signatures.
        // we only "require" it here so that the revert reason on invalid signature will be of "VerifyingPaymaster", and not "ECDSA"
        require(
            signature.length == 64 || signature.length == 65,
            "VerifyingPaymaster: invalid signature length in paymasterAndData"
        );
        bytes32 hash = getHash(userOp, validUntil, validAfter)
            .toEthSignedMessageHash();
        senderNonce[userOp.getSender()]++;
        //don't revert on signature failure: return SIG_VALIDATION_FAILED
        if (verifyingSigner != ECDSA.recover(hash, signature)) {
            return ("", _packValidationData(true, validUntil, validAfter));
        }
        _payPrefund(maxCost);
        //no need for other on-chain validation: entire UserOp should have been checked
        // by the external service prior to signing it.
        return ("", _packValidationData(false, validUntil, validAfter));
    }

    function parsePaymasterAndData(
        bytes calldata paymasterAndData
    )
        public
        pure
        returns (uint48 validUntil, uint48 validAfter, bytes calldata signature)
    {
        (validUntil, validAfter) = abi.decode(
            paymasterAndData[VALID_TIMESTAMP_OFFSET:SIGNATURE_OFFSET],
            (uint48, uint48)
        );
        signature = paymasterAndData[SIGNATURE_OFFSET:];
    }

    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) external {
        _requireFromEntryPoint();
        _postOp(mode, context, actualGasCost);
    }

    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) internal virtual {
        (mode, context, actualGasCost); // unused params
        // subclass must override this method if validatePaymasterUserOp returns a context
        revert("must override");
    }

    /**
     * check current account deposit in the entryPoint
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /**
     * deposit more funds for this account in the entryPoint
     */
    function addDeposit() public payable {
        entryPoint().depositTo{value: msg.value}(address(this));
    }

    function withdrawDepositTo(
        address payable withdrawAddress,
        uint256 amount
    ) public onlyOwner {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    receive() external payable {
        // React to receiving ether
    }
}
