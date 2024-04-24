const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

const {
  getUserOp,
  encodeUserOpCallDataAndGasLimit,
  getGasFee,
  getPreVerificationGas,
} = require("../utils/helpers");

describe("Wallet-V5", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployContracts() {
    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccount, anotherAccount] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("Token");
    const token = await Token.deploy(owner.address);
    await token.waitForDeployment();

    const EntryPoint = await ethers.getContractFactory("EntryPointV5");
    const entryPoint = await EntryPoint.deploy();
    await entryPoint.waitForDeployment();
    const Wallet = await ethers.getContractFactory("WalletV5");
    const wallet = await Wallet.deploy(
      owner.address,
      await entryPoint.getAddress()
    );
    await wallet.waitForDeployment();
    await owner.sendTransaction({
      to: await wallet.getAddress(),
      value: ethers.parseEther("1"),
    });
    await token.transfer(await wallet.getAddress(), ethers.parseEther("100"));

    return {
      token,
      wallet,
      entryPoint,
      owner,
      otherAccount,
      anotherAccount,
    };
  }

  describe("Deployment", function () {
    it("Should Deploy wallet, token and entrypoint", async function () {
      const { token, wallet, entryPoint } = await loadFixture(deployContracts);
      expect(await token.getAddress()).to.exist;
      expect(await wallet.getAddress()).to.exist;
      expect(await entryPoint.getAddress()).to.exist;
    });
  });
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
});
