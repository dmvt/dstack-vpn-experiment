require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.24",
  networks: {
    hardhat: {
      // Disable forking for now to avoid rate limiting issues
      // forking: {
      //   url: process.env.MAINNET_RPC_URL || "https://eth-mainnet.g.alchemy.com/v2/demo",
      //   blockNumber: 20000000, // Use a recent block for consistent testing
      // },
      accounts: {
        mnemonic: "test test test test test test test test test test test junk",
        count: 10,
      },
    },
    base: {
      url: process.env.BASE_RPC_URL || "https://mainnet.base.org",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    baseSepolia: {
      url: process.env.BASE_SEPOLIA_RPC_URL || "https://sepolia.base.org",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  mocha: {
    timeout: 40000,
  },
}; 