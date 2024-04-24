const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  getUserOp,
  encodeUserOpCallDataAndGasLimit,
  getGasFee,
  getPreVerificationGas,
} = require("../utils/helpers");

describe("Wallet-V3", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployWallet() {
    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccount, anotherAccount] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("Token");
    const token = await Token.deploy(owner.address);
    await token.waitForDeployment();

    const Wallet = await ethers.getContractFactory("WalletV3");
    const wallet = await Wallet.deploy(owner.address);
    await wallet.waitForDeployment();

    await token.transfer(await wallet.getAddress(), ethers.parseEther("100"));

    return { token, wallet, owner, otherAccount, anotherAccount };
  }

  describe("Deployment", function () {
    it("Should Deploy wallet and token", async function () {
      const { token, wallet } = await loadFixture(deployWallet);
      expect(await token.getAddress()).to.exist;
      expect(await wallet.getAddress()).to.exist;
    });
    it("Should validate owner's signature", async function () {
      const { token, wallet, owner, otherAccount } = await loadFixture(
        deployWallet
      );
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
            ethers.parseEther("100"),
          ]),
        }
      );
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
      let preVerificationGas = await getPreVerificationGas(userOp);
      userOp = { ...userOp, preVerificationGas, callGasLimit };
      let hash = await wallet.hashFunction(userOp);
      const signedMessage = await owner.signMessage(ethers.toBeArray(hash));
      userOp = { ...userOp, signature: signedMessage };
      expect(await wallet._validateSignature(userOp, hash)).not.to.be.reverted;
    });
  });
});
