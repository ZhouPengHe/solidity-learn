import { ethers, upgrades, network } from "hardhat";
import * as fs from "fs";

async function main() {
	const [deployer] = await ethers.getSigners();
	console.log(`Deployer: ${deployer.address} Network: ${network.name}`);

	// 1) 部署 NFT 可升级合约
	const NFT = await ethers.getContractFactory("NFTUpgradeable");
	const nft = await upgrades.deployProxy(NFT, ["DemoNFT", "DNFT", process.env.NFT_BASE_URI || ""], { initializer: "initialize" });
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

	// 4) 设置价格预言机（可选）
	const ethUsd = process.env.CHAINLINK_ETH_USD || "";
	if (ethUsd) {
		const tx = await factory.setAuctionPriceFeed(await factory.getAddress(), ethers.ZeroAddress, ethUsd);
		await tx.wait();
		console.log("Factory owner set ETH/USD feed via factory method");
	}

	// 输出到文件
	const out = {
		network: network.name,
		NFTProxy: await nft.getAddress(),
		AuctionImplementation: await implementation.getAddress(),
		AuctionFactory: await factory.getAddress(),
	};
	fs.writeFileSync("deploy-output.json", JSON.stringify(out, null, 2));
	console.log("Saved deploy-output.json");
}

main().catch((e) => {
	console.error(e);
	process.exit(1);
});


