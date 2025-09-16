// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IAuctionBidOnly {
    function bid(uint256 amount) external payable;
}

/**
 * 最小可用 CCIP 执行器（目标链）
 * - 解码从源链带来的 payload，并在本链上的拍卖代理执行 bid
 * - 仅演示用途：未做签名/路由校验与重放保护
 */
contract CcipBidExecutor is Ownable {
    event PayloadExecuted(address indexed auction, bool isEth, uint256 amount);

    struct BidPayload {
        address auctionProxy;    // 目标链拍卖代理地址
        bool isEth;              // 是否 ETH 出价
        uint256 amount;          // 出价金额（代币单位或 wei）
    }

    constructor() Ownable(msg.sender) {}

    function execute(bytes calldata payload) external payable onlyOwner {
        BidPayload memory p = abi.decode(payload, (BidPayload));
        if (p.isEth) {
            require(msg.value == p.amount, "bad msg.value");
            IAuctionBidOnly(p.auctionProxy).bid{value: msg.value}(0);
        } else {
            IAuctionBidOnly(p.auctionProxy).bid(p.amount);
        }
        emit PayloadExecuted(p.auctionProxy, p.isEth, p.amount);
    }
}


