// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 讨饭合约
// 测试-捐赠交易详情：
//      https://sepolia.etherscan.io/tx/0xd83673393fc17c5ea11fab5d2708ed34bb7adbbade955a8ef58fd9586d68cf07
//      https://sepolia.etherscan.io/tx/0x9b9d888aa5b237d8b06d4092f196b92a5d5d2e15ec9ea50aec5945cd14e87076
//      https://sepolia.etherscan.io/tx/0x0c407ca1e0fbbe55ebd58779f368105c35914d36765d544edfa7c646d5cb3186

// 测试-提现交易详情：
//      https://sepolia.etherscan.io/tx/0x0be80e6975fbefaef57ec2d6beae8805f073fcc249d7075f89e6bae392127681
contract BeggingContract {
    address public owner;

    // 记录每个捐赠者的捐赠金额。
    mapping (address => uint256) private donations;

    // 捐赠者地址列表
    address[] private donors;

    // 捐赠事件
    event Donation(address indexed donor, uint256 amount);

    // 时间限制
    uint256 public startTime;
    uint256 public endTime;

    // 设置捐赠时间限制
    constructor(uint256 _startTime, uint256 _endTime){
        owner = msg.sender;
        startTime = _startTime;
        endTime = _endTime;
    }

    // 判断合约所有者
    modifier onlyOwner(){
        require(msg.sender == owner,"No permission");
        _;
    }

    // 时间限制
    modifier timeLimit(){
        require(block.timestamp >= startTime && block.timestamp <= endTime, 
        "Donations are not available at this time");
        _;
    }

    // 捐赠函数
    function donate() external payable timeLimit {
        require(msg.value > 0.0001 ether, "Donation must be greater than 0");
        if (donations[msg.sender] == 0){
            donors.push(msg.sender);
        }
        donations[msg.sender] += msg.value;
        emit Donation(msg.sender, msg.value);
    }

    // 合约所有者提取资金
    function withdraw() external onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "No balance");
        payable(owner).transfer(amount);
    }

    // 查询某个地址的捐赠金额。
    function getDonation(address addr) external view returns(uint256){
        return donations[addr];
    }

    // 显示捐赠金额最多的前2个地址
    function topDonors() external view returns (address[2] memory topAddrs, uint256[2] memory topAmounts){
        address[] memory tempDonors = donors;
        uint256[] memory amounts = new uint256[](tempDonors.length);
        for (uint i=0; i < tempDonors.length; i++) {
            amounts[i] = donations[tempDonors[i]];
        }
        for (uint i = 0; i < tempDonors.length; i++){
            for (uint j = i + 1; j < tempDonors.length; j++){
                if (amounts[j] > amounts[i]) {
                    uint256 tempAmount = amounts[i];
                    amounts[i] = amounts[j];
                    amounts[j] = tempAmount;
                    address tempAddr = tempDonors[i];
                    tempDonors[i] = tempDonors[j];
                    tempDonors[j] = tempAddr;
                }
            }
        }
        for (uint i = 0; i < 2; i++) {
            if ( i < tempDonors.length) {
                topAddrs[i] = tempDonors[i];
                topAmounts[i] = amounts [i];
            }else {
                topAddrs[i] = address(0);
                topAmounts[i] = 0;
            }
        }
    }
}