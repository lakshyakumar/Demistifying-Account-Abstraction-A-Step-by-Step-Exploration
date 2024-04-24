# Streamlining User Experience: Iteration 5 of Our Smart Contract Wallet

Our Smart Contract Wallet keeps evolving, and iteration five brings exciting user experience improvements! This time, we're laser-focused on refining the functionality of the `EntryPoint` contract. This innovative component acts as a bridge between users and the wallet, ensuring secure and efficient transactions.

### Introducing handleOps: The Orchestrator

At the heart of this update lies the implementation of the crucial handleOps function. Think of it as the conductor of the transaction orchestra. `handleOps` oversees a series of vital steps, including:

- **Validation**: Meticulously examining transactions to ensure security and authorization.
- **Execution**: Putting the validated transactions into action on the blockchain.
- **Gas Management**: Calculating the gas fees required for each transaction.
- **Compensation**: Reimbursing users or relayers (bundlers) for the gas spent on their behalf.

#### handleOps in Action:

The `handleOps` function works seamlessly behind the scenes, calling upon other specialized functions to complete its tasks. Here's a simplified breakdown:

1. `_validatePrepayment`: This function meticulously checks if a transaction is valid and authorized before proceeding.
2. `_executeUserOp`: This function takes the baton from `_validatePrepayment` and executes the validated transaction. It further delegates tasks to:
3. `innerHandleOps`: This function tackles the core execution logic.
4. `_handlePosrtOps`: This function calculates the actual gas costs incurred during execution.
5. `_compensate`: Finally, `_compensate` ensures that users or relayers who covered the gas fees are reimbursed appropriately.

### The Benefits: A More Robust and User-Friendly Wallet

By refining the EntryPoint contract and implementing handleOps, we're creating a more robust and user-friendly Smart Contract Wallet. Users can expect:

- **Seamless Transaction Execution**: The handleOps function orchestrates a smooth transaction experience, handling all the complexities behind the scenes.
- **Enhanced Security**: Robust validation and secure execution ensure the safety of user funds.
- **Fair Gas Management**: Transparent gas calculation and compensation mechanisms guarantee fairness for all parties involved.

## Tests

In this iteration, we prioritize writing tests to validate the behavior of the `handleOps` function, ensuring seamless execution of user operations and accurate fund transfers. We continue building upon the foundation laid in previous iterations, aiming to create a more robust and user-friendly wallet solution.

1.  We'll begin by writing tests to validate the functionality of the `handleOps` function. These tests will supplement the existing suite, ensuring comprehensive coverage and accuracy in our wallet contract's behavior.
    We will be invoking `handleOPs` on `Enrtypoint` from our testing script.

```javascript
describe("It should call and execute userOp", function () {
  it("Should call and execute userOp", async function () {
    const { token, entryPoint, wallet, owner, otherAccount } =
      await loadFixture(deployContracts);
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
    let userOp = getUserOp(
      await wallet.getAddress(),
      nonce,
      callData,
      callGasLimit,
      verificationGasLimit,
      1000000,
      maxFeePerGas,
      maxPriorityFeePerGas
    );
    let preVerificationGas = await getPreVerificationGas(userOp);

    userOp = { ...userOp, preVerificationGas };
    let hash = await wallet.hashFunction(userOp);
    const signedMessage = await owner.signMessage(ethers.toBeArray(hash));
    userOp = { ...userOp, signature: signedMessage };
    const txn = await entryPoint
      .connect(otherAccount)
      .handleOps(userOp, otherAccount.address);
    txn.wait();
    expect(await token.balanceOf(otherAccount.address)).to.equal(
      ethers.parseEther("10")
    );
  });
});
```

## Development

### EntrypointV5

In `contracts/05_EntryPointV5.sol`, we delve into the implementation of the `handleOps` function within the EntryPointV5.sol contract. This function serves as a central component responsible for handling user operations, validating prepayments, executing operations, and managing gas compensation.  
The `handleOps` function is designed to orchestrate the processing of user operations, ensuring their validity, execution, and proper gas compensation. It encapsulates several essential functionalities, including prepayment validation, operation execution, gas cost calculation, and beneficiary compensation.

- **Internal Functions**: Several internal functions are utilized within the handleOps function to modularize and streamline its logic. These functions include \_validatePrepayment, \_executeUserOp, \_handlePostOp, and \_compensate.
- **Reentrancy Protection**: The contract incorporates the ReentrancyGuard modifier to prevent reentrancy attacks, ensuring the integrity of the operation execution process.
- **Gas Cost Calculation**: Gas costs are accurately calculated based on the gas consumed during operation execution and the configured gas price parameters.
- **Error Handling**: The function handles various error scenarios gracefully, reverting transactions with appropriate error messages when necessary.

```javascript
  contract EntryPointV5 is NonceManager, StakeManager, ReentrancyGuard {
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
    ...
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
   ...
}
```

### WalletV5 Contract

We focus on implementing the `_validateNonce` function within the `contracts/05_WalletV5.sol` contract. This internal function plays a crucial role in validating nonce values associated with transactions, thereby ensuring the integrity and security of our Ethereum wallet solution.  
Nonce validation is a critical aspect of transaction processing in Ethereum. By implementing the `_validateNonce` function, we enforce the requirement that each transaction must have a nonce value corresponding to the next sequential nonce expected for the sending account. This helps prevent replay attacks and ensures the correct execution order of transactions.  
The `_validateNonce` function, defined within the WalletV5.sol contract, accepts a single parameter: nonce, representing the nonce value to be validated. This function internally calls the validateNonce function of the entry point contract, passing the nonce value for validation.

```javascript
  contract WalletV5 is Ownable {
   ...
    function _validateNonce(uint256 nonce) internal view virtual {
        entryPoint().validateNonce(0, nonce);
    }
  ...
}
```

The recent modifications made to the EntryPointV5.sol contract primarily focus on augmenting its capabilities to handle user operations more efficiently and securely.

One significant addition is the implementation of the handleOps function, which serves as the central processing unit for user-initiated operations. This function orchestrates various tasks, including validation, execution, gas cost computation, and beneficiary compensation, streamlining the entire process within a single, cohesive structure.

To bolster security measures, a validateNonce function has been integrated to validate the nonce associated with user operations. This helps prevent replay attacks by ensuring that each operation is uniquely identified and executed only once.

Additionally, the contract now includes functions for calculating gas prices based on specified parameters and checking gas limits to prevent out-of-gas errors during execution. These enhancements contribute to a more robust and reliable execution environment for user operations.

Furthermore, internal functions such as innerHandleOp have been introduced to handle the actual execution of user operations, efficiently managing revert reasons and updating operation statuses as necessary.

Finally, upon successful execution of user operations, the handleOps function ensures fair compensation to the designated beneficiary for the gas costs incurred during the operation's execution, thereby promoting fairness and incentivizing participation.

## Conclusion

### Building a Robust Future: Wrapping Up Iteration 5 of Our Smart Contract Wallet

Iteration 5 has been a monumental step forward for our Smart Contract Wallet! This time, we concentrated on empowering the EntryPoint contract, the secure bridge between users and the wallet.

The centerpiece of this update is the implementation of the `handleOps` function. Working tirelessly behind the scenes, it orchestrates a seamless transaction experience by validating, executing, managing gas, and compensating participants. This streamlined approach strengthens security through robust pre-payment validation and fosters fairness with transparent gas calculation and compensation mechanisms.

### Beyond User Experience: Enhanced Security and Fairness

Iteration 5 goes beyond user experience. We've significantly bolstered security with robust validation through `_validatePrepayment`. This ensures only authorized transactions progress. Additionally, transparent gas calculation and compensation mechanisms, facilitated by `_handlePosrtOps` and `_compensate`, guarantee fairness for all parties involved.

### The Road Ahead: Refinement and Beyond

Our work isn't over! We'll be rigorously testing handleOps to ensure flawless operation. We'll also be introducing new functionalities within interfaces and contracts to further support these enhancements. But that's not all! We'll be:

- Simulating transactions beforehand to understand parameters and capture potential failure scenarios.
- Refining gas calculation and compensation mechanisms for optimal efficiency and fairness.

## References

1. [EntryPointV5](contracts/05_EntryPointV5.sol)
2. [WalletV5.sol](contracts/05_WalletV5.sol)
3. [Test file](test/05_WalletV5.test.js)
