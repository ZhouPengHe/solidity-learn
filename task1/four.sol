// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ✅  用 solidity 实现罗马数字转数整数
contract Four {
    function romanToInt(string memory s) public pure returns (uint256) {
        uint256 result = 0;
        uint256 len = bytes(s).length;
        for (uint i = 0; i < len; i++) {
            uint256 currentValue = romanCharToValue(bytes(s)[i]);
            uint256 nextValue = (i + 1 < len) ? romanCharToValue(bytes(s)[i + 1]) : 0;
            if (currentValue < nextValue) {
                result -= currentValue;
            } else {
                result += currentValue;
            }
        }
        return result;
    }

    function romanCharToValue(bytes1 char) private pure returns (uint256) {
        if (char == 'I') return 1;
        if (char == 'V') return 5;
        if (char == 'X') return 10;
        if (char == 'L') return 50;
        if (char == 'C') return 100;
        if (char == 'D') return 500;
        if (char == 'M') return 1000;
        revert("Invalid Roman character");
    }
}
