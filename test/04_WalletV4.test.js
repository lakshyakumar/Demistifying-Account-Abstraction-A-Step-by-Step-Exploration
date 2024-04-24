const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

const {
  getUserOp,
  encodeUserOpCallDataAndGasLimit,
  getGasFee,
  getPreVerificationGas,
} = require("../utils/helpers");

describe("Wallet-V4", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployContracts() {
    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccount, anotherAccount] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("Token");
    const token = await Token.deploy(owner.address);
    await token.waitForDeployment();

    const EntryPoint = await ethers.getContractFactory("EntryPointV4");
    const entryPoint = await EntryPoint.deploy();
    await entryPoint.waitForDeployment();
    const Wallet = await ethers.getContractFactory("WalletV4");
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
    it("Test sending Ether to Entrypoint", async function () {
      const { wallet, entryPoint, owner } = await loadFixture(deployContracts);
      let balance = await ethers.provider.getBalance(await wallet.getAddress());
      expect(balance).to.equal(ethers.parseEther("1"));
      await entryPoint.callWalletsPayPrefund(await wallet.getAddress());
      balance = await entryPoint.balanceOf(await wallet.getAddress());
      expect(balance).to.equal(ethers.parseEther("0.0000000042"));
    });
  });
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
    it("Test handleOps_v1 function with another EoA", async function () {
      const { wallet, entryPoint, token, owner, otherAccount, oneMoreAccount } =
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
        maxFeePerGas,
        maxPriorityFeePerGas
      );

      let preVerificationGas = await getPreVerificationGas(userOp);

      userOp = { ...userOp, preVerificationGas };

      let hash = await wallet.hashFunction(userOp);
      const signedMessage = await owner.signMessage(ethers.toBeArray(hash));
      userOp = { ...userOp, signature: signedMessage };

      await entryPoint.connect(otherAccount).handleOps_v1(userOp);
      expect(await token.balanceOf(otherAccount.address)).to.equal(
        ethers.parseEther("10")
      );
    });
  });
});
