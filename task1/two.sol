// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
// ✅ 反转字符串 (Reverse String)
// 题目描述：反转一个字符串。输入 "abcde"，输出 "edcba"
contract Two{
    function reverseString(string calldata str) external pure returns(string memory){
        bytes memory byteStr = bytes(str);
        uint len = byteStr.length;
        bytes memory newStr = new bytes(len);
        for(uint i = 0; i < len; i++){
            newStr[i] = byteStr[len - 1 - i];
        }
        return string(newStr);
    }
}