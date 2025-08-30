// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//✅  二分查找 (Binary Search)
// 题目描述：在一个有序数组中查找目标值。
contract Six{

     function binarySearch(uint[] calldata arr, uint target) external pure returns (int) {
        uint start = 0;
        uint end = arr.length - 1;
        while (start <= end) {
            uint mid = start + (end - start) / 2;
            if (arr[mid] == target) {
                return int(mid);
            }
            if (arr[mid] > target) {
                end = mid - 1;
            }else {
                start = mid + 1;
            }
        }
        return -1;
    }

}