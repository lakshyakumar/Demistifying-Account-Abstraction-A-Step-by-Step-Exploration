const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");

describe("Wallet-V1", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
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

  describe("Deployment", function () {
    it("Should Deploy wallet and token", async function () {
      const { token, wallet } = await loadFixture(deployWallet);
      expect(await token.getAddress()).to.exist;
      expect(await wallet.getAddress()).to.exist;
    });
    it("Should Calculate wallet Token balance", async function () {
      const { token, wallet } = await loadFixture(deployWallet);
      let balance = await token.balanceOf(await wallet.getAddress());
      expect(balance).to.equal(ethers.parseEther("100"));
    });
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
  });
});
