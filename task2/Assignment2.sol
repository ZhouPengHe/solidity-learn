// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
// 在测试网上发行一个图文并茂的 NFT
contract Assignment2 is ERC721URIStorage, Ownable {
    uint256 private tokenIds;

    constructor(string memory name, string memory symbol) 
    ERC721(name, symbol) Ownable(msg.sender){}

    // ipfs://bafkreib44g65kqztoypxjtcuk4276wzhvyanqm5pxfxhi4aj44gkk22f4m
    // https://sepolia.etherscan.io/tx/0x4ca70f4c875ebb7f0d0440f3309d1892d13b0cb2c68f359f514b1a749bbd8bef
    function mintNFT(address addr, string memory tokenURI) public onlyOwner returns (uint256) {
        tokenIds += 1;
        uint256 newId = tokenIds;
        _mint(addr, newId);
        _setTokenURI(newId, tokenURI);
        return newId;
    }
}