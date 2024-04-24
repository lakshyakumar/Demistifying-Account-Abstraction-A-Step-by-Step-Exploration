// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./libraries/UserOperationV7.sol";
import "./common/NonceManager.sol";
import "./common/StakeManager.sol";
import "./interface/IWallet_with_paymaster.sol";
import "./interface/IPaymaster.sol";
import "./structure/UserOpV4.sol";

contract EntryPointV7 is NonceManager, StakeManager, ReentrancyGuard {
    uint256 public constant SIG_VALIDATION_FAILED = 1;
    bytes32 private constant INNER_OUT_OF_GAS = hex"deaddead";
    uint256 private constant REVERT_REASON_MAX_LEN = 2048;

    struct ValidationData {
        uint48 validAfter;
        uint48 validUntil;
    }

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

    function getMemoryBytesFromOffset(
        uint256 offset
    ) internal pure returns (bytes memory data) {
        assembly {
            data := offset
        }
    }

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

    function _validateSenderAndPaymaster(
        address sender,
        bytes calldata paymasterAndData
    ) external view {
        if (sender.code.length == 0) {
            revert("AA20 account not deployed");
        }
        if (paymasterAndData.length >= 20) {
            address paymaster = address(bytes20(paymasterAndData[0:20]));
            if (paymaster.code.length == 0) {
                // it would revert anyway. but give a meaningful message
                revert("AA30 paymaster not deployed");
            }
        }
        // always revert
        revert("");
    }
    function _simulateOnlyValidation(
        UserOperation calldata userOp
    ) internal view {
        try
            this._validateSenderAndPaymaster(
                userOp.sender,
                userOp.paymasterAndData
            )
        {} catch Error(string memory revertReason) {
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
        uint256 validationData,
        uint256 paymasterValidationData
    ) public pure returns (uint48 validAfter, uint48 validUntil) {
        (uint48 accValidUntil, uint48 accValidAfter) = _parseValidationData(
            validationData
        );
        (uint48 pmValidUntil, uint48 pmValidAfter) = _parseValidationData(
            paymasterValidationData
        );
        if (accValidAfter < pmValidAfter) validAfter = pmValidAfter;
        if (accValidUntil > pmValidUntil) validUntil = pmValidUntil;
    }

    function simulateHandleOp(
        UserOperation calldata op,
        address target,
        bytes calldata targetCallData
    ) external {
        UserOpInfo memory opInfo;
        _simulateOnlyValidation(op);
        (
            uint256 validationData,
            uint256 paymasterValidationData
        ) = _validatePrepayment(op, opInfo);
        (uint48 validAfter, uint48 validUntil) = _intersectTimeRange(
            validationData,
            paymasterValidationData
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
        IPaymaster.PostOpMode mode,
        UserOpInfo memory opInfo,
        bytes memory context,
        uint256 actualGas
    ) private returns (uint256 actualGasCost) {
        uint256 preGas = gasleft();
        address refundAddress;
        MemoryUserOp memory mUserOp = opInfo.mUserOp;
        uint256 gasPrice = getUserOpGasPrice(mUserOp);
        address paymaster = mUserOp.paymaster;
        if (paymaster == address(0)) {
            refundAddress = mUserOp.sender;
        } else {
            refundAddress = paymaster;
            if (context.length > 0) {
                actualGasCost = actualGas * gasPrice;
                if (mode != IPaymaster.PostOpMode.postOpReverted) {
                    IPaymaster(paymaster).postOp{
                        gas: mUserOp.verificationGasLimit
                    }(mode, context, actualGasCost);
                } else {
                    // solhint-disable-next-line no-empty-blocks
                    try
                        IPaymaster(paymaster).postOp{
                            gas: mUserOp.verificationGasLimit
                        }(mode, context, actualGasCost)
                    {} catch Error(string memory reason) {
                        revert FailedOp(
                            0,
                            string.concat("AA50 postOp reverted: ", reason)
                        );
                    } catch {
                        revert FailedOp(0, "AA50 postOp revert");
                    }
                }
            }
        }
        actualGas += preGas - gasleft();
        actualGasCost = actualGas * gasPrice;
        if (opInfo.prefund < actualGasCost) {
            revert FailedOp(0, "AA51 prefund below actualGasCost");
        }
        uint256 refund = opInfo.prefund - actualGasCost;
        _incrementDeposit(refundAddress, refund);
        bool success = mode == IPaymaster.PostOpMode.opSucceeded;
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
        UserOpInfo memory opInfo,
        bytes calldata context
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
        IPaymaster.PostOpMode mode = IPaymaster.PostOpMode.opSucceeded;
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
                mode = IPaymaster.PostOpMode.opReverted;
            }
        }
        unchecked {
            uint256 actualGas = preGas - gasleft() + opInfo.preOpGas;
            //note: opIndex is ignored (relevant only if mode==postOpReverted, which is only possible outside of innerHandleOp)
            return _handlePostOp(mode, opInfo, context, actualGas);
        }
    }

    function _executeUserOp(
        UserOperation calldata userOp,
        UserOpInfo memory opInfo
    ) private returns (uint256 collected) {
        uint256 preGas = gasleft();
        bytes memory context = getMemoryBytesFromOffset(opInfo.contextOffset);
        try this.innerHandleOp(userOp.callData, opInfo, context) returns (
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
            collected = _handlePostOp(
                IPaymaster.PostOpMode.postOpReverted,
                opInfo,
                context,
                actualGas
            );
        }
    }

    function handleOps(
        UserOperation calldata ops,
        address payable beneficiary
    ) public nonReentrant {
        unchecked {
            uint256 preGas = gasleft();
            UserOpInfo memory opInfo;
            (
                uint256 validationData,
                uint256 paymasterValidationData
            ) = _validatePrepayment(ops, opInfo);
            _validateAccountAndPaymasterValidationData(
                validationData,
                paymasterValidationData,
                address(0)
            );
            uint256 collected = _executeUserOp(ops, opInfo);
            uint256 actualGas = preGas - gasleft();
            (actualGas);
            _compensate(beneficiary, collected);
        }
    }

    function verifyCalculateGasAndPrefund(
        UserOperation calldata ops,
        UserOpInfo memory opInfo,
        MemoryUserOp memory mUserOp
    )
        public
        returns (
            uint256 validationData,
            uint256 gasUsedByValidateAccountPrepayment
        )
    {
        uint256 preGas = gasleft();
        opInfo.userOpHash = getUserOpHash(ops);
        // validate all numeric values in userOp are well below 128 bit, so they can safely be added
        // and multiplied without causing overflow
        uint256 maxGasValues = mUserOp.preVerificationGas |
            mUserOp.verificationGasLimit |
            mUserOp.callGasLimit |
            ops.maxFeePerGas |
            ops.maxPriorityFeePerGas;
        require(maxGasValues <= type(uint120).max, "AA94 gas values overflow");

        uint256 requiredPreFund = _getRequiredPrefund(mUserOp);
        uint256 missingAccountFunds = 0;
        uint256 bal = balanceOf(mUserOp.sender);
        missingAccountFunds = bal > requiredPreFund ? 0 : requiredPreFund - bal;

        address sender = mUserOp.sender;
        try
            Wallet(sender).validateSignatureAndSend{
                gas: mUserOp.verificationGasLimit
            }(ops, opInfo.userOpHash, requiredPreFund)
        returns (uint256 _validationData) {
            validationData = _validationData;
        } catch Error(string memory revertReason) {
            revert FailedOp(0, string.concat("AA23 reverted: ", revertReason));
        } catch {
            revert FailedOp(0, "AA23 reverted (or OOG)");
        }
        deposits[sender] = deposits[sender] - requiredPreFund;
        gasUsedByValidateAccountPrepayment = preGas - gasleft();
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

    function _validatePaymasterPrepayment(
        UserOperation calldata op,
        UserOpInfo memory opInfo,
        uint256 requiredPreFund,
        uint256 gasUsedByValidateAccountPrepayment
    ) internal returns (bytes memory context, uint256 validationData) {
        unchecked {
            MemoryUserOp memory mUserOp = opInfo.mUserOp;
            uint256 verificationGasLimit = mUserOp.verificationGasLimit;
            require(
                verificationGasLimit > gasUsedByValidateAccountPrepayment,
                "AA41 too little verificationGas"
            );
            uint256 gas = verificationGasLimit -
                gasUsedByValidateAccountPrepayment;

            address paymaster = mUserOp.paymaster;
            uint256 deposit = deposits[paymaster];
            if (deposit < requiredPreFund) {
                revert FailedOp(0, "AA31 paymaster deposit too low");
            }
            deposits[paymaster] = uint112(deposit - requiredPreFund);
            try
                IPaymaster(paymaster).validatePaymasterUserOp{gas: gas}(
                    op,
                    opInfo.userOpHash,
                    requiredPreFund
                )
            returns (bytes memory _context, uint256 _validationData) {
                context = _context;
                validationData = _validationData;
            } catch Error(string memory revertReason) {
                revert FailedOp(
                    0,
                    string.concat("AA33 reverted: ", revertReason)
                );
            } catch {
                revert FailedOp(0, "AA33 reverted (or OOG)");
            }
        }
    }

    function _getValidationData(
        uint256 validationData
    ) internal view returns (address aggregator, bool outOfTimeRange) {
        if (validationData == 0) {
            return (address(0), false);
        }

        (uint48 validUntil, uint48 validAfter) = _parseValidationData(
            validationData
        );
        // solhint-disable-next-line not-rely-on-time
        outOfTimeRange =
            block.timestamp > validUntil ||
            block.timestamp < validAfter;
    }

    function _validateAccountAndPaymasterValidationData(
        uint256 validationData,
        uint256 paymasterValidationData,
        address expectedAggregator
    ) internal view {
        (address aggregator, bool outOfTimeRange) = _getValidationData(
            validationData
        );
        if (expectedAggregator != aggregator) {
            revert FailedOp(0, "AA24 signature error");
        }
        if (outOfTimeRange) {
            revert FailedOp(0, "AA22 expired or not due");
        }
        //pmAggregator is not a real signature aggregator: we don't have logic to handle it as address.
        // non-zero address means that the paymaster fails due to some signature check (which is ok only during estimation)
        address pmAggregator;
        (pmAggregator, outOfTimeRange) = _getValidationData(
            paymasterValidationData
        );
        if (pmAggregator != address(0)) {
            revert FailedOp(0, "AA34 signature error");
        }
        if (outOfTimeRange) {
            revert FailedOp(0, "AA32 paymaster expired or not due");
        }
    }

    function _validatePrepayment(
        UserOperation calldata userOp,
        UserOpInfo memory outOpInfo
    ) public returns (uint256 validationData, uint256 paymasterValidationData) {
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
        uint256 gasUsedByValidateAccountPrepayment;
        uint256 requiredPreFund = _getRequiredPrefund(mUserOp);
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
        if (mUserOp.paymaster != address(0)) {
            (context, paymasterValidationData) = _validatePaymasterPrepayment(
                userOp,
                outOpInfo,
                requiredPreFund,
                gasUsedByValidateAccountPrepayment
            );
        }
        unchecked {
            uint256 gasUsed = preGas - gasleft();
            if (userOp.verificationGasLimit < gasUsed) {
                revert FailedOp(0, "AA40 over verificationGasLimit");
            }
            outOpInfo.prefund = requiredPreFund;
            outOpInfo.contextOffset = getOffsetOfMemoryBytes(context);
            outOpInfo.preOpGas = preGas - gasleft() + userOp.preVerificationGas;
        }
    }
}
