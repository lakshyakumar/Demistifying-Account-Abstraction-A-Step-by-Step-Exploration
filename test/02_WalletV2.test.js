const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

describe("Wallet-V2", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployWallet() {
    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccount, anotherAccount] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("Token");
    const token = await Token.deploy(owner.address);
    await token.waitForDeployment();

    const Wallet = await ethers.getContractFactory("WalletV2");
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
    it("Should transfer tokens when owner signs the transaction", async function () {
      const { token, wallet, owner, otherAccount } = await loadFixture(
        deployWallet
      );

      const transferData = token
        .connect(owner)
        .interface.encodeFunctionData("transfer", [
          otherAccount.address,
          ethers.parseEther("100"),
        ]);

      let messageHash = await wallet.getMessageHash(
        await token.getAddress(),
        0,
        transferData
      );

      const signedMessage = await owner.signMessage(
        ethers.toBeArray(messageHash)
      );
      await wallet.execute({
        target: await token.getAddress(),
        value: 0,
        _calldata: transferData,
        signature: signedMessage,
      });
      let balance = await token.balanceOf(otherAccount.address);
      let walletBalance = await token.balanceOf(await wallet.getAddress());
      expect(balance).to.equal(ethers.parseEther("100"));
      expect(walletBalance).to.equal(0);
    });
    it("Transfer tokens when the owner signs the transaction, regardless of the sender", async function () {
      const { token, wallet, owner, otherAccount, anotherAccount } =
        await loadFixture(deployWallet);

      const transferData = token
        .connect(owner)
        .interface.encodeFunctionData("transfer", [
          otherAccount.address,
          ethers.parseEther("100"),
        ]);
      let messageHash = await wallet.getMessageHash(
        await token.getAddress(),
        0,
        transferData
      );
      const signedMessage = await owner.signMessage(
        ethers.toBeArray(messageHash)
      );
      await wallet.connect(anotherAccount).execute({
        target: await token.getAddress(),
        value: 0,
        _calldata: transferData,
        signature: signedMessage,
      });
      let balance = await token.balanceOf(otherAccount.address);
      let walletBalance = await token.balanceOf(await wallet.getAddress());
      expect(balance).to.equal(ethers.parseEther("100"));
      expect(walletBalance).to.equal(0);
    });
  });
});
