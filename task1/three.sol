// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ✅ 用 Solidity 实现整数转罗马数字
contract Three {
    function intToRoman(uint256 num) public pure returns (string memory) {
        string[13] memory romanSymbols = [
            "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"
        ];
        uint16[13] memory values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
        string memory result = "";
        for (uint8 i = 0; i < 13; i++) {
            while (num >= values[i]) {
                result = string(abi.encodePacked(result, romanSymbols[i]));
                num -= values[i];
            }
        }
        return result;
    }
}
