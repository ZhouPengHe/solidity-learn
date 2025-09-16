// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
	uint8 private immutable _customDecimals;

	constructor(string memory n, string memory s, uint8 d) ERC20(n, s) {
		_customDecimals = d;
		_mint(msg.sender, 1_000_000 * 10 ** d);
	}

	function decimals() public view override returns (uint8) {
		return _customDecimals;
	}
}


