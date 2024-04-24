# Unveiling the Future: Iteration 6 of Our Smart Contract Wallet

The journey continues! In iteration six of our Smart Contract Wallet development, we're thrilled to introduce the simulateHandleOp function. This groundbreaking addition empowers users with the ability to _verify and simulate transactions before execution_.

Imagine a world where you can test the waters of a transaction before it's set in stone. With `simulateHandleOp`, that's exactly what becomes possible. This functionality paves the way for a more _secure and transparent_ user experience within the realm of Decentralized Finance (DeFi).

Stay tuned as we delve deeper into the inner workings of simulateHandleOp and explore how it revolutionizes transaction processing within our Smart Contract Wallet!

## Tests

The test case executes the `simulateHandleOp` function from the `Entrypoint` contract, passing in a generated user operation. This function simulates the execution of the user operation and verifies its outcome. The expectation is that the simulation fails with a specific error message, which is confirmed using the `.to.be.revertedWithCustomError()` function. This part of the test focuses solely on the simulation functionality, assuming that gas calculations, user operations, and deployment tests remain unchanged from previous iterations.

```javascript
it("Should call and execute simulateHandleOp", async function () {
  const { token, entryPoint, wallet, owner, otherAccount } = await loadFixture(
    deployContracts
  );
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
  await expect(
    entryPoint
      .connect(otherAccount)
      .simulateHandleOp(userOp, userOp.sender, userOp.callData)
  )
    .to.be.revertedWithCustomError(entryPoint, "ExecutionResult")
    .withArgs(anyValue, anyValue, 0, anyValue, true, anyValue);
});
```

The test case adds an execution of `simulateHandleOp` to verify its functionality. It sets up the necessary environment, generates a user operation to transfer tokens, signs the operation, and then calls `simulateHandleOp` on the entry point contract with the generated user operation. The test expects the simulation to revert with a specific error message indicating an `ExecutionResult`.

## Development

### EntrypointV6

The newly added functions in the `contracts\06_EntryPointV6.sol` contract enhance the simulation capabilities by introducing the `simulateHandleOp` function. Here's a breakdown of the additions:

- **\_validateSender**: This external view function checks if the sender's address corresponds to a deployed contract. If the sender's address does not have any bytecode deployed, it reverts with the error message `"AA20 account not deployed"`.

- **\_simulateOnlyValidation**: This internal view function performs preliminary validation on the user operation. It invokes `_validateSender` to ensure the sender's address is valid. If any validation fails, it reverts with a custom `FailedOp` error containing the reason for the failure.

- **\_parseValidationData**: This public pure function parses the validation data to extract the `validUntil` and validAfter timestamps. If the `validUntil` timestamp is 0, indicating no expiry, it sets it to the maximum value of uint48.

- **\_intersectTimeRange**: Another public pure function, `_intersectTimeRange` extracts and returns the `validAfter` and `validUntil` timestamps from the validation data.

- **simulateHandleOp**: This external function is the core of the simulation functionality. It validates the user operation, determines the time validity range, executes the user operation, and attempts to call the target contract if provided. If any of these steps fail, it reverts with an ExecutionResult containing relevant information such as gas consumption, validity timestamps, and the success of the target contract call.

```javascript
    ...
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
   ...
```

several new functions are added to support the `simulateHandleOp` feature. `_validateSender` checks if the sender's address corresponds to a deployed contract and reverts if not. `_simulateOnlyValidation` performs preliminary validation on the user operation, ensuring the sender's address is valid. `_parseValidationData` and `_intersectTimeRange` functions parse and extract relevant timestamp data from validation information. Finally, `simulateHandleOp` function simulates the execution of a user operation, validating it, determining time validity, executing the operation, and attempting to call a target contract if provided, reverting with an `ExecutionResult` if any step fails.

## Conclusion

### Building Confidence: Wrapping Up Iteration 6 of Our Smart Contract Wallet

Iteration 6 has been another crucial step forward for our Smart Contract Wallet! This time, we focused on empowering users with greater control and security through the EntryPointV6 contract.

### Introducing simulateHandleOp: A Transaction Foresight

The star of the show this iteration is the innovative simulateHandleOp function. Think of it as a crystal ball for your transactions. This groundbreaking feature allows users to verify and simulate transactions before execution. Imagine the peace of mind that comes from testing the waters of a transaction before it's set in stone! simulateHandleOp paves the way for a more secure and transparent user experience within the realm of Decentralized Finance (DeFi).

### Beyond Implementation: Ensuring Flawless Functionality

Our commitment to user confidence goes beyond simply introducing features. We've meticulously tested `simulateHandleOp` with dedicated testing scripts, ensuring it flawlessly handles user operations.

### The Road Ahead: Continuous Refinement

While `simulateHandleOp` significantly enhances the EntryPoint contract, we're dedicated to continuous improvement. We'll be conducting further testing and analysis to identify and address any potential limitations in the validation and execution process.

Looking ahead to the next iteration, we'll be integrating the `Paymaster` feature into the `EntryPoint`. This exciting addition will further enhance its functionality and empower even more seamless transaction processing.

## References

1. [EntryPointV6](contracts/06_EntryPointV6.sol)
2. [WalletV6.sol](contracts/06_WalletV6.sol)
3. [Test file](test/06_WalletV6.test.js)
