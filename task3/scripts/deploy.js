const { ethers, upgrades, network } = require("hardhat");

async function main() {
	const [deployer] = await ethers.getSigners();
	console.log(`Deployer: ${deployer.address} Network: ${network.name}`);

	// 1) 部署 NFT 可升级合约
	const NFT = await ethers.getContractFactory("NFTUpgradeable");
	const nft = await upgrades.deployProxy(
		NFT,
		["DemoNFT", "DNFT", process.env.NFT_BASE_URI || ""],
		{ initializer: "initialize" }
	);
	await nft.waitForDeployment();
	console.log("NFT proxy:", await nft.getAddress());

	// 2) 部署拍卖实现
	const Impl = await ethers.getContractFactory("AuctionImplementation");
	const implementation = await Impl.deploy();
	await implementation.waitForDeployment();
	console.log("Auction implementation:", await implementation.getAddress());

	// 3) 部署工厂
	const Factory = await ethers.getContractFactory("AuctionFactory");
	const factory = await Factory.deploy(await implementation.getAddress());
	await factory.waitForDeployment();
	console.log("Auction factory:", await factory.getAddress());
}

main().catch((e) => {
	console.error(e);
	process.exit(1);
});


