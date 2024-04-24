# Laying the Foundation: Iteration 1 of Our Smart Contract Wallet

Our Smart Contract Wallet development begins! This initial iteration focuses on establishing a core structure with basic functionalities for holding and transferring tokens. We'll delve into the key components, the challenges addressed, and the road ahead in subsequent iterations.

## Tests

Test-driven development (TDD) forms the cornerstone of our development methodology. By writing comprehensive test cases using the Hardhat testing framework, we ensure the reliability and correctness of our Smart Contract Wallet. Our test suite includes scenarios such as deploying the wallet and token contracts, verifying wallet token balances, and executing token transfers.

1.  The `deployWallet()` function is pivotal, deploying both the wallet and token contracts. Additionally, it initializes signing entities and transfers tokens to the wallet. Our test suite validates these actions:

- **Deployment Test**: Verifies the successful deployment of both contracts.
- **Token Balances**: Ensures the wallet holds the expected token balance.
- **Token Transfers**: Ensures token transfer to the correct entities from the token owner.

```javascript
async function deployWallet() {
  // Contracts are deployed using the first signer/account by default
  const [owner, otherAccount] = await ethers.getSigners();

  const Token = await ethers.getContractFactory("Token");
  const token = await Token.deploy(owner.address);
  await token.waitForDeployment();

  const Wallet = await ethers.getContractFactory("WalletV1");
  const wallet = await Wallet.deploy(owner.address);
  await wallet.waitForDeployment();

  await token.transfer(await wallet.getAddress(), ethers.parseEther("100"));

  return { token, wallet, owner, otherAccount };
}
```

2. Lets write our test cases:

   - **Test Case 1**: Deploy Wallet and Token Contracts  
     This test ensures that both the wallet and token contracts are successfully deployed. It verifies that the addresses of both contracts exist, indicating a successful deployment process.

   ```javascript
   it("Should Deploy wallet and token", async function () {
     const { token, wallet } = await loadFixture(deployWallet);
     expect(await token.getAddress()).to.exist;
     expect(await wallet.getAddress()).to.exist;
   });
   ```

   - **Test Case 2**: Calculate Wallet Token Balance  
     This test verifies that the wallet holds the expected token balance. It retrieves the token balance of the wallet address and checks if it matches the expected balance of 100 tokens.

   ```javascript
   it("Should Calculate wallet Token balance", async function () {
     const { token, wallet } = await loadFixture(deployWallet);
     let balance = await token.balanceOf(await wallet.getAddress());
     expect(balance).to.equal(ethers.parseEther("100"));
   });
   ```

   - **Test Case 3**: Invoke Token Transfer from Smart Contract Wallet  
     This test validates the functionality of token transfer from the smart contract wallet. It executes a token transfer transaction from the wallet to another account (otherAccount). After the transfer, it checks if the balance of otherAccount has increased by 100 tokens and if the wallet's balance has decreased to 0 tokens.

   ```javascript
   it("Invoke token transfer from the smart contract wallet", async function () {
     const { token, wallet, owner, otherAccount } = await loadFixture(
       deployWallet
     );

     const transferData = token
       .connect(owner)
       .interface.encodeFunctionData("transfer", [
         otherAccount.address,
         ethers.parseEther("100"),
       ]);
     await wallet.execute(await token.getAddress(), 0, transferData);
     let balance = await token.balanceOf(otherAccount.address);
     let walletBalance = await token.balanceOf(await wallet.getAddress());
     expect(balance).to.equal(ethers.parseEther("100"));
     expect(walletBalance).to.equal(0);
   });
   ```

   These test cases ensure the correctness and functionality of essential operations in the smart contract wallet. By thoroughly testing deployment, balance calculation, and token transfers, we validate the reliability of our smart contract implementation.

## Development

### Token Contract

1. Lets create a `contracts/common/Token.sol` contract using `@openzeppelin` contracts. This contract is going to be the base token contract that is tested to be transfered by smart contract wallet.

```javascript
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Token is ERC20, Ownable {
    constructor(
        address initialOwner
    ) ERC20("TestToken", "TTK") Ownable(initialOwner) {
        _mint(initialOwner, 5000 * (10 ** uint256(decimals())));
    }
}
```

### WalletV1 Contract

2. Lets create a `contracts/01_WalletV1.sol`, here, we delve into the implementation of a basic smart contract wallet named `WalletV1`. This contract enables users to execute transactions securely and efficiently. The `execute` function allows the contract owner to trigger transactions to other contracts. Meanwhile, the `_call` function internally executes the specified transaction, handling any errors that may occur during execution.

```javascript
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract WalletV1 is Ownable {
    constructor(address _admin) Ownable(_admin) {}

    function execute(
        address _target,
        uint256 _value,
        bytes calldata _calldata
    ) external onlyOwner {
        _call(_target, _value, _calldata);
    }

    function _call(
        address _target,
        uint256 value,
        bytes memory _calldata
    ) internal {
        (bool success, bytes memory result) = _target.call{value: value}(
            _calldata
        );
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
```

## Conclusion

### What we have accomplished

We've taken a monumental step – our initial Smart Contract Wallet is live! This first iteration lays the groundwork for seamless blockchain transactions. Here's what we've achieved:

- The Power of Decentralized Transactions: Our wallet empowers users to conduct transactions directly on the blockchain, eliminating the need for intermediaries.
- Token Transfers Made Easy: We've established a foundation for token transfers conducted directly through the Smart Contract Wallet.
- Confidence Through Testing: By crafting rigorous test cases, we've verified essential functionalities:
  - Successful deployment of both wallet and token contracts.
  - Accurate reflection of token balances within the wallet.
  - Flawless execution of token transfers initiated from the smart contract wallet.

### Beyond the First Milestone: Addressing Limitations

While this initial version represents a significant milestone, there's room for improvement. Currently, only the wallet owner can initiate transactions. This limitation effectively creates a two-wallet scenario: one for tokens and one for Ether (the native blockchain currency). This necessitates users to manage separate accounts, hindering the overall user experience.

### The Road Ahead: Empowering Users and Minimizing Costs

Our next challenge lies in overcoming this design flaw. We aim to create a system where users can not only sign transactions but also pass them to a relayer account. This relayer, incentivized through the system, will execute the transaction, eliminating the need for users to maintain an externally-owned account (EOA) solely for gas fees (transaction costs on the blockchain).

### The Role of Relayers (Bundlers):

The relayer accounts we mentioned can be likened to bundlers. Bundlers act as facilitators, grouping multiple transactions into a single package before submitting them to the blockchain for processing. This process enhances efficiency by reducing transaction fees and saving valuable space on the blockchain.

### Stay Tuned: The Evolution Continues!

This is just the beginning of our Smart Contract Wallet's journey. As we refine and expand its functionalities, we unlock new possibilities for the realm of decentralized finance. Stay tuned for further progress reports as we push the boundaries of innovation!

## References

1. [Token.sol](contracts/common/Token.sol)
2. [WalletV1.sol](contracts/01_WalletV1.sol)
3. [Test file](test/01_WalletV1.test.js)
