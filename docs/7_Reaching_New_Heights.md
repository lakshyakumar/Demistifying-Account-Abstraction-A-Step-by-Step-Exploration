# Reaching New Heights: Iteration 7 of Our Smart Contract Wallet

The evolution continues! Iteration seven of our Smart Contract Wallet development ushers in a revolutionary concept: _gasless transactions_. This exciting advancement is made possible by the introduction of the `Paymaster` contract. Imagine a world where you can execute transactions within the wallet and interact with smart contracts without worrying about gas fees!

The Paymaster plays a pivotal role in achieving this vision. Alongside this innovation, we've also refined the underlying structure of _user operations_ (UserOp) by introducing a new field named `paymasterAndData`. This addition provides the necessary framework for seamless integration with the `Paymaster` contract. To ensure seamless interaction, the `Entrypoint` contract has been adapted to handle paymaster-related parameters effectively.

Get ready to explore the exciting possibilities of gasless transactions in this chapter of our Smart Contract Wallet journey!

### Introducing Paymaster

The `Paymaster` contract facilitates gasless transactions by managing deposits and handling transaction validation. It integrates with the `Entrypoint` and provides mechanisms to add and withdraw deposits. Notable features include:

- **Gasless Transactions**: Users can perform transactions without worrying about gas fees, as the **Paymaster** handles the gas costs.
- **Validation and Parsing**: **Paymaster** includes functions such as `validatePaymasterUserOp` and `parsePaymasterAndData` to validate and parse paymaster data, ensuring the integrity of transactions.

## Tests

We have updated the testing script to incorporate deployment and validation of the `Paymaster` contract. Additionally, testing scenarios for transactions involving **Paymaster** have been added to ensure robust functionality.

1. Let's kick off the deployment process by incorporating the `VerifyingPaymasterV7` contract into the `deployContract()` function

```javascript
    ...
    const Paymaster = await ethers.getContractFactory("VerifyingPaymasterV7");
    const paymaster = await Paymaster.deploy(
      await entryPoint.getAddress(),
      owner.address
    );
    await paymaster.waitForDeployment();
    await owner.sendTransaction({
      to: await paymaster.getAddress(),
      value: ethers.parseEther("1"),
    });
    await paymaster.addDeposit({ value: ethers.parseEther("0.5") });
    ...
```

2. Once the `paymaster` contract is deployed, it's crucial to validate its deployment to ensure its functionality. lets write a deplyment test case:

```javascript
   describe("Deployment", function () {
    it("Should Deploy wallet, token, paymaster and entrypoint", async function () {
      ...
      expect(await paymaster.getAddress()).to.exist;
    });
  });
```

3. To comprehensively test the `Paymaster` contract, it's imperative to include various testing scenarios. Below is a test case for scenario that verifies, calls, and executes a user operation with the `Paymaster` contract:

```javascript
it("Test should verify, call and execute userop with paymaster 0x", async function () {
  const { token, wallet, paymaster, entryPoint, owner, otherAccount } =
    await loadFixture(deployContracts);
  const MOCK_VALID_UNTIL = "0x00000000deadbeef";
  const MOCK_VALID_AFTER = "0x0000000000001234";

  let nonce = await wallet.getNonce();
  let { maxFeePerGas, maxPriorityFeePerGas, verificationGasLimit } =
    await getGasFee(ethers.provider);
  const { callData, callGasLimit } = await encodeUserOpCallDataAndGasLimit(
    wallet,
    owner,
    {
      target: await token.getAddress(),
      value: 0,
      data: token.interface.encodeFunctionData("transfer", [
        otherAccount.address,
        ethers.parseEther("10"),
      ]),
    }
  );
  let userOp = {
    ...getUserOp(
      await wallet.getAddress(),
      nonce,
      callData,
      callGasLimit,
      verificationGasLimit,
      1000000,
      maxFeePerGas,
      maxPriorityFeePerGas
    ),
    paymasterAndData: "0x",
  };
  const pmHash = await paymaster.getHash(
    userOp,
    MOCK_VALID_UNTIL,
    MOCK_VALID_AFTER
  );
  const pmSignedMessage = await owner.signMessage(ethers.toBeArray(pmHash));
  let hash = await wallet.hashFunction(userOp);
  let { chainId } = await ethers.provider.getNetwork();

  const codedData = abiCoder.encode(
    ["bytes32", "address", "uint256"],
    [hash, await entryPoint.getAddress(), chainId]
  );
  let encodedData = ethers.keccak256(codedData);
  const signedMessage = await owner.signMessage(ethers.toBeArray(encodedData));
  const paymasterAndData = ethers.concat([
    await paymaster.getAddress(),
    abiCoder.encode(["uint48", "uint48"], [MOCK_VALID_UNTIL, MOCK_VALID_AFTER]),
    pmSignedMessage,
  ]);
  userOp = {
    ...userOp,
    signature: signedMessage,
    paymasterAndData,
  };
  await expect(
    entryPoint
      .connect(otherAccount)
      .simulateHandleOp(userOp, userOp.sender, userOp.callData)
  )
    .to.be.revertedWithCustomError(entryPoint, "ExecutionResult")
    .withArgs(anyValue, anyValue, anyValue, anyValue, true, anyValue);
  const txn = await entryPoint
    .connect(otherAccount)
    .handleOps(userOp, otherAccount.address);
  txn.wait();
  expect(await token.balanceOf(otherAccount.address)).to.equal(
    ethers.parseEther("10")
  );
});
```

This test scenario encompasses the verification, invocation, and execution of a user operation using the paymaster contract, thereby ensuring its seamless functionality within the Ethereum ecosystem.

## Development

### EntrypointV7

The `contracts\07_EntryPointV7.sol` contract has undergone significant changes and enhancements to improve its functionality and robustness. Let's delve into the key modifications and their benefits:

1. **Struct Refactoring**:
   The `ValidationData` struct has been introduced to encapsulate validation-related data, enhancing code readability and organization.
2. **Event Declaration**:
   An `UserOperationEvent` event has been declared to facilitate event-driven architecture, providing visibility into user operation events for monitoring and analysis purposes.
3. **Function Refinements**:
   - The `getMemoryBytesFromOffset` function has been implemented to retrieve memory bytes from a specified offset, streamlining memory management operations within the contract.
   - Refinements have been made to the `_validateSenderAndPaymaster` function to handle edge cases more gracefully, such as reverting with meaningful error messages when sender or paymaster accounts are not deployed.
4. **Simulation and Validation**:
   - The `_simulateOnlyValidation` function has been introduced to simulate validation processes without executing actual operations, enabling efficient testing and validation of user operations.
   - A new `_intersectTimeRange` function has been added to calculate the intersection of time ranges, enhancing validation accuracy and ensuring proper execution within specified time constraints.
5. **Execution and Handling**:
   - The `simulateHandleOp` function now incorporates comprehensive validation checks, gas calculations, and execution handling for user operations, promoting efficient and secure contract execution.
   - Internal functions such as `_handlePostOp` and `_executeUserOp` have been refined to handle post-operation tasks, gas management, and error handling, ensuring consistent and reliable contract behavior.
6. **Prepayment Validation**:
   - Extensive modifications have been made to the `_validatePrepayment` function to validate user prepayments, nonce validity, and paymaster interactions, fostering trust and security in transaction processing.
   - Improved validation logic ensures accurate verification of account and paymaster data, mitigating potential risks and vulnerabilities in the transaction lifecycle.

```javascript
contract EntryPointV7 is NonceManager, StakeManager, ReentrancyGuard {
    ...
    struct ValidationData {
        uint48 validAfter;
        uint48 validUntil;
    }
    ...
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
```

### PaymasterV7 Contract

The added code in the `contracts\07_PaymasterV7.sol` contract introduces functionalities for verifying user operations and managing prepayments. It leverages cryptographic signatures for validation, incorporates gas cost calculations, and facilitates interaction with the EntryPoint contract for depositing and withdrawing funds. Additionally, it implements methods for parsing paymaster data, handling post-operation actions, and managing contract deposits.

```javascript
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

```

The development involves integrating functionalities for validating user operations, managing prepayments, and handling gas calculations within the EntryPoint and Paymaster contracts. These additions enable secure and efficient execution of user transactions while ensuring proper management of funds and gas costs.

## Conclusion

### Building for the Future: Wrapping Up Iteration 7 of Our Smart Contract Wallet

Iteration 7 has been a game-changer for our Smart Contract Wallet, paving the way for a more user-friendly and efficient future! This time, we focused on introducing the revolutionary concept of gasless transactions.

### Introducing the Paymaster: Powering a Gasless Future

The centerpiece of this update is the innovative Paymaster contract. This groundbreaking addition allows users to bypass gas fees entirely, both within the wallet and when interacting with smart contracts. Imagine the possibilities of seamless transactions without any upfront costs!

### Seamless Integration for a Powerful Future

To seamlessly integrate the Paymaster into our architecture, we've made key modifications:

- **Enhanced UserOperation Structure**: We've included a new field named paymasterAndData within the UserOperation structure. This provides a robust framework for smooth interaction with the Paymaster contract.
- **Adapting the Entrypoint**: The Entrypoint contract has been updated to handle paymaster-related parameters effectively. Additionally, it now incorporates the \_payPrefund function from the Paymaster, enabling deposits and withdrawals from the entry point.
- **Empowering the Paymaster Contract**: The Paymaster contract itself comes equipped with features like validatePaymasterUserOp and parsePaymasterAndData. These functionalities ensure proper validation and parsing of paymaster data.

### Continuous Improvement: Looking Ahead

While iteration 7 marks a significant leap forward, we remain committed to continuous improvement:

- **Enhanced Paymaster Handling**: We'll be focusing on refining our system's ability to handle various types of paymasters, ensuring broader compatibility.
- **Codebase Optimization**: Further codebase optimization is planned to enhance efficiency and performance.
- **Expanding the Ecosystem**: We welcome contributions in the form of pull requests for bundler implementations and additional paymaster contracts. This collaborative approach will further enhance the flexibility and usability of our platform.
  Thank you for joining us on this journey! We're excited to explore the possibilities of gasless transactions and build a future where everyone can participate in DeFi with ease. Stay tuned for what's next!

## References

1. [EntryPointV7](contracts/07_EntryPointV7.sol)
2. [WalletV7.sol](contracts/07_WalletV7.sol)
3. [Test file](test/07_WalletV7.test.js)
4. [PaymasterV7](contracts/07_PaymasterV7.sol)
5. [UserOperationV7](contracts/libraries/UserOperationV7.sol)
