const WalletContract = require("../artifacts/contracts/04_WalletV4.sol/WalletV4.json");
const { ethers } = require("hardhat");
let abi = WalletContract.abi;

let overheads;
const abiCoder = new ethers.AbiCoder();
const validateUserOpMethod = "_validateSignature";
const userOpType = {
  components: [
    {
      type: "address",
      name: "sender",
    },
    {
      type: "uint256",
      name: "nonce",
    },
    {
      type: "bytes",
      name: "callData",
    },
    {
      type: "uint256",
      name: "callGasLimit",
    },
    {
      type: "uint256",
      name: "verificationGasLimit",
    },
    {
      type: "uint256",
      name: "preVerificationGas",
    },
    {
      type: "uint256",
      name: "maxFeePerGas",
    },
    {
      type: "uint256",
      name: "maxPriorityFeePerGas",
    },
    {
      type: "bytes",
      name: "signature",
    },
  ],
  name: "userOp",
  type: "tuple",
};

const DefaultGasOverheads = {
  fixed: 21000,
  perUserOp: 18300,
  perUserOpWord: 4,
  zeroByte: 4,
  nonZeroByte: 16,
  bundleSize: 1,
  sigSize: 65,
};

let getUserOp = (
  senderAddress,
  nonce,
  callData = "0x",
  callGasLimit = 0,
  verificationGasLimit = 21000,
  preVerificationGas = 0,
  maxFeePerGas = 200000,
  maxPriorityFeePerGas = 0
) => ({
  sender: senderAddress,
  nonce,
  callData,
  callGasLimit,
  verificationGasLimit,
  preVerificationGas,
  maxFeePerGas,
  maxPriorityFeePerGas,
  signature: "0x",
});

const UserOpType = (abi) => {
  return (_a = abi.find((entry) => entry.name === validateUserOpMethod)) ===
    null || _a === void 0
    ? void 0
    : _a.inputs[0];
};

function parseNumber(a) {
  if (a == null || a === "") return null;
  return a;
}

function encode(typevalues, forSignature) {
  const types = typevalues.map((typevalue) =>
    typevalue.type === "bytes" && forSignature ? "bytes32" : typevalue.type
  );
  const values = typevalues.map((typevalue) =>
    typevalue.type === "bytes" && forSignature
      ? (0, ethers.keccak256)(typevalue.val)
      : typevalue.val
  );

  return abiCoder.encode(types, values);
}

function packUserOp(op, forSignature = true) {
  if (forSignature) {
    // lighter signature scheme (must match UserOperation#pack): do encode a zero-length signature, but strip afterwards the appended zero-length value

    let encoded = ethers.defaultAbiCoder.encode(
      [userOpType],
      [Object.assign(Object.assign({}, op), { signature: "0x" })]
    );
    // remove leading word (total length) and trailing word (zero-length signature)
    encoded = "0x" + encoded.slice(66, encoded.length - 64);
    return encoded;
  }
  const typevalues = UserOpType(abi).components.map((c) => ({
    type: c.type,
    val: op[c.name],
  }));
  return encode(typevalues, forSignature);
}

function calcPreVerificationGas(userOp, overheads) {
  const ov = Object.assign(
    Object.assign({}, DefaultGasOverheads),
    overheads !== null && overheads !== void 0 ? overheads : {}
  );
  const p = Object.assign(
    {
      // dummy values, in case the UserOp is incomplete.
      preVerificationGas: 21000,
      signature: (0, ethers.hexlify)(Buffer.alloc(ov.sigSize, 1)),
    },
    userOp
  );
  const packed = (0, ethers.toBeArray)((0, packUserOp)(p, false));
  const lengthInWord = (packed.length + 31) / 32;
  const callDataCost = packed
    .map((x) => (x === 0 ? ov.zeroByte : ov.nonZeroByte))
    .reduce((sum, x) => sum + x);
  const ret = Math.round(
    callDataCost +
      ov.fixed / ov.bundleSize +
      ov.perUserOp +
      ov.perUserOpWord * lengthInWord
  );
  return ret;
}

/**
 * should cover cost of putting calldata on-chain, and some overhead.
 * actual overhead depends on the expected bundle size
 */
const getPreVerificationGas = async (userOp) => {
  const p = await (0, ethers.resolveProperties)(userOp);
  return (0, calcPreVerificationGas)(p, overheads);
};

const getGasFee = async (provider) => {
  const verificationGasLimit = 100000;
  if (network.config.chainId === 31337) {
    let block = await provider.getBlock("latest");
    let tip = block.baseFeePerGas;
    const buffer = (tip / BigInt("100")) * BigInt("13");
    const maxPriorityFeePerGas = tip + buffer;
    const maxFeePerGas = block.baseFeePerGas
      ? block.baseFeePerGas * BigInt("2") + maxPriorityFeePerGas
      : maxPriorityFeePerGas;

    return { maxFeePerGas, maxPriorityFeePerGas, verificationGasLimit };
  }
  const [fee, block] = await Promise.all([
    provider.send("eth_maxPriorityFeePerGas", []),
    provider.getBlock("latest"),
  ]);
  const tip = ethers.BigNumber.from(fee);
  const buffer = tip.div(100).mul(13);
  const maxPriorityFeePerGas = tip.add(buffer);
  const maxFeePerGas = block.baseFeePerGas
    ? block.baseFeePerGas.mul(2).add(maxPriorityFeePerGas)
    : maxPriorityFeePerGas;

  return { maxFeePerGas, maxPriorityFeePerGas, verificationGasLimit };
};
const encodeExecute = async (contract, target, value, data) => {
  return contract.interface.encodeFunctionData("execute", [
    target,
    value,
    data,
  ]);
};
const encodeUserOpCallDataAndGasLimit = async (
  wallet,
  owner,
  detailsForUserOp
) => {
  var _a, _b;
  const value =
    (_a = parseNumber(detailsForUserOp.value)) !== null && _a !== void 0
      ? _a
      : BigInt("0");
  const callData = await encodeExecute(
    wallet,
    detailsForUserOp.target,
    value,
    detailsForUserOp.data
  );
  const callGasLimit =
    (_b = parseNumber(detailsForUserOp.gasLimit)) !== null && _b !== void 0
      ? _b
      : await ethers.provider.estimateGas({
          from: owner.address,
          to: await wallet.getAddress(),
          data: callData,
        });
  return {
    callData,
    callGasLimit,
  };
};

module.exports = {
  getUserOp,
  UserOpType,
  getGasFee,
  getPreVerificationGas,
  calcPreVerificationGas,
  packUserOp,
  encode,
  parseNumber,
  encodeUserOpCallDataAndGasLimit,
};
