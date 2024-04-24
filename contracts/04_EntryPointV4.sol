// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./libraries/UserOperationV3.sol";
import "./common/NonceManager.sol";
import "./common/StakeManager.sol";
import "./interface/IWallet.sol";
import "./structure/UserOpV4.sol";

contract EntryPointV4 is NonceManager, StakeManager {
    uint256 public constant SIG_VALIDATION_FAILED = 1;
    bytes32 private constant INNER_OUT_OF_GAS = hex"deaddead";
    uint256 private constant REVERT_REASON_MAX_LEN = 2048;

    using UserOperationLib for UserOperation;

    error FailedOp(uint256 opIndex, string reason);

    event UserOperationRevertReason(
        bytes32 indexed userOpHash,
        address indexed sender,
        uint256 nonce,
        bytes revertReason
    );

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

    function handleOps_v1(UserOperation calldata ops) public {
        UserOpInfo memory opInfo;
        MemoryUserOp memory mUserOp = opInfo.mUserOp;
        _copyUserOpToMemory(ops, mUserOp);
        (
            uint256 validationData,
            uint256 gasUsedByValidateAccountPrepayment
        ) = verifyCalculateGasAndPrefund(ops, opInfo, mUserOp);
        bool success = call(mUserOp.sender, 0, ops.callData, ops.callGasLimit);
        // uint256 collected = _executeUserOp_v1(ops, opInfo, mUserOp);
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
        uint256 opIndex,
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
                    opIndex,
                    string.concat("AA23 reverted: ", revertReason)
                );
            } catch {
                revert FailedOp(opIndex, "AA23 reverted (or OOG)");
            }
            gasUsedByValidateAccountPrepayment = preGas - gasleft();
        }
    }

    function _validatePrepayment(
        uint256 opIndex,
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
        (
            uint256 gasUsedByValidateAccountPrepayment,
            uint256 validationData
        ) = _validateAccountPrepayment(
                opIndex,
                userOp,
                outOpInfo,
                requiredPreFund
            );
    }

    function verificationEnabledPayPrefund(UserOperation calldata ops) public {
        UserOpInfo memory opInfo;
        MemoryUserOp memory mUserOp = opInfo.mUserOp;
        _copyUserOpToMemory(ops, mUserOp);
        opInfo.userOpHash = getUserOpHash(ops);
        // validate all numeric values in userOp are well below 128 bit, so they can safely be added
        // and multiplied without causing overflow
        uint256 maxGasValues = mUserOp.preVerificationGas |
            mUserOp.verificationGasLimit |
            mUserOp.callGasLimit |
            ops.maxFeePerGas |
            ops.maxPriorityFeePerGas;
        require(maxGasValues <= type(uint120).max, "AA94 gas values overflow");
        uint256 requiredPrefund = 4200000000;
        address sender = mUserOp.sender;
        Wallet(sender).validateSignatureAndSend(
            ops,
            opInfo.userOpHash,
            requiredPrefund
        );
    }
}
