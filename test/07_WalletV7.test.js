const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");

const {
  getUserOp,
  encodeUserOpCallDataAndGasLimit,
  getGasFee,
  getPreVerificationGas,
} = require("../utils/helpers");

const abiCoder = new ethers.AbiCoder();

describe("Wallet-V7", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployContracts() {
    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccount, anotherAccount] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("Token");
    const token = await Token.deploy(owner.address);
    await token.waitForDeployment();

    const EntryPoint = await ethers.getContractFactory("EntryPointV6");
    const entryPoint = await EntryPoint.deploy();
    await entryPoint.waitForDeployment();
    const Wallet = await ethers.getContractFactory("WalletV6");
    const wallet = await Wallet.deploy(
      owner.address,
      await entryPoint.getAddress()
    );
    await wallet.waitForDeployment();
    const Paymaster = await ethers.getContractFactory("VerifyingPaymasterV7");
    const paymaster = await Paymaster.deploy(
      await entryPoint.getAddress(),
      owner.address
    );
    await paymaster.waitForDeployment();
    await owner.sendTransaction({
      to: await wallet.getAddress(),
      value: ethers.parseEther("1"),
    });
    await owner.sendTransaction({
      to: await paymaster.getAddress(),
      value: ethers.parseEther("1"),
    });
    await paymaster.addDeposit({ value: ethers.parseEther("0.5") });
    await token.transfer(await wallet.getAddress(), ethers.parseEther("100"));

    return {
      token,
      wallet,
      paymaster,
      entryPoint,
      owner,
      otherAccount,
      anotherAccount,
    };
  }

  describe("Deployment", function () {
    it("Should Deploy wallet, token, paymaster and entrypoint", async function () {
      const { token, wallet, entryPoint, paymaster } = await loadFixture(
        deployContracts
      );
      expect(await token.getAddress()).to.exist;
      expect(await wallet.getAddress()).to.exist;
      expect(await entryPoint.getAddress()).to.exist;
      expect(await paymaster.getAddress()).to.exist;
    });
  });
  describe("Test paymaster", function () {
    it("Test paymaster parsePaymasterAndData", async function () {
      const { token, wallet, paymaster, stakeManager, entryPoint } =
        await loadFixture(deployContracts);
      const MOCK_VALID_UNTIL = "0x00000000deadbeef";
      const MOCK_VALID_AFTER = "0x0000000000001234";
      const MOCK_SIG = "0x1234";
      const paymasterAndData = ethers.concat([
        await paymaster.getAddress(),
        abiCoder.encode(
          ["uint48", "uint48"],
          [MOCK_VALID_UNTIL, MOCK_VALID_AFTER]
        ),
        MOCK_SIG,
      ]);
      const res = await paymaster.parsePaymasterAndData(paymasterAndData);
      expect(res.validUntil).to.be.equal(BigInt(MOCK_VALID_UNTIL));
    });
    it("Test paymaster validation", async function () {
      const { token, wallet, paymaster, stakeManager, entryPoint, owner } =
        await loadFixture(deployContracts);
      const MOCK_VALID_UNTIL = "0x00000000deadbeef";
      const MOCK_VALID_AFTER = "0x0000000000001234";
      const MOCK_SIG = "0x1234";
      const paymasterAndData = ethers.concat([
        await paymaster.getAddress(),
        abiCoder.encode(
          ["uint48", "uint48"],
          [MOCK_VALID_UNTIL, MOCK_VALID_AFTER]
        ),
        MOCK_SIG,
      ]);
      let op = {
        ...getUserOp(
          await wallet.getAddress(),
          0,
          "0xb61d27f60000000000000000000000005fbdb2315678afecb367f032d93f642f64180aa3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000044a9059cbb00000000000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c80000000000000000000000000000000000000000000000008ac7230489e8000000000000000000000000000000000000000000000000000000000000",
          60404,
          100000,
          40936,
          1715370539,
          619287127
        ),
        paymasterAndData: "0x",
      };
      const hash = await paymaster.getHash(
        op,
        MOCK_VALID_UNTIL,
        MOCK_VALID_AFTER
      );
      const signedMessage = await owner.signMessage(ethers.toBeArray(hash));
      const paymasterData = ethers.concat([
        await paymaster.getAddress(),
        abiCoder.encode(
          ["uint48", "uint48"],
          [MOCK_VALID_UNTIL, MOCK_VALID_AFTER]
        ),
        signedMessage,
      ]);
      let result = await paymaster._validatePaymasterUserOp(
        { ...op, paymasterAndData: paymasterData },
        ethers.parseEther("1")
      );
    });
    it("Test verify, call and execute userop with paymaster 0x", async function () {
      const { token, wallet, entryPoint, owner, otherAccount } =
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
      let hash = await wallet.hashFunction(userOp);
      let { chainId } = await ethers.provider.getNetwork();

      const codedData = abiCoder.encode(
        ["bytes32", "address", "uint256"],
        [hash, await entryPoint.getAddress(), chainId]
      );
      let encodedData = ethers.keccak256(codedData);
      const signedMessage = await owner.signMessage(
        ethers.toBeArray(encodedData)
      );
      userOp = { ...userOp, signature: signedMessage };
      await expect(
        entryPoint
          .connect(otherAccount)
          .simulateHandleOp(userOp, userOp.sender, userOp.callData)
      )
        .to.be.revertedWithCustomError(entryPoint, "ExecutionResult")
        .withArgs(anyValue, anyValue, 0, anyValue, true, anyValue);

      const txn = await entryPoint
        .connect(otherAccount)
        .handleOps(userOp, otherAccount.address);
      txn.wait();
      expect(await token.balanceOf(otherAccount.address)).to.equal(
        ethers.parseEther("10")
      );
    });
    it("Test should not verify, call and execute userop with paymaster 0x", async function () {
      const { token, wallet, entryPoint, owner, otherAccount } =
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
      let hash = await wallet.hashFunction(userOp);
      let { chainId } = await ethers.provider.getNetwork();

      const codedData = abiCoder.encode(
        ["bytes32", "address", "uint256"],
        [hash, await entryPoint.getAddress(), chainId]
      );
      let encodedData = ethers.keccak256(codedData);
      const signedMessage = await owner.signMessage(
        ethers.toBeArray(encodedData)
      );
      userOp = {
        ...userOp,
        signature: signedMessage,
        nonce: userOp.nonce + BigInt("1"),
      };
      await expect(
        entryPoint
          .connect(otherAccount)
          .simulateHandleOp(userOp, userOp.sender, userOp.callData)
      )
        .to.be.revertedWithCustomError(entryPoint, "FailedOp")
        .withArgs(anyValue, anyValue);
    });
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
      const signedMessage = await owner.signMessage(
        ethers.toBeArray(encodedData)
      );
      const paymasterAndData = ethers.concat([
        await paymaster.getAddress(),
        abiCoder.encode(
          ["uint48", "uint48"],
          [MOCK_VALID_UNTIL, MOCK_VALID_AFTER]
        ),
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
  });
});
