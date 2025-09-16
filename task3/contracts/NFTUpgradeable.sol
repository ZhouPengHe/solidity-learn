// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * 可升级的 ERC721 NFT 合约
 * - 使用 UUPS 模式
 * - 支持批量/单次铸造
 * - 可设置 baseURI
 */
contract NFTUpgradeable is Initializable, ERC721Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
	string private _baseTokenURI;
	uint256 private _nextTokenId;
    mapping(uint256 => string) private _tokenURIs;

	/// 初始化函数（替代构造）
	function initialize(string memory name_, string memory symbol_, string memory baseURI_) public initializer {
		__ERC721_init(name_, symbol_);
		__Ownable_init(msg.sender);
		__UUPSUpgradeable_init();
		_baseTokenURI = baseURI_;
		_nextTokenId = 1;
	}

	function setBaseURI(string memory newBase) external onlyOwner {
		_baseTokenURI = newBase;
	}

	function safeMint(address to) external onlyOwner returns (uint256 tokenId) {
		tokenId = _nextTokenId++;
		_safeMint(to, tokenId);
	}

	function safeMintWithURI(address to, string memory tokenURI_) external onlyOwner returns (uint256 tokenId) {
		tokenId = _nextTokenId++;
		_safeMint(to, tokenId);
		_tokenURIs[tokenId] = tokenURI_;
	}

	function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

	function _baseURI() internal view override returns (string memory) {
		return _baseTokenURI;
	}

	function tokenURI(uint256 tokenId) public view override returns (string memory) {
		_requireOwned(tokenId);
		string memory specific = _tokenURIs[tokenId];
		if (bytes(specific).length > 0) {
			return specific;
		}
		return super.tokenURI(tokenId);
	}

	function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
		return super.supportsInterface(interfaceId);
	}
}