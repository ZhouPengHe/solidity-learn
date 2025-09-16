const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("UUPS 升级演示", function () {
	it("将拍卖代理升级到 V2 且保持状态", async function () {
		const [deployer, seller] = await ethers.getSigners();

		// NFT（部署并给卖家铸造 1 个）
		const NFT = await ethers.getContractFactory("NFTUpgradeable");
		const nft = await upgrades.deployProxy(NFT, ["DemoNFT", "DNFT", "https://base/"], { initializer: "initialize" });
		await nft.waitForDeployment();
		await (await nft.safeMint(seller.address)).wait();
		const tokenId = 1;

		// 实现合约 V1 与工厂
		const ImplV1 = await ethers.getContractFactory("AuctionImplementation");
		const implV1 = await ImplV1.deploy();
		await implV1.waitForDeployment();
		const Factory = await ethers.getContractFactory("AuctionFactory");
		const factory = await Factory.deploy(await implV1.getAddress());
		await factory.waitForDeployment();

		// 创建拍卖
		await (await nft.connect(seller).approve(await factory.getAddress(), tokenId)).wait();
		const tx = await factory.connect(seller).createAuction(await nft.getAddress(), tokenId, 60, 1, ethers.ZeroAddress);
		const rc = await tx.wait();
		const evt = rc.logs.find((l) => l.fragment && l.fragment.name === "AuctionDeployed");
		const proxyAddr = evt.args[0];
		const auction = await ethers.getContractAt("AuctionImplementation", proxyAddr);

		// 设置喂价以允许出价
		const Mock = await ethers.getContractFactory("MockV3Aggregator");
		const ethFeed = await Mock.deploy(8, 2000n * 10n ** 8n);
		await ethFeed.waitForDeployment();
		await (await factory.setAuctionPriceFeed(proxyAddr, ethers.ZeroAddress, await ethFeed.getAddress())).wait();

		// 出一笔价以产生状态
		await (await auction.connect(deployer).bid(0, { value: ethers.parseEther("0.02") })).wait();

		// 部署 V2 实现
		const ImplV2 = await ethers.getContractFactory("AuctionImplementationV2");
		const implV2 = await ImplV2.deploy();
		await implV2.waitForDeployment();

		// 通过工厂执行升级
		await (await factory.upgradeAuction(proxyAddr, await implV2.getAddress())).wait();

		// 使用 V2 ABI 从代理读取版本
		const auctionV2 = await ethers.getContractAt("AuctionImplementationV2", proxyAddr);
		expect(await auctionV2.version()).to.eq("V2");

		// 升级后应保持：最高出价者 == deploy者
		const state = await auction.auction();
		expect(state.highestBidder).to.eq(deployer.address);
	});
});


