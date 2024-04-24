// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./libraries/UserOperationV3.sol";
import "./common/NonceManager.sol";
import "./common/StakeManager.sol";
import "./interface/IWallet.sol";
import "./structure/UserOpV4.sol";

contract EntryPointV6 is NonceManager, StakeManager, ReentrancyGuard {
    uint256 public constant SIG_VALIDATION_FAILED = 1;
    bytes32 private constant INNER_OUT_OF_GAS = hex"deaddead";
    uint256 private constant REVERT_REASON_MAX_LEN = 2048;

    using UserOperationLib for UserOperation;

    error FailedOp(uint256 opIndex, string reason);

    error ExecutionResult(
        uint256 preOpGas,
        uint256 paid,
        uint48 validAfter,
        uint48 validUntil,
        bool targetSuccess,
        bytes targetResult
    );

    event UserOperationRevertReason(
        bytes32 indexed userOpHash,
        address indexed sender,
        uint256 nonce,
        bytes revertReason
    );

    event UserOperationEvent(
        bytes32 indexed userOpHash,
        address indexed sender,
        address indexed paymaster,
        uint256 nonce,
        bool success,
        uint256 actualGasCost,
        uint256 actualGasUsed
    );

    function validateNonce(
        uint192 key,
        uint256 _nonce
    ) public view returns (bool) {
        uint256 nonce = nonceSequenceNumber[msg.sender][key];
        require(nonce == _nonce, "Nonce Not valid");
        return true;
    }

    function getReturnData(
        uint256 maxLen
    ) internal pure returns (bytes memory returnData) {
        assembly {
            let len := returndatasize()
            if gt(len, maxLen) {
                len := maxLen
            }
            let ptr := mload(0x40)
            mstore(0x40, add(ptr, add(len, 0x20)))
            mstore(ptr, len)
            returndatacopy(add(ptr, 0x20), 0, len)
            returnData := ptr
        }
    }

    function _validateSender(address sender) external view {
        if (sender.code.length == 0) {
            revert("AA20 account not deployed");
        }
    }

    function _simulateOnlyValidation(
        UserOperation calldata userOp
    ) internal view {
        try this._validateSender(userOp.sender) {} catch Error(
            string memory revertReason
        ) {
            if (bytes(revertReason).length != 0) {
                revert FailedOp(0, revertReason);
            }
        }
    }

    function _parseValidationData(
        uint256 validationData
    ) public pure returns (uint48 validUntil, uint48 validAfter) {
        validUntil = uint48(validationData >> 160);
        if (validUntil == 0) {
            validUntil = type(uint48).max;
        }
        validAfter = uint48(validationData >> (48 + 160));
    }

    function _intersectTimeRange(
        uint256 validationData
    ) public pure returns (uint48 validAfter, uint48 validUntil) {
        (validUntil, validAfter) = _parseValidationData(validationData);
    }

    function simulateHandleOp(
        UserOperation calldata op,
        address target,
        bytes calldata targetCallData
    ) external {
        UserOpInfo memory opInfo;
        _simulateOnlyValidation(op);
        uint256 validationData = _validatePrepayment(op, opInfo);
        (uint48 validAfter, uint48 validUntil) = _intersectTimeRange(
            validationData
        );

        numberMarker();
        uint256 paid = _executeUserOp(op, opInfo);
        numberMarker();
        bool targetSuccess;
        bytes memory targetResult;
        if (target != address(0)) {
            (targetSuccess, targetResult) = target.call(targetCallData);
        }
        revert ExecutionResult(
            opInfo.preOpGas,
            paid,
            validAfter,
            validUntil,
            targetSuccess,
            targetResult
        );
    }

    function getOffsetOfMemoryBytes(
        bytes memory data
    ) internal pure returns (uint256 offset) {
        assembly {
            offset := data
        }
    }
    function _compensate(address payable beneficiary, uint256 amount) internal {
        require(beneficiary != address(0), "AA90 invalid beneficiary");
        (bool success, ) = beneficiary.call{value: amount}("");
        require(success, "AA91 failed send to beneficiary");
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function getUserOpGasPrice(
        MemoryUserOp memory mUserOp
    ) internal view returns (uint256) {
        unchecked {
            uint256 maxFeePerGas = mUserOp.maxFeePerGas;
            uint256 maxPriorityFeePerGas = mUserOp.maxPriorityFeePerGas;
            if (maxFeePerGas == maxPriorityFeePerGas) {
                //legacy mode (for networks that don't support basefee opcode)
                return maxFeePerGas;
            }
            return min(maxFeePerGas, maxPriorityFeePerGas + block.basefee);
        }
    }

    function _handlePostOp(
        UserOpInfo memory opInfo,
        uint256 actualGas
    ) private returns (uint256 actualGasCost) {
        uint256 preGas = gasleft();
        address refundAddress;
        MemoryUserOp memory mUserOp = opInfo.mUserOp;
        uint256 gasPrice = getUserOpGasPrice(mUserOp);
        refundAddress = mUserOp.sender;
        actualGas += preGas - gasleft();
        actualGasCost = actualGas * gasPrice;
        if (opInfo.prefund < actualGasCost) {
            revert FailedOp(0, "AA51 prefund below actualGasCost");
        }
        uint256 refund = opInfo.prefund - actualGasCost;
        _incrementDeposit(refundAddress, refund);
        emit UserOperationEvent(
            opInfo.userOpHash,
            mUserOp.sender,
            mUserOp.paymaster,
            mUserOp.nonce,
            true,
            actualGasCost,
            actualGas
        );
    }

    function innerHandleOp(
        bytes memory callData,
        UserOpInfo memory opInfo
    ) external returns (uint256 actualGasCost) {
        uint256 preGas = gasleft();
        require(msg.sender == address(this), "AA92 internal call only");
        MemoryUserOp memory mUserOp = opInfo.mUserOp;
        uint callGasLimit = mUserOp.callGasLimit;

        unchecked {
            // handleOps was called with gas limit too low. abort entire bundle.
            if (
                gasleft() < callGasLimit + mUserOp.verificationGasLimit + 5000
            ) {
                assembly {
                    mstore(0, INNER_OUT_OF_GAS)
                    revert(0, 32)
                }
            }
        }
        if (callData.length > 0) {
            bool success = call(mUserOp.sender, 0, callData, callGasLimit);
            if (!success) {
                bytes memory result = getReturnData(REVERT_REASON_MAX_LEN);
                if (result.length > 0) {
                    emit UserOperationRevertReason(
                        opInfo.userOpHash,
                        mUserOp.sender,
                        mUserOp.nonce,
                        result
                    );
                }
            }
        }
        unchecked {
            uint256 actualGas = preGas - gasleft() + opInfo.preOpGas;
            //note: opIndex is ignored (relevant only if mode==postOpReverted, which is only possible outside of innerHandleOp)
            return _handlePostOp(opInfo, actualGas);
        }
    }

    function _executeUserOp(
        UserOperation calldata userOp,
        UserOpInfo memory opInfo
    ) private returns (uint256 collected) {
        uint256 preGas = gasleft();
        try this.innerHandleOp(userOp.callData, opInfo) returns (
            uint256 _actualGasCost
        ) {
            collected = _actualGasCost;
        } catch {
            bytes32 innerRevertCode;
            assembly {
                returndatacopy(0, 0, 32)
                innerRevertCode := mload(0)
            }
            // handleOps was called with gas limit too low. abort entire bundle.
            if (innerRevertCode == INNER_OUT_OF_GAS) {
                //report paymaster, since if it is not deliberately caused by the bundler,
                // it must be a revert caused by paymaster.
                revert FailedOp(0, "AA95 out of gas");
            }

            uint256 actualGas = preGas - gasleft() + opInfo.preOpGas;
            collected = _handlePostOp(opInfo, actualGas);
        }
    }

    function handleOps(
        UserOperation calldata ops,
        address payable beneficiary
    ) external nonReentrant {
        uint256 preGas = gasleft();
        UserOpInfo memory opInfo;
        uint256 validationData = _validatePrepayment(ops, opInfo);
        uint256 collected = _executeUserOp(ops, opInfo);
        uint256 actualGas = preGas - gasleft();
        _compensate(beneficiary, collected);
    }

    function call(
        address to,
        uint256 value,
        bytes memory data,
        uint256 txGas
    ) internal returns (bool success) {
        assembly {
            success := call(
                txGas,
                to,
                value,
                add(data, 0x20),
                mload(data),
                0,
                0
            )
        }
    }

    function _copyUserOpToMemory(
        UserOperation calldata userOp,
        MemoryUserOp memory mUserOp
    ) internal pure {
        mUserOp.sender = userOp.sender;
        mUserOp.nonce = userOp.nonce;
        mUserOp.callGasLimit = userOp.callGasLimit;
        mUserOp.verificationGasLimit = userOp.verificationGasLimit;
        mUserOp.preVerificationGas = userOp.preVerificationGas;
        mUserOp.maxFeePerGas = userOp.maxFeePerGas;
        mUserOp.maxPriorityFeePerGas = userOp.maxPriorityFeePerGas;
    }

    function getUserOpHash(
        UserOperation calldata userOp
    ) public view returns (bytes32) {
        return
            keccak256(abi.encode(userOp.hash(), address(this), block.chainid));
    }

    function _getRequiredPrefund(
        MemoryUserOp memory mUserOp
    ) internal pure returns (uint256 requiredPrefund) {
        unchecked {
            //when using a Paymaster, the verificationGasLimit is used also to as a limit for the postOp call.
            // our security model might call postOp eventually twice
            uint256 mul = mUserOp.paymaster != address(0) ? 3 : 1;
            uint256 requiredGas = mUserOp.callGasLimit +
                mUserOp.verificationGasLimit *
                mul +
                mUserOp.preVerificationGas;

            requiredPrefund = requiredGas * mUserOp.maxFeePerGas;
        }
    }

    function numberMarker() internal view {
        assembly {
            mstore(0, number())
        }
    }

    function callWalletsPayPrefund(address _wallet) public {
        Wallet(_wallet)._payPrefund(4200000000);
    }

    function _validateAccountPrepayment(
        UserOperation calldata op,
        UserOpInfo memory opInfo,
        uint256 requiredPrefund
    )
        internal
        returns (
            uint256 gasUsedByValidateAccountPrepayment,
            uint256 validationData
        )
    {
        unchecked {
            uint256 preGas = gasleft();
            MemoryUserOp memory mUserOp = opInfo.mUserOp;
            address sender = mUserOp.sender;
            numberMarker();
            uint256 missingAccountFunds = 0;
            uint256 bal = balanceOf(sender);
            missingAccountFunds = bal > requiredPrefund
                ? 0
                : requiredPrefund - bal;
            try
                Wallet(sender).validateUserOp{
                    gas: mUserOp.verificationGasLimit
                }(op, opInfo.userOpHash, missingAccountFunds)
            returns (uint256 _validationData) {
                validationData = _validationData;
            } catch Error(string memory revertReason) {
                revert FailedOp(
                    0,
                    string.concat("AA23 reverted: ", revertReason)
                );
            } catch {
                revert FailedOp(0, "AA23 reverted (or OOG)");
            }
            uint256 deposit = deposits[sender];
            if (requiredPrefund > deposit) {
                revert FailedOp(0, "AA21 didn't pay prefund");
            }
            deposits[sender] = uint112(deposit - requiredPrefund);
            gasUsedByValidateAccountPrepayment = preGas - gasleft();
        }
    }

    function _validatePrepayment(
        UserOperation calldata userOp,
        UserOpInfo memory outOpInfo
    ) public returns (uint256 validationData) {
        uint256 preGas = gasleft();
        MemoryUserOp memory mUserOp = outOpInfo.mUserOp;
        _copyUserOpToMemory(userOp, mUserOp);
        outOpInfo.userOpHash = getUserOpHash(userOp);
        uint256 maxGasValues = mUserOp.preVerificationGas |
            mUserOp.verificationGasLimit |
            mUserOp.callGasLimit |
            userOp.maxFeePerGas |
            userOp.maxPriorityFeePerGas;
        require(maxGasValues <= type(uint120).max, "AA94 gas values overflow");
        uint256 requiredPreFund = _getRequiredPrefund(mUserOp);
        uint256 gasUsedByValidateAccountPrepayment;
        (
            gasUsedByValidateAccountPrepayment,
            validationData
        ) = _validateAccountPrepayment(userOp, outOpInfo, requiredPreFund);

        if (!_validateAndUpdateNonce(mUserOp.sender, mUserOp.nonce)) {
            revert FailedOp(0, "AA25 invalid account nonce");
        }

        //a "marker" where account opcode validation is done and paymaster opcode validation is about to start
        // (used only by off-chain simulateValidation)
        numberMarker();
        bytes memory context;
        unchecked {
            uint256 gasUsed = preGas - gasleft();
            if (userOp.verificationGasLimit < gasUsed) {
                revert FailedOp(0, "AA40 over verificationGasLimit");
            }
            outOpInfo.prefund = requiredPreFund;
            outOpInfo.contextOffset = getOffsetOfMemoryBytes(context);
            outOpInfo.preOpGas =
                preGas -
                gasleft() +
                userOp.preVerificationGas +
                gasUsedByValidateAccountPrepayment;
        }
    }
}
