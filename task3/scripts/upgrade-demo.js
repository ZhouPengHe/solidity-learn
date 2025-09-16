const { ethers } = require("hardhat");

async function main() {
	const proxy = process.env.AUCTION_PROXY;
	if (!proxy) throw new Error("AUCTION_PROXY not set");

	const ImplV2 = await ethers.getContractFactory("AuctionImplementationV2");
	const v2 = await ImplV2.deploy();
	await v2.waitForDeployment();
	console.log("New impl V2:", await v2.getAddress());

	const factoryAddr = process.env.FACTORY_ADDR;
	if (!factoryAddr) throw new Error("FACTORY_ADDR not set");
	const factory = await ethers.getContractAt("AuctionFactory", factoryAddr);
	await (await factory.upgradeAuction(proxy, await v2.getAddress())).wait();
	console.log("Upgraded proxy:", proxy);
}

main().catch((e) => {
	console.error(e);
	process.exit(1);
});


