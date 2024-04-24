# Leveling Up Security and Efficiency: Iteration 4 of Our Smart Contract Wallet

Our Smart Contract Wallet keeps evolving, and iteration four brings a wave of exciting upgrades! We're focused on three key areas:

1. **Refined Transaction Execution**: Streamlining the process of executing transactions within the wallet.
2. **Enhanced Security Measures**: Bolstering the security of our wallet to protect user funds.
3. **Streamlined Gas Fee Management**: Introducing functionalities to make gas fees more manageable for users.

### Introducing the Entrypoint: A Game Changer

Central to these improvements is the introduction of the Entrypoint contract. This innovative component acts as a bridge between external accounts and the Smart Contract Wallet. It plays a pivotal role in revolutionizing transaction validation and gas fee handling. The EntryPoint serves as a multifaceted entity, orchestrating transaction validation, gas fee management, and stake handling within our smart contract wallet architecture. Its role extends beyond mere transaction facilitation to encompass broader functionalities that ensure the integrity and security of our transaction ecosystem. We are focusing on the stake managing capabilities of entrypoint in the iteration.

### The Power of Entrypoint: stake and nonce Management

The Entrypoint contract boasts two key functionalities:

- Stake and Nonce Management: This ensures users have sufficient funds staked (locked) to cover potential gas fees before initiating transactions. Additionally, it utilizes nonces to prevent replay attacks, a common security threat in blockchain environments.

### WalletV4: Validating and Sending with Confidence

The WalletV4 contract leverages the Entrypoint's capabilities through two crucial functions:

- **validateUserOp**: This function meticulously examines every user-initiated transaction, ensuring it adheres to all security protocols and is authorized by the rightful owner.
- **validateSignatureAndSend**: Once a transaction is validated, this function securely transmits it for execution on the blockchain.

## Tests

In our ongoing development journey towards enhancing smart contract wallet functionality, the deployment of the EntryPoint contract marks a significant milestone. Let's dive into the steps involved in deploying and testing the EntryPoint contract within our ecosystem.  
To ensure the robustness and reliability of our EntryPoint contract, we have devised a series of tests that thoroughly examine its deposit and fund transfer mechanisms. Let's delve into the details of these tests and how they validate the functionality of our EntryPoint contract.

1.  In our `deployContract` function, we incorporate the deployment logic for the `EntryPoint` contract alongside the existing deployment process for the wallet and token contracts. This ensures that the `EntryPoint` is seamlessly integrated into our ecosystem, ready to orchestrate transaction validation and gas fee management.

```javascript
    ...
    const EntryPoint = await ethers.getContractFactory("EntryPointV4");
    const entryPoint = await EntryPoint.deploy();
    await entryPoint.waitForDeployment();
    ...
    return {
      token,
      wallet,
      entryPoint,
      owner,
      otherAccount,
      anotherAccount,
     };
```

2. To validate the successful deployment of the `EntryPoint` contract, we include a dedicated test within our deployment test suite. This test verifies that the `EntryPoint` contract is deployed and its address is accessible, confirming its presence within the deployed ecosystem.

```javascript
  describe("Deployment", function () {
    it("Should Deploy wallet, token and entrypoint", async function () {
      ...
      expect(await entryPoint.getAddress()).to.exist;
    });
   });
```

3. This tests validates the deposit and sending functionality by depositing `0.5 ETH` to the entry point contract from the owner's address. Subsequently, it checks whether the balance of the owner's address within the `EntryPoint` contract reflects the deposited amount accurately. Also, we simulate a transaction where the owner sends `0.5 ETH` directly to the entry point contract. Similar to the previous test, we confirm that the balance of the owner's address within the `EntryPoint` contract correctly reflects the transaction amount.

```javascript
describe("entrypoint", function () {
  it("Test Entrypoint deposit", async function () {
    const { entryPoint, owner } = await loadFixture(deployContracts);
    await entryPoint.depositTo(owner.address, {
      value: ethers.parseEther("0.5"),
    });
    let balance = await entryPoint.balanceOf(owner.address);
    expect(balance).to.equal(ethers.parseEther("0.5"));
  });
  it("Test entryPoint sending", async function () {
    const { entryPoint, owner } = await loadFixture(deployContracts);
    const tx = await owner.sendTransaction({
      to: await entryPoint.getAddress(),
      value: ethers.parseEther("0.5"),
    });
    let balance = await entryPoint.balanceOf(owner.address);
    expect(balance).to.equal(ethers.parseEther("0.5"));
  });
});
```

4. In Previous Test we invoked the function directly from EOA, this test validates the functionality of the `_payPrefund` function within the wallet contract. It ensures that when `0.5 ETH` is deducted from the wallet's balance, the balance is updated accordingly. Also we validate the capability of the wallet contract to utilize the gas funds deposited in the `EntryPoint` contract. After calling the `callWalletsPayPrefund`(will be replaced in future instances) function in the `EntryPoint` contract.

```javascript
describe("_payPrefund function in wallet", function () {
  it("Test _payPrefund function", async function () {
    const { wallet, owner } = await loadFixture(deployContracts);
    let balance = await ethers.provider.getBalance(await wallet.getAddress());
    expect(balance).to.equal(ethers.parseEther("1"));
    await wallet._payPrefund(ethers.parseEther("0.5"));
    balance = await ethers.provider.getBalance(await wallet.getAddress());
    expect(balance).to.equal(ethers.parseEther("0.5"));
  });
});
describe("_payPrefund function in wallet uisng entrypoint", function () {
  it("Test Sending Ether to Entrypoint", async function () {
    const { wallet, entryPoint, owner } = await loadFixture(deployContracts);
    let balance = await ethers.provider.getBalance(await wallet.getAddress());
    expect(balance).to.equal(ethers.parseEther("1"));
    await entryPoint.callWalletsPayPrefund(await wallet.getAddress());
    balance = await entryPoint.balanceOf(await wallet.getAddress());
    expect(balance).to.equal(ethers.parseEther("0.0000000042"));
  });
});
```

5. This test suite assesses the functionality of the `verificationEnabledPayPrefund` and `handleOps_v1` function within the `EntryPoint` contract along with the calculations for `UserOps` params which can be found in file `utils\helpers.js`. It executes various transaction operations and validates their outcomes.

```javascript
describe("_payPrefund function with validation and op", function () {
  it("Test verificationEnabledPayPrefund function", async function () {
    const { wallet, entryPoint, owner } = await loadFixture(deployContracts);
    let balance = await ethers.provider.getBalance(await wallet.getAddress());
    expect(balance).to.equal(ethers.parseEther("1"));

    let nonce = await wallet.getNonce();
    let userOp = getUserOp(await wallet.getAddress(), nonce);
    let hash = await wallet.hashFunction(userOp);
    const signedMessage = await owner.signMessage(ethers.toBeArray(hash));
    userOp = { ...userOp, signature: signedMessage };

    await entryPoint.verificationEnabledPayPrefund(userOp);
    balance = await entryPoint.balanceOf(await wallet.getAddress());
    expect(balance).to.equal(ethers.parseEther("0.0000000042"));
  });
  it("Test _payPrefund function with token transfer calldata", async function () {
    const { wallet, entryPoint, token, owner, otherAccount } =
      await loadFixture(deployContracts);
    let balance;

    let nonce = await wallet.getNonce();

    await token.transfer(await wallet.getAddress(), ethers.parseEther("100"));
    let userOp = getUserOp(await wallet.getAddress(), nonce);
    let preVerificationGas = await getPreVerificationGas(userOp);
    userOp = { ...userOp, preVerificationGas };

    let hash = await wallet.hashFunction(userOp);
    const signedMessage = await owner.signMessage(ethers.toBeArray(hash));
    userOp = { ...userOp, signature: signedMessage };

    await entryPoint.verificationEnabledPayPrefund(userOp);
    balance = await entryPoint.balanceOf(await wallet.getAddress());
    expect(balance).to.equal(ethers.parseEther("0.0000000042"));
  });
  it("Test handleOps_v1 function", async function () {
    const { wallet, entryPoint, token, owner, otherAccount } =
      await loadFixture(deployContracts);

    let nonce = await wallet.getNonce();
    await token.transfer(await wallet.getAddress(), ethers.parseEther("100"));

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
      0,
      maxFeePerGas,
      maxPriorityFeePerGas
    );
    let preVerificationGas = await getPreVerificationGas(userOp);

    userOp = { ...userOp, preVerificationGas };

    let hash = await wallet.hashFunction(userOp);
    const signedMessage = await owner.signMessage(ethers.toBeArray(hash));
    userOp = { ...userOp, signature: signedMessage };

    await entryPoint.handleOps_v1(userOp);
    balance = await entryPoint.balanceOf(await wallet.getAddress());
    expect(await token.balanceOf(otherAccount.address)).to.equal(
      ethers.parseEther("10")
    );
  });
});
```

## Development

### NonceManager Contract

- **Storage Mapping**: The contract uses a mapping to store nonce values for each sender address and nonce key. This allows for efficient retrieval and updating of nonce values during transaction processing.
- **Nonce Calculation**: The `getNonce` function calculates the next valid nonce based on the sender's address and a provided key. This nonce is composed of the sequence number and the nonce key, ensuring uniqueness.
- **Nonce Increment**: The contract provides a function `incrementNonce` to manually increment the nonce for a sender. This functionality can be useful during contract initialization or for special cases where nonce adjustment is necessary.
- **Nonce Validation**: The `_validateAndUpdateNonce` function validates the uniqueness of a nonce for a given sender and nonce value. This validation is essential for ensuring that nonces are incremented correctly and that transactions are processed securely.

Create a `contracts/common/NonceManager.sol` contract.

```javascript
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract NonceManager {
    /**
     * The next valid sequence number for a given nonce key.
     */
    mapping(address => mapping(uint192 => uint256)) public nonceSequenceNumber;

    function getNonce(
        address sender,
        uint192 key
    ) public view returns (uint256 nonce) {
        return nonceSequenceNumber[sender][key] | (uint256(key) << 64);
    }

    // allow an account to manually increment its own nonce.
    // (mainly so that during construction nonce can be made non-zero,
    // to "absorb" the gas cost of first nonce increment to 1st transaction (construction),
    // not to 2nd transaction)
    function incrementNonce(uint192 key) public {
        nonceSequenceNumber[msg.sender][key]++;
    }

    /**
     * validate nonce uniqueness for this account.
     * called just after validateUserOp()
     */
    function _validateAndUpdateNonce(
        address sender,
        uint256 nonce
    ) internal returns (bool) {
        uint192 key = uint192(nonce >> 64);
        uint64 seq = uint64(nonce);
        return nonceSequenceNumber[sender][key]++ == seq;
    }
}

```

### StakeManager Contract

- **Deposit Management**: The contract includes functions for depositing funds (receive and depositTo) into the contract. Users can send Ether to the contract, and their deposit balances are updated accordingly.
- **Balance Retrieval**: The `balanceOf` function allows users to retrieve their deposit balances stored in the StakeManager contract. This functionality enables users to monitor their available funds for gas payment.
- **Deposit Increment**: The `_incrementDeposit` function is used internally to increment the deposit balance for a given account. It ensures that deposit amounts are updated correctly and that potential overflow conditions are prevented.
- **Gas Payment Integration**: The StakeManager contract can be integrated with other contracts or systems to handle gas payment automatically. Contracts can query the StakeManager contract for available deposit balances and deduct gas fees as needed.
  Create a `contracts\common\StakeManager.sol` contract

```javascript
/**
 ** Account-Abstraction (EIP-4337) singleton EntryPoint implementation.
 ** Only one instance required on each chain.
 **/
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

contract StakeManager {
    /// maps paymaster to their deposits and stakes
    mapping(address => uint256) public deposits;

    /// return the deposit (for gas payment) of the account
    function balanceOf(address account) public view returns (uint256) {
        return deposits[account];
    }

    receive() external payable {
        uint256 newDeposit = deposits[msg.sender] + msg.value;
        deposits[msg.sender] = newDeposit;
    }

    /**
     * add to the deposit of the given account
     */
    function depositTo(address account) public payable {
        uint256 initBal = deposits[account];
        uint256 balance = initBal + uint256(msg.value);
        deposits[account] = balance;
    }

    function _incrementDeposit(address account, uint256 amount) internal {
        uint256 deposit = deposits[account];
        uint256 newAmount = deposit + amount;
        require(newAmount <= type(uint112).max, "deposit overflow");
        deposits[account] = newAmount;
    }
}

```

### UserOpV4 Structures

The `contracts/structure/UserOpV4.sol` file defines two important data structures used in smart contract operations: MemoryUserOp and UserOpInfo.

- **MemoryUserOp**: Defines parameters for a user operation, including gas limits, fees, and sender information.
- **UserOpInfo**: Aggregates data related to a user operation, such as operation parameters, hash, prefund, and gas consumption.

```javascript
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
```

### EntrypointV4

The `contracts/04_EntryPointV4.sol` contract serves as the main entry point for executing user operations within the system. It imports several libraries and contracts to manage nonces, stakes, and user operations.

The `handleOps_v1` function, although currently mocked, will eventually execute user operations. It verifies and calculates gas and prefunds required for the operation by calling the `verifyCalculateGasAndPrefund` function. After validation, it attempts to execute the user operation by calling the call function, which invokes the target contract with the specified parameters.

The `verificationEnabledPayPrefund` function is responsible for verifying user operation calculations, including gas and prefunds, and initiating the transaction. It ensures that the sender has sufficient funds to cover the operation and validates the user's signature before initiating the transaction.

These functions play crucial roles in the execution and validation of user operations, ensuring the security and integrity of the system.

### WalletV4 Contract

Lets create a `contracts/04_WalletV4.sol` contract, we've introduced several enhancements to our wallet contract:

1. EntryPoint Integration:
   - We added an immutable private variable `_entryPoint` to store the address of the EntryPoint contract.
   - Implemented modifiers `_requireFromEntryPoint` and `_requireFromEntryPointOrOwner` to ensure that certain functions can only be called by the EntryPoint or the owner.
   - The constructor now takes an additional parameter `anEntryPoint`, allowing the setting of the EntryPoint address during contract deployment.
   - Added a getter function `entryPoint()` to retrieve the EntryPoint address.

```javascript
  ...
  IEntryPoint private immutable _entryPoint;
  ...
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
 ...
```

2. EntryPoint Interactions:
   - Implemented functions `getNonce()`, `getDeposit()`, `addDeposit()`, and `withdrawDepositTo()`.
   - `getNonce()` retrieves the nonce for the wallet from the `EntryPoint`.
   - `getDeposit()` returns the deposit balance of the wallet held by the `EntryPoint`.
   - `addDeposit()` allows the wallet to add funds to its deposit on the `EntryPoint`.
   - `withdrawDepositTo()` enables the owner to withdraw funds from the `EntryPoint` deposit to a specified address.

```javascript
   ...
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
   ...
```

3. Transaction Verification and Execution:
   - Introduced the function `_validateNonce(uint256 nonce)` to verify the nonce (not fully implemented in this iteration).
   - Added the `_payPrefund(uint256 missingAccountFunds)` function, allowing the wallet to pay gas fees to the `EntryPoint`. This function is meant to be a private function at the end.
   - `Implemented validateUserOp()` and `validateSignatureAndSend()` functions to validate user operations and execute them.
   - `validateUserOp()` verifies the signature, nonce (placeholder), and funds before executing the operation.
   - `validateSignatureAndSend()` performs similar validation but also executes the operation.

```javascript
   ...
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

    ...

    function validateSignatureAndSend(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData) {
        validationData = _validateSignature(userOp, userOpHash);
        _validateNonce(userOp.nonce);
        _payPrefund(missingAccountFunds);
    }
   ...
```

for this iteration we are focusing on the functions such as `_payPrefund` that enables the wallet to pay gas to the entrypoint, the `_payPrefund` in next iterations will be a private fundtion and will be called by a function `validateUserOp` which also cchecks the signature, Nonce and the sender being an entrypoint. lets skip the nonce verification for this iteration but keep a placeholder there. The another caller for the `_payPrefund` function will be `validateSignatureAndSend` that will provide a simmilar functionality with an execute option. The major difference in `validateUserOp` and `validateSignatureAndSend` is the ability to just verify and verify and execute, the entrypoint at any time can use the verification for making sure the transaction is not going to fail before sending it as an actual transaction.

## Conclusion

### What we have accomplished

This iteration of our smart contract wallet focused on significantly bolstering transaction verification, a crucial step in ensuring user security. We achieved this by integrating a new component called the EntryPoint contract. This innovative addition acts as a secure intermediary between external accounts and the wallet itself. Additionally, we implemented access control modifiers to further tighten security. While the groundwork for transaction validation and execution is laid, there's one missing piece we'll address next: nonce verification.

### What's Next? Addressing Remaining Gaps

While we've made significant progress, there's always room for improvement. Here's what we'll tackle next:

- **Implementing Nonce Verification**: We'll fully integrate nonce verification within the EntryPoint contract to eliminate the security vulnerability of replay attacks.
- **Compensating Relayers**: We'll introduce a function to ensure transaction relayers (bundlers) are appropriately compensated for their gas costs incurred during transaction execution.

By addressing these limitations and continuously refining our wallet contract, we're building a secure and user-friendly platform for the exciting world of Decentralized Finance (DeFi). Stay tuned as we explore new functionalities and push the boundaries of what's possible!

## References

1. [Interfaces](contracts/interface)
2. [WalletV4.sol](contracts/04_WalletV4.sol)
3. [EntryPointV4](contracts/04_EntryPointV4.sol)
