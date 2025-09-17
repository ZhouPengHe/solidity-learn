require("@chainlink/env-enc").config();

require("@nomicfoundation/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-deploy");
require("solidity-coverage");

const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL || "";
const PRIVATE_KEY = process.env.PRIVATE_KEY || "";

/**
 * Hardhat 配置：
 * - Solidity 编译器 0.8.24，开启优化
 * - 集成 hardhat-deploy，定义 namedAccounts
 * - 配置 sepolia 测试网络（从 .env 读取）
 */
module.exports = {
	solidity: {
		version: "0.8.24",
		settings: {
			optimizer: { enabled: true, runs: 200 },
		},
	},
	defaultNetwork: "hardhat",
	networks: {
		sepolia: {
			url: SEPOLIA_RPC_URL,
			accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
		},
	},
	paths: {
		sources: "contracts",
		artifacts: "artifacts",
		cache: "cache",
	},
	mocha: {
		timeout: 60000,
		reporter: "mocha-multi-reporters",
		reporterOptions: {
			reporterEnabled: "spec, mocha-junit-reporter, mochawesome",
			mochaJunitReporterReporterOptions: {
				mochaFile: "reports/junit.xml",
				toConsole: false,
			},
			mochawesomeReporterOptions: {
				reportDir: "reports/mochawesome",
				reportFilename: "report",
				quiet: true,
				overwrite: true,
				html: true,
				json: true,
			},
		},
	},
	// hardhat-deploy
	namedAccounts: {
		deployer: {
			default: 0,
		},
	},
};


