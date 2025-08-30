// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//✅  合并两个有序数组 (Merge Sorted Array)
// 题目描述：将两个有序数组合并为一个有序数组。
contract Five{
    function mergeSortedArray(uint[] calldata a, uint[] calldata b) external pure returns(uint[] memory){
        uint[] memory newArray = new uint[](a.length + b.length);
        uint i = 0;
        uint j = 0;
        uint k = 0;
        while (i < a.length && j < b.length) {
            if (a[i] <= b[j]) {
                newArray[k] = a[i];
                i++;
            } else {
                newArray[k] = b[j];
                j++;
            }
            k++;
        }
         while (i < a.length) {
            newArray[k] = a[i];
            i++;
            k++;
        }
        while (j < b.length) {
            newArray[k] = b[j];
            j++;
            k++;
        }
        return newArray;
    }
}