// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./AuctionImplementation.sol";

/**
 * V2 实现：
 * - 在 V1 基础上增加一个只读函数 version()，验证升级生效
 * - 保持存储布局不变（通过继承 V1）
 */
contract AuctionImplementationV2 is AuctionImplementation {
	function version() external pure returns (string memory) {
		return "V2";
	}
}


