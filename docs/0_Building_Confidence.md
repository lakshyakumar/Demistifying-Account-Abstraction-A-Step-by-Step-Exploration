# Building Confidence: Setting Up Your Smart Contract Testing Framework with Hardhat

This article equips you with the knowledge to set up a comprehensive testing framework for your blockchain project using Hardhat. Whether you're a seasoned developer or just starting your journey in this exciting space, robust testing is crucial for ensuring the security and functionality of your smart contracts.

## Setting Up the Hardhat Environment

Let's begin by establishing the foundation for your testing environment. We'll utilize Hardhat, a popular Ethereum development framework known for its user-friendliness and robust features.

1. Installation: Begin by installing Hardhat using npm:

```bash
npm install --save-dev hardhat
```

2. Project Initialization: Once installed, initiate a new JavaScript project using Hardhat's built-in command:

```bash
npx hardhat init
> Create a JavaScript project
```

3. **Dependencies**: Install the necessary dependencies for development and testing:

```bash
npm install --save-dev "hardhat@^2.12.7" "@nomicfoundation/hardhat-toolbox@^5.0.0"
```

4. OpenZeppelin Contracts: Integrate the OpenZeppelin library for access to pre-audited and secure smart contract functionalities:

```bash
// Get Openzeppelin contracts
npm install @openzeppelin/contracts
```

5. Verification: Verify the successful installation by running these commands:

```bash
npx hardhat --version
npx hardhat test
```

These commands should output the installed Hardhat version and run sample tests

**Housekeeping**: To ensure a clean slate for our tutorial, delete the existing files related to a potentially pre-existing Lock contract:

1. `contracts/Lock.sol`
2. `scripts/deploy.js`
3. `test/Lock.js`

**Solidity Version**: Double-check that your `hardhat.config.js` file specifies `solidity: "0.8.20"` to ensure compatibility with the code examples used throughout this guide.

### Demystifying Testing Scripts: A Practical Approach

Understanding the structure of test scripts is crucial for writing effective tests. This section will provide a step-by-step approach, assuming you're new to writing test scripts.

lets create a file `test/01_WalletV1.test.js`

- **loadFixture**: This function enables us to define a reusable setup for each test case. It ensures that every test starts with a clean environment and a consistent initial state.
- **deployWallet** function: This function, essential for each test case, is responsible for deploying and returning the required contracts needed for the specific tests.
- **describe blocks**: These blocks help organize your tests logically. Here, we have one describe block for the overall "Wallet-V1" functionality and a nested one for "Deployment" specifically.
- **it statements**: Each individual test case is defined within an it statement. These statements describe the specific behavior being tested along with the corresponding assertions using expect from Chai.
- **Test Case**: In the provided example, the test case ensures that the deployed token contract has an address after deployment.

```javascript
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");

describe("Wallet-V1", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployWallet() {
    // use this function to deploy and return the basic contracts required for the test cases
    return { token };
  }

  describe("Deployment", function () {
    it("Should Deploy wallet and token", async function () {
      const { token } = await loadFixture(deployWallet);
      expect(await token.getAddress()).to.exist;
    });
  });
});
```

**Running Your Tests**: Navigate to your project directory in the terminal and execute the following command to run your newly created test script:

```bash
npx hardhat test
```

## References

1. [Test File](test/01_WalletV1.test.js)
