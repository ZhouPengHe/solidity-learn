const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("拍卖端", function () {
	it("创建拍卖，使用 ETH 出价并结束", async function () {
		const [deployer, seller, bidder1, bidder2] = await ethers.getSigners();

		// 部署 NFT 可升级
		const NFT = await ethers.getContractFactory("NFTUpgradeable");
		const nft = await upgrades.deployProxy(NFT, ["DemoNFT", "DNFT", "https://base/"], { initializer: "initialize" });
		await nft.waitForDeployment();

		// 给卖家铸造 1 个 NFT
		await (await nft.connect(deployer).safeMint(seller.address)).wait();
		const tokenId = 1;

		// 部署拍卖实现
		const Impl = await ethers.getContractFactory("AuctionImplementation");
		const implementation = await Impl.deploy();
		await implementation.waitForDeployment();

		// 部署工厂
		const Factory = await ethers.getContractFactory("AuctionFactory");
		const factory = await Factory.deploy(await implementation.getAddress());
		await factory.waitForDeployment();

		// 卖家授权工厂转移 NFT
		await (await nft.connect(seller).approve(await factory.getAddress(), tokenId)).wait();

		// 创建拍卖（支付资产为 ETH: address(0)）
		const duration = 3 * 60; // 3 分钟
		const startPrice = ethers.parseEther("0.01");
		const tx = await factory.connect(seller).createAuction(await nft.getAddress(), tokenId, duration, startPrice, ethers.ZeroAddress);
		const rc = await tx.wait();
		const evt = rc.logs.find((l) => l.fragment && l.fragment.name === "AuctionDeployed");
		const proxyAddr = evt.args[0];

		const auction = await ethers.getContractAt("AuctionImplementation", proxyAddr);

		// 设置 ETH/USD 预言机，避免报价时失败（使用不同变量名避免重名）
		const MockFeed2 = await ethers.getContractFactory("MockV3Aggregator");
		const ethFeed2 = await MockFeed2.deploy(8, 2000n * 10n ** 8n);
		await ethFeed2.waitForDeployment();
		await (await factory.setAuctionPriceFeed(proxyAddr, ethers.ZeroAddress, await ethFeed2.getAddress())).wait();

		// 已设置喂价

		// 出价 1：0.02 ETH（bidder1）
		await (await auction.connect(bidder1).bid(0, { value: ethers.parseEther("0.02") })).wait();

		// 出价 2：0.03 ETH（bidder2）
		await (await auction.connect(bidder2).bid(0, { value: ethers.parseEther("0.03") })).wait();

		// 增加时间并结束拍卖
		await ethers.provider.send("evm_increaseTime", [duration + 1]);
		await ethers.provider.send("evm_mine", []);
		await (await auction.endAuction()).wait();

		// 验证 NFT 到达 bidder2
		expect(await nft.ownerOf(tokenId)).to.eq(bidder2.address);
	});

	it("创建拍卖，使用 ERC20 出价并结算手续费", async function () {
		const [deployer, seller, bidder1, bidder2, fee] = await ethers.getSigners();

		// NFT
		const NFT = await ethers.getContractFactory("NFTUpgradeable");
		const nft = await upgrades.deployProxy(NFT, ["DemoNFT", "DNFT", "https://base/"], { initializer: "initialize" });
		await nft.waitForDeployment();
		await (await nft.safeMint(seller.address)).wait();
		const tokenId = 1;

		// ERC20
		const ERC20 = await ethers.getContractFactory("MockERC20");
		const usdc = await ERC20.deploy("MockUSDC", "mUSDC", 6);
		await usdc.waitForDeployment();
		// 给两个出价者一些余额
		await (await usdc.transfer(bidder1.address, 100_000n * 10n ** 6n)).wait();
		await (await usdc.transfer(bidder2.address, 100_000n * 10n ** 6n)).wait();

		// 实现与工厂
		const Impl = await ethers.getContractFactory("AuctionImplementation");
		const implementation = await Impl.deploy();
		await implementation.waitForDeployment();
		const Factory = await ethers.getContractFactory("AuctionFactory");
		const factory = await Factory.deploy(await implementation.getAddress());
		await factory.waitForDeployment();

		// 授权 NFT 给工厂
		await (await nft.connect(seller).approve(await factory.getAddress(), tokenId)).wait();

		// 创建拍卖（支付代币为 USDC）
		const duration = 60;
		const startPrice = 1_000_000n; // 1 USDC，6 位
		const tx = await factory.connect(seller).createAuction(await nft.getAddress(), tokenId, duration, startPrice, await usdc.getAddress());
		const rc = await tx.wait();
		const evt = rc.logs.find((l) => l.fragment && l.fragment.name === "AuctionDeployed");
		const proxyAddr = evt.args[0];
		const auction = await ethers.getContractAt("AuctionImplementation", proxyAddr);

		// 设置 USDC/USD 预言机（8 位，1.00 美元 => 1e8）
		const Mock = await ethers.getContractFactory("MockV3Aggregator");
		const usdcFeed = await Mock.deploy(8, 1n * 10n ** 8n);
		await usdcFeed.waitForDeployment();
		await (await factory.setAuctionPriceFeed(proxyAddr, await usdc.getAddress(), await usdcFeed.getAddress())).wait();

		// 设置手续费 2% 到 fee 地址（通过工厂）
		await (await factory.setAuctionFeeConfig(proxyAddr, fee.address, 200)).wait();

		// 两个用户授权 USDC 给拍卖合约
		await (await usdc.connect(bidder1).approve(proxyAddr, 1_000_000_000n)).wait();
		await (await usdc.connect(bidder2).approve(proxyAddr, 1_000_000_000n)).wait();

		// 连续出价
		await (await auction.connect(bidder1).bid(2_000_000n)).wait(); // 2 USDC
		await (await auction.connect(bidder2).bid(3_000_000n)).wait(); // 3 USDC

		// 结束
		await ethers.provider.send("evm_increaseTime", [duration + 1]);
		await ethers.provider.send("evm_mine", []);
		const feeBalBefore = await usdc.balanceOf(fee.address);
		await (await auction.endAuction()).wait();

		// 验证持有人与手续费到账
		expect(await nft.ownerOf(tokenId)).to.eq(bidder2.address);
		const feeBalAfter = await usdc.balanceOf(fee.address);
		expect(feeBalAfter - feeBalBefore).to.eq(60_000n); // 3_000_000 * 2% = 60_000
	});

	it("ERC20 18 位小数出价：USD 报价正确，超价退款", async function () {
		const [deployer, seller, bidder1, bidder2] = await ethers.getSigners();

		// NFT
		const NFT = await ethers.getContractFactory("NFTUpgradeable");
		const nft = await upgrades.deployProxy(NFT, ["DemoNFT", "DNFT", "https://base/"], { initializer: "initialize" });
		await nft.waitForDeployment();
		await (await nft.safeMint(seller.address)).wait();
		const tokenId = 1;

		// 18 位小数的 ERC20
		const ERC20 = await ethers.getContractFactory("MockERC20");
		const dai = await ERC20.deploy("MockDAI", "mDAI", 18);
		await dai.waitForDeployment();
		// 分配余额
		await (await dai.transfer(bidder1.address, 100_000n * 10n ** 18n)).wait();
		await (await dai.transfer(bidder2.address, 100_000n * 10n ** 18n)).wait();

		// 实现合约与工厂
		const Impl = await ethers.getContractFactory("AuctionImplementation");
		const implementation = await Impl.deploy();
		await implementation.waitForDeployment();
		const Factory = await ethers.getContractFactory("AuctionFactory");
		const factory = await Factory.deploy(await implementation.getAddress());
		await factory.waitForDeployment();

		// 授权 NFT 给工厂
		await (await nft.connect(seller).approve(await factory.getAddress(), tokenId)).wait();

		// 创建拍卖（支付代币 DAI）
		const duration = 60;
		const startPrice = 1n * 10n ** 18n; // 1 DAI
		const tx = await factory.connect(seller).createAuction(await nft.getAddress(), tokenId, duration, startPrice, await dai.getAddress());
		const rc = await tx.wait();
		const evt = rc.logs.find((l) => l.fragment && l.fragment.name === "AuctionDeployed");
		const proxyAddr = evt.args[0];
		const auction = await ethers.getContractAt("AuctionImplementation", proxyAddr);

		// 设置喂价：1.00 USD（8 位小数）
		const Mock = await ethers.getContractFactory("MockV3Aggregator");
		const daiFeed = await Mock.deploy(8, 1n * 10n ** 8n);
		await daiFeed.waitForDeployment();
		await (await factory.setAuctionPriceFeed(proxyAddr, await dai.getAddress(), await daiFeed.getAddress())).wait();

		// 代币授权
		await (await dai.connect(bidder1).approve(proxyAddr, 1_000_000n * 10n ** 18n)).wait();
		await (await dai.connect(bidder2).approve(proxyAddr, 1_000_000n * 10n ** 18n)).wait();

		// 第一次出价：5 DAI
		const bidder1BalBefore = await dai.balanceOf(bidder1.address);
		let bidTx = await auction.connect(bidder1).bid(5n * 10n ** 18n);
		let bidRc = await bidTx.wait();
		let bidEvt = bidRc.logs.find((l) => l.fragment && l.fragment.name === "BidPlaced");
		expect(bidEvt.args[1]).to.eq(5n * 10n ** 18n); // amount
		expect(bidEvt.args[2]).to.eq(5n * 10n ** 8n); // usd 1e8
		const bidder1BalAfterFirst = await dai.balanceOf(bidder1.address);
		expect(bidder1BalBefore - bidder1BalAfterFirst).to.eq(5n * 10n ** 18n);

		// 第二次出价：6 DAI（bidder2）-> 退款给 bidder1 5 DAI
		const bidder1BalBeforeRefund = await dai.balanceOf(bidder1.address);
		await (await auction.connect(bidder2).bid(6n * 10n ** 18n)).wait();
		const bidder1BalAfterRefund = await dai.balanceOf(bidder1.address);
		expect(bidder1BalAfterRefund - bidder1BalBeforeRefund).to.eq(5n * 10n ** 18n);

		// 结束
		await ethers.provider.send("evm_increaseTime", [duration + 1]);
		await ethers.provider.send("evm_mine", []);
		await (await auction.endAuction()).wait();
		expect(await nft.ownerOf(tokenId)).to.eq(bidder2.address);
	});

	it("ERC20 负面用例：未授权、低价、已过期", async function () {
		const [deployer, seller, bidder] = await ethers.getSigners();

		// NFT
		const NFT = await ethers.getContractFactory("NFTUpgradeable");
		const nft = await upgrades.deployProxy(NFT, ["DemoNFT", "DNFT", "https://base/"], { initializer: "initialize" });
		await nft.waitForDeployment();
		await (await nft.safeMint(seller.address)).wait();
		const tokenId = 1;

		// ERC20 6 decimals
		const ERC20 = await ethers.getContractFactory("MockERC20");
		const usdc = await ERC20.deploy("MockUSDC", "mUSDC", 6);
		await usdc.waitForDeployment();
		await (await usdc.transfer(bidder.address, 1_000_000n * 10n ** 6n)).wait();

		// impl + factory
		const Impl = await ethers.getContractFactory("AuctionImplementation");
		const implementation = await Impl.deploy();
		await implementation.waitForDeployment();
		const Factory = await ethers.getContractFactory("AuctionFactory");
		const factory = await Factory.deploy(await implementation.getAddress());
		await factory.waitForDeployment();

		await (await nft.connect(seller).approve(await factory.getAddress(), tokenId)).wait();

		const duration = 30;
		const startPrice = 1_000_000n; // 1 USDC
		const tx = await factory.connect(seller).createAuction(await nft.getAddress(), tokenId, duration, startPrice, await usdc.getAddress());
		const rc = await tx.wait();
		const evt = rc.logs.find((l) => l.fragment && l.fragment.name === "AuctionDeployed");
		const proxyAddr = evt.args[0];
		const auction = await ethers.getContractAt("AuctionImplementation", proxyAddr);

		// 设置喂价
		const Mock = await ethers.getContractFactory("MockV3Aggregator");
		const feed = await Mock.deploy(8, 1n * 10n ** 8n);
		await feed.waitForDeployment();
		await (await factory.setAuctionPriceFeed(proxyAddr, await usdc.getAddress(), await feed.getAddress())).wait();

		// 1) 未授权 approve -> transferFrom 失败（使用 try/catch 断言）
		let failed = false;
		try {
			await auction.connect(bidder).bid(2_000_000n);
		} catch (e) {
			failed = true;
		}
		expect(failed).to.eq(true);

		// 授权最小额度并按起拍价出价成功
		await (await usdc.connect(bidder).approve(proxyAddr, 2_000_000n)).wait();
		await (await auction.connect(bidder).bid(1_000_000n)).wait();

		// 2) 低于当前要求的出价
		failed = false;
		try {
			await auction.connect(bidder).bid(1_000_000n);
		} catch (e) {
			failed = true;
		}
		expect(failed).to.eq(true);

		// 3) 已过期
		await ethers.provider.send("evm_increaseTime", [duration + 1]);
		await ethers.provider.send("evm_mine", []);
		failed = false;
		try {
			await auction.connect(bidder).bid(2_000_000n);
		} catch (e) {
			failed = true;
		}
		expect(failed).to.eq(true);
	});

	it("CCIP 占位开关工作", async function () {
		const [deployer, seller] = await ethers.getSigners();
		const NFT = await ethers.getContractFactory("NFTUpgradeable");
		const nft = await upgrades.deployProxy(NFT, ["DemoNFT", "DNFT", "https://base/"], { initializer: "initialize" });
		await nft.waitForDeployment();
		await (await nft.safeMint(seller.address)).wait();
		const tokenId = 1;

		const Impl = await ethers.getContractFactory("AuctionImplementation");
		const implementation = await Impl.deploy();
		await implementation.waitForDeployment();
		const Factory = await ethers.getContractFactory("AuctionFactory");
		const factory = await Factory.deploy(await implementation.getAddress());
		await factory.waitForDeployment();

		await (await nft.connect(seller).approve(await factory.getAddress(), tokenId)).wait();
		const tx = await factory.connect(seller).createAuction(await nft.getAddress(), tokenId, 30, 1, ethers.ZeroAddress);
		const rc = await tx.wait();
		const evt = rc.logs.find((l) => l.fragment && l.fragment.name === "AuctionDeployed");
		const proxyAddr = evt.args[0];
		const auction = await ethers.getContractAt("AuctionImplementation", proxyAddr);

		// 默认为 false
		expect(await auction.sendCrossChainBid("0x"))
			.to.eq(false);

		// 保持占位：不做配置与跨链，仅断言默认 false
	});

	it("CCIP PoC：发送请求事件并由执行器转发 ETH 出价", async function () {
		const [deployer, seller, bidder] = await ethers.getSigners();
		const NFT = await ethers.getContractFactory("NFTUpgradeable");
		const nft = await upgrades.deployProxy(NFT, ["DemoNFT", "DNFT", "https://base/"], { initializer: "initialize" });
		await nft.waitForDeployment();
		await (await nft.safeMint(seller.address)).wait();
		const tokenId = 1;

		const Impl = await ethers.getContractFactory("AuctionImplementation");
		const implementation = await Impl.deploy();
		await implementation.waitForDeployment();
		const Factory = await ethers.getContractFactory("AuctionFactory");
		const factory = await Factory.deploy(await implementation.getAddress());
		await factory.waitForDeployment();

		await (await nft.connect(seller).approve(await factory.getAddress(), tokenId)).wait();
		const tx = await factory.connect(seller).createAuction(await nft.getAddress(), tokenId, 30, ethers.parseEther("0.01"), ethers.ZeroAddress);
		const rc = await tx.wait();
		const evt = rc.logs.find((l) => l.fragment && l.fragment.name === "AuctionDeployed");
		const proxyAddr = evt.args[0];
		const auction = await ethers.getContractAt("AuctionImplementation", proxyAddr);

		// 通过工厂转发设置 CCIP 配置
		await (await factory.setAuctionCcipConfig(proxyAddr, deployer.address, true)).wait();

		// 监听事件并发送请求
		const payload = ethers.AbiCoder.defaultAbiCoder().encode([
			"tuple(address auctionProxy, bool isEth, uint256 amount)"
		], [[proxyAddr, true, ethers.parseEther("0.02")]]);
		const req = await auction.connect(deployer).sendCrossChainBidRequest(payload);
		await req.wait();

		// 目标链执行器在本链模拟执行
		const Exec = await ethers.getContractFactory("CcipBidExecutor");
		const exec = await Exec.deploy();
		await exec.waitForDeployment();

		// 确保该拍卖已设置 ETH/USD 喂价
		const MockFeed3 = await ethers.getContractFactory("MockV3Aggregator");
		const ethFeed3 = await MockFeed3.deploy(8, 2000n * 10n ** 8n);
		await ethFeed3.waitForDeployment();
		await (await factory.setAuctionPriceFeed(proxyAddr, ethers.ZeroAddress, await ethFeed3.getAddress())).wait();

		await (await exec.execute(payload, { value: ethers.parseEther("0.02") })).wait();

		// 最高价应为 0.02 ETH
		const info = await auction.auction();
		expect(info.highestBid).to.eq(ethers.parseEther("0.02"));
	});
});


