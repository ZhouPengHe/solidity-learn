// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./AuctionImplementation.sol";

/**
 * 工厂合约：
 * - 负责部署拍卖代理合约（ERC1967Proxy）并初始化
 * - 持有实现合约地址，支持升级实现（可选）
 * - 保存所有拍卖实例地址
 */
contract AuctionFactory is Ownable {
	address public implementation;
	address[] public allAuctions;

	event AuctionDeployed(address proxy, address seller, address nft, uint256 tokenId, address payToken, uint256 startPrice, uint256 duration);
	event ImplementationUpgraded(address newImpl);

	constructor(address implementation_) Ownable(msg.sender) {
		require(implementation_ != address(0), "impl=0");
		implementation = implementation_;
	}

	function setImplementation(address newImpl) external onlyOwner {
		require(newImpl != address(0), "impl=0");
		implementation = newImpl;
		emit ImplementationUpgraded(newImpl);
	}

	/// 升级指定拍卖代理到新的实现（UUPS upgradeTo），仅工厂 owner
	function upgradeAuction(address auctionProxy, address newImpl) external onlyOwner {
		require(newImpl != address(0), "impl=0");
		// 调用 UUPS 的 upgradeToAndCall(address,bytes)（空数据）
		(bytes memory data) = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImpl, "");
		(bool ok, ) = auctionProxy.call(data);
		require(ok, "upgrade fail");
	}

	function allAuctionsLength() external view returns (uint256) {
		return allAuctions.length;
	}

	/// 创建一场拍卖，并把工厂设为 owner，便于后续升级/管理。
	function createAuction(
		address nftContract,
		uint256 tokenId,
		uint256 duration,
		uint256 startPrice,
		address payTokenAddress
	) external returns (address proxyAddr) {
		require(implementation != address(0), "no impl");
		// 需要先由卖家授权本工厂转移 NFT
		bytes memory data = abi.encodeWithSelector(
			AuctionImplementation.initialize.selector,
			address(this),
			msg.sender,
			nftContract,
			tokenId,
			duration,
			startPrice,
			payTokenAddress
		);

		ERC1967Proxy proxy = new ERC1967Proxy(implementation, data);
		proxyAddr = address(proxy);

		// 转移 NFT 到新拍卖合约（需事先 approve 给工厂）
		IERC721(nftContract).transferFrom(msg.sender, proxyAddr, tokenId);

		allAuctions.push(proxyAddr);
		emit AuctionDeployed(proxyAddr, msg.sender, nftContract, tokenId, payTokenAddress, startPrice, duration);
	}

	/// 由工厂 owner 代表拍卖代理设置价格预言机
	function setAuctionPriceFeed(address auctionProxy, address token, address aggregator) external onlyOwner {
		(bool ok, ) = auctionProxy.call(abi.encodeWithSelector(AuctionImplementation.setPriceFeed.selector, token, aggregator));
		require(ok, "call fail");
	}

	/// 由工厂 owner 设置手续费配置
	function setAuctionFeeConfig(address auctionProxy, address recipient, uint16 feeBps) external onlyOwner {
		(bool ok, ) = auctionProxy.call(abi.encodeWithSelector(AuctionImplementation.setFeeConfig.selector, recipient, feeBps));
		require(ok, "call fail");
	}

	/// 由工厂 owner 设置 CCIP 配置（转发到拍卖代理）
	function setAuctionCcipConfig(address auctionProxy, address router, bool enabled) external onlyOwner {
		(bool ok, ) = auctionProxy.call(abi.encodeWithSelector(AuctionImplementation.setCcipConfig.selector, router, enabled));
		require(ok, "call fail");
	}
}


