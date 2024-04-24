# Iteration 3: Building a Standardized and Efficient Wallet

Our Smart Contract Wallet continues to evolve! In the previous iteration, we unlocked the power of user-initiated transactions. Now, iteration three focuses on refining these functionalities for a more standardized and efficient experience.

### Striving for Consistency: Standardizing Signature Verification

User-initiated transactions offer flexibility, but ensuring their validity is crucial. This iteration prioritizes standardizing our signature verification process. By adopting widely recognized standards, we aim to create a more predictable and interoperable system.

### Streamlining Efficiency: Optimizing Parameter Structuring

We also want to make things smoother for both users and developers. Here's where parameter structuring comes in. We'll refine the way transaction parameters are organized, making the entire process more streamlined and easier to manage.

### Improvements from Previous Iteration:

1. **UserOperation Library Creation**: To streamline the handling of user transactions, we create a separate library called UserOperationV3. This library defines a structured UserOperation object with additional parameters, providing a standardized approach for handling transaction data.
2. **Expanded UserOperation Parameters**: The UserOperation struct now encompasses several parameters, including the sender's address, nonce, call data, gas limits, and signature. These parameters enhance transaction specification and streamline transaction execution.

### UserOperation

**_UserOperation_** The user operation now consist of multiple sub varibales lets find out whats their role are:

- **Address sender**: used to define thesender address, wallet in our case
- **uint256 nonce**: The nonce of the wallet transaction from entrypoint
- **bytes callData**: Calldata of the transaction we need wallet to perform
- **uint256 callGasLimit**: Limit the gas for making the transaction
- **uint256 verificationGasLimit**: limit of the gas sender is willing to pay for the verification of the transaction
- **uint256 preVerificationGas**: Gas amount limited for the pre-verification tasks
- **uint256 maxFeePerGas**: represents the maximum amount of ether (in gwei) that the sender is willing to pay per unit of gas for the transaction to be included in a block. It determines the maximum total fee for the transaction.
- **uint256 maxPriorityFeePerGas**: This is the maximum tip (in gwei) that the sender is willing to pay per unit of gas for the transaction to be prioritized by miners. It represents an additional fee on top of the base fee and is used to incentivize miners to include the transaction in a block quickly.
- **bytes signature**: Signature from the wallet owner

## Tests

The testing section introduces a new test code to validate the owner's signature before executing a transaction, ensuring enhanced security for the smart contract wallet:

1.  The `deployWallet()` function is pivotal, and it remains unchanged for this iteration we can use the previous version of the function without a change.
2.  No change the first deployment test as well utilize the same test for testing the deployment of the smart contract wallet.
3.  A new test case is added to verify the validation of the owner's signature. This test involves several steps,

```javascript
    it("Should validate owner's signature", async function () {
      const { token, wallet, owner, otherAccount } = await loadFixture(
        deployWallet
      );
      // Calculating maxFeePerGas, maxPriorityFeePerGas, verificationGasLimit for userOperation
      let { maxFeePerGas, maxPriorityFeePerGas, verificationGasLimit } =
        await getGasFee(ethers.provider);
      // Calculating callData and callGasLimit for the userOperation
      const { callData, callGasLimit } = await encodeUserOpCallDataAndGasLimit(
        wallet,
        owner,
        {
          target: await token.getAddress(),
          value: 0,
          data: token.interface.encodeFunctionData("transfer", [
            otherAccount.address,
            ethers.parseEther("100"),
          ]),
        }
      );
      // Creating the userOperation
      let userOp = getUserOp(
        await wallet.getAddress(),
        0,
        callData,
        callGasLimit,
        verificationGasLimit,
        0,
        maxFeePerGas,
        maxPriorityFeePerGas
      );
      // Getting preverification Gas
      let preVerificationGas = await getPreVerificationGas(userOp);
      userOp = { ...userOp, preVerificationGas, callGasLimit };
      Calculating hash of the userOP
      let hash = await wallet.hashFunction(userOp);
      // Signing On UserOperation
      const signedMessage = await owner.signMessage(ethers.toBeArray(hash));
      userOp = { ...userOp, signature: signedMessage };
      // Verifying UserOperation
      expect(await wallet._validateSignature(userOp, hash)).not.to.be.reverted;
    });
```

In the testing procedure, we first calculate the gas fee parameters for the `UserOperation`, including the maximum fee per gas, maximum priority fee per gas, and verification gas limit. Then, we determine the call data and call gas limit for the UserOperation based on the token transfer transaction. Next, we create the UserOperation object with essential parameters such as sender address, nonce, call data, gas limits, and signature. Subsequently, we calculate the preverification gas for the UserOperation and compute its hash. Afterward, we sign the UserOperation with the owner's signature and verify the signature using the \_validateSignature function.

## Development

### UserOperation Library

we are focusing on enhancing the efficiency and usability of our smart contract wallet by introducing a dedicated library for managing user operations. The primary objective of this library is to define the UserOperation struct consistently across multiple contracts, ensuring reusability of hash and other related functions. By adding more variables to the `UserOperation` structure, we aim to expand its capabilities and flexibility in handling various transaction scenarios.  
Create the library in `contracts/libraries/UserOperationV3.sol`, we have added more varibles in the `userOperation` structure.

```javascript
struct UserOperation {
    address sender;
    uint256 nonce;
    bytes callData;
    uint256 callGasLimit;
    uint256 verificationGasLimit;
    uint256 preVerificationGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    bytes signature;
}
```

Follow the files in references section for more information on implementation and functions in the library.

### WalletV3 Contract

1. Lets create a `contracts/03_WalletV3.sol` contract, we streamlined the signature validation process and hash calculation by introducing the `hashFunction` and `_validateSignature` functions. These functions replace multiple previous functions and leverage **OpenZeppelin**'s cryptographic utilities for improved efficiency and reliability.

```javascript
...
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./libraries/UserOperationV3.sol";

contract WalletV3 is Ownable {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;
    using UserOperationLib for UserOperation;

    uint256 internal constant SIG_VALIDATION_FAILED = 1;

    constructor(address _admin) Ownable(_admin) {}

    function hashFunction(
        UserOperation calldata userOp
    ) public pure returns (bytes32) {
        return userOp.hash();
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
...
}
```

## Conclusion

### Building a Robust System: Iteration 3 of Our Smart Contract Wallet

Our Smart Contract Wallet keeps getting better! In the previous iteration, we introduced user-initiated transactions, expanding its capabilities. Now, iteration three focuses on refining these functionalities to create a more standardized and efficient system.

### Standardization for Trust: Streamlining Signature Verification

User-initiated transactions offer flexibility, but ensuring their legitimacy is crucial. This iteration prioritizes standardizing our signature verification process. By adopting widely recognized standards, we aim to create a more predictable and interoperable system. This fosters trust and simplifies integration with other blockchain applications.

### Efficiency Through Structure: Optimizing Parameter Structuring

We also want to make things smoother for both users and developers. Here's where parameter structuring comes in. We'll refine the way transaction parameters are organized, making the entire process more streamlined and easier to manage. This reduces complexity and improves development experience.

### The Benefits: A Refined and User-Friendly Wallet

These refinements within iteration three will culminate in a more refined and user-friendly Smart Contract Wallet. Users can benefit from the flexibility of user-initiated transactions within a predictable verification framework. Developers will appreciate the optimized parameter structuring, promoting efficient development and integration of transactions.

### The Journey Continues: Addressing Gas Fees and Security

While we've made significant progress, there's always room for improvement. Here's what we'll tackle next:

- **Fair Gas Fee Management**: Currently, there's no way to refund gas fees to the account executing transactions for the wallet owner. This discourages external accounts from participating. We'll introduce a mechanism to ensure fair gas fee reimbursement.
- **Enhanced Security Measures**: The current design leaves room for potential abuse. We'll implement safeguards to prevent malicious owners from creating invalid transactions that waste gas for the executing account.

### The Next Chapter: Introducing the Entrypoint Contract

To address these limitations, we'll introduce an Entrypoint smart contract in the next iteration. This contract will act as an intermediary, facilitating gas fee refunds and implementing security checks to prevent abuse and verify transaction validity

### The Future is Bright: A Secure and User-Friendly Wallet

Our goal is to create a Smart Contract Wallet that sets new standards in DeFi. Through continuous iteration, we'll refine features, address limitations, and leverage external libraries. Stay tuned as we push the boundaries of security, efficiency, and usability in the exciting realm of decentralized finance!

## References

1. [UserOperationV3.sol](contracts/libraries/UserOperationV3.sol)
2. [WalletV3.sol](contracts/03_WalletV3.sol)
3. [Test file](test/03_WalletV3.test.js)
4. [helpers.js](utils/helpers.js)
