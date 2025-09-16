// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * 拍卖实现（UUPS 可升级）
 * - 支持 ETH 或 ERC20 出价
 * - 使用 Chainlink 预言机计算美元价
 * - 升级由合约 owner 控制（建议由工厂作为 owner）
 */
contract AuctionImplementation is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
	struct Auction {
		address seller;          // 卖家
		uint256 duration;        // 拍卖持续时间，单位秒
		uint256 startPrice;      // 起拍价（以支付代币单位表示；若 ETH 则为 wei）
		uint256 startTime;       // 拍卖开始时间
		bool ended;              // 是否结束
		address highestBidder;   // 最高出价者
		uint256 highestBid;      // 最高出价（以支付代币单位；若 ETH 则为 wei）
		address nftContract;     // NFT 合约地址
		uint256 tokenId;         // NFT ID
		address payTokenAddress; // 出价代币地址，0 表示 ETH
	}

	Auction public auction;

	// 代币地址 => Chainlink 预言机（token/USD 或 ETH/USD）。若 address(0) => ETH/USD。
	mapping(address => AggregatorV3Interface) public priceFeeds;

	// CCIP 占位配置
	address public ccipRouter;
	bool public ccipEnabled;

	// 手续费配置
	address public feeRecipient; // 收费地址
	uint16 public feeBps;        // 手续费，基点（万分比）。200 => 2%

	event AuctionCreated(address indexed seller, address indexed nft, uint256 indexed tokenId, address payToken, uint256 startPrice, uint256 duration);
	event BidPlaced(address indexed bidder, uint256 amount, uint256 amountUsd);
	event AuctionEnded(address indexed winner, uint256 amount);
	event PriceFeedUpdated(address indexed token, address indexed aggregator);
	event FeeConfigUpdated(address indexed recipient, uint16 feeBps);
	event CcipConfigUpdated(address indexed router, bool enabled);
	// CCIP 最小可用演示：仅发出请求事件，由外部路由/执行器处理跨链与目标链执行
	event CcipBidRequested(address indexed router, bytes payload);

	/// 初始化（由代理调用）
	function initialize(
		address owner_,
		address seller,
		address nftContract,
		uint256 tokenId,
		uint256 duration,
		uint256 startPrice,
		address payTokenAddress
	) public initializer {
		__Ownable_init(owner_);
		__UUPSUpgradeable_init();
		__ReentrancyGuard_init();

		require(nftContract != address(0), "NFT=0");
		require(duration > 0, "duration=0");
		require(startPrice > 0, "startPrice=0");

		auction = Auction({
			seller: seller,
			duration: duration,
			startPrice: startPrice,
			startTime: block.timestamp,
			ended: false,
			highestBidder: address(0),
			highestBid: 0,
			nftContract: nftContract,
			tokenId: tokenId,
			payTokenAddress: payTokenAddress
		});

		emit AuctionCreated(seller, nftContract, tokenId, payTokenAddress, startPrice, duration);
	}

	// owner 设置价格预言机地址（token=>USD 或 ETH=>USD）。
	function setPriceFeed(address token, address aggregator) external onlyOwner {
		require(aggregator != address(0), "agg=0");
		priceFeeds[token] = AggregatorV3Interface(aggregator);
		emit PriceFeedUpdated(token, aggregator);
	}

	/// 读取最新价格并返回：price，decimals（美元有 decimals 小数）
	function getLatestPrice(address token) public view returns (int256 price, uint8 decimals) {
		AggregatorV3Interface feed = priceFeeds[token];
		require(address(feed) != address(0), "feed not set");
		(, int256 answer,,,) = feed.latestRoundData();
		return (answer, feed.decimals());
	}

	/// 设置手续费（仅 owner）。feeBps 为万分比，最大 2000 (20%)
	function setFeeConfig(address recipient, uint16 feeBps_) external onlyOwner {
		require(recipient != address(0), "recipient=0");
		require(feeBps_ <= 2000, "fee too high");
		feeRecipient = recipient;
		feeBps = feeBps_;
		emit FeeConfigUpdated(recipient, feeBps_);
	}

	/// 设置 CCIP 路由与开关（占位）
	function setCcipConfig(address router, bool enabled) external onlyOwner {
		ccipRouter = router;
		ccipEnabled = enabled;
		emit CcipConfigUpdated(router, enabled);
	}

	/// 最小可用 CCIP 请求：仅校验开关并发事件，实际跨链发送与目标链执行在链下/路由完成
	function sendCrossChainBidRequest(bytes calldata payload) external returns (bool) {
		require(ccipEnabled && ccipRouter != address(0), "ccip disabled");
		emit CcipBidRequested(ccipRouter, payload);
		return true;
	}

	/// 计算给定出价金额的美元值（返回 1e8 精度的 USD 金额）。
	function quoteBidInUsd(uint256 amount) public view returns (uint256 usdAmountE8) {
		address payToken = auction.payTokenAddress;
		(int256 price, uint8 pDecimals) = getLatestPrice(payToken);
		require(price > 0, "bad price");
		uint256 priceU = uint256(price);
		uint256 tokenDecimals = payToken == address(0) ? 18 : IERC20Metadata(payToken).decimals();
		// amount(1eTokenDec) * price(1ePDec) -> 1e(TokenDec+PDec)
		// 归一到 1e8（常见的 USD 标准精度）
		usdAmountE8 = amount * priceU;
		if (tokenDecimals + pDecimals >= 8) {
			usdAmountE8 = usdAmountE8 / (10 ** (tokenDecimals + pDecimals - 8));
		} else {
			usdAmountE8 = usdAmountE8 * (10 ** (8 - tokenDecimals - pDecimals));
		}
	}

	/// 出价：
	function bid(uint256 amount) external payable nonReentrant {
		require(!auction.ended, "ended");
		require(block.timestamp < auction.startTime + auction.duration, "expired");

		uint256 payAmount;
		if (auction.payTokenAddress == address(0)) {
			payAmount = msg.value;
			require(payAmount > 0, "no eth");
		} else {
			require(amount > 0, "amount=0");
			payAmount = amount;
			IERC20(auction.payTokenAddress).transferFrom(msg.sender, address(this), payAmount);
		}

		uint256 minRequired = auction.highestBid == 0 ? auction.startPrice : auction.highestBid + 1; // 简单加一规则
		require(payAmount >= minRequired, "low bid");

		// 退款给之前的最高出价者
		if (auction.highestBidder != address(0)) {
			if (auction.payTokenAddress == address(0)) {
				(bool ok,) = auction.highestBidder.call{value: auction.highestBid}("");
				require(ok, "refund fail");
			} else {
				IERC20(auction.payTokenAddress).transfer(auction.highestBidder, auction.highestBid);
			}
		}

		auction.highestBidder = msg.sender;
		auction.highestBid = payAmount;

		uint256 usd = quoteBidInUsd(payAmount);
		emit BidPlaced(msg.sender, payAmount, usd);
	}

	/// 结束拍卖：任何人可在过期后调用
	function endAuction() external nonReentrant {
		require(!auction.ended, "ended");
		require(block.timestamp >= auction.startTime + auction.duration, "not ended");
		auction.ended = true;

		// 如果没有出价，NFT 归还卖家
		if (auction.highestBidder == address(0)) {
			IERC721(auction.nftContract).transferFrom(address(this), auction.seller, auction.tokenId);
			emit AuctionEnded(address(0), 0);
			return;
		}

		// 转 NFT 给中标者
		IERC721(auction.nftContract).transferFrom(address(this), auction.highestBidder, auction.tokenId);
		// 结算资金：先扣手续费（若配置）再转给卖家
		uint256 amount = auction.highestBid;
		uint256 fee = feeRecipient != address(0) && feeBps > 0 ? (amount * feeBps) / 10000 : 0;
		uint256 toSeller = amount - fee;
		if (auction.payTokenAddress == address(0)) {
			if (fee > 0) {
				(bool okF,) = payable(feeRecipient).call{value: fee}("");
				require(okF, "pay fee fail");
			}
			(bool okS,) = payable(auction.seller).call{value: toSeller}("");
			require(okS, "pay seller fail");
		} else {
			if (fee > 0) {
				IERC20(auction.payTokenAddress).transfer(feeRecipient, fee);
			}
			IERC20(auction.payTokenAddress).transfer(auction.seller, toSeller);
		}

		emit AuctionEnded(auction.highestBidder, auction.highestBid);
	}

	/// 卖家可在无人出价时取消（可选）
	function cancel() external nonReentrant {
		require(msg.sender == auction.seller || msg.sender == owner(), "no auth");
		require(!auction.ended, "ended");
		require(auction.highestBidder == address(0), "has bid");
		auction.ended = true;
		IERC721(auction.nftContract).transferFrom(address(this), auction.seller, auction.tokenId);
	}

	/// 预留：跨链拍卖接口（占位）
	function sendCrossChainBid(bytes calldata /*payload*/ ) external view returns (bool) {
		// 兼容旧测试：返回当前是否开启 + 是否设置路由
		return ccipEnabled && ccipRouter != address(0);
	}

	function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

	/// 仅限 owner 触发的升级入口，便于通过工厂代理升级（避免接口签名/兼容性问题）。
	// 移除占位升级方法，采用工厂直接调用 UUPS upgradeTo

	// 接收 ETH
	receive() external payable {}
}


