// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 任务：参考 openzeppelin-contracts/contracts/token/ERC20/IERC20.sol实现一个简单的 ERC20 代币合约。要求：
// 合约包含以下标准 ERC20 功能：
// 部署到sepolia 测试网，导入到自己的钱包
contract MyToken{
    
    string public name = "ZhouToken";
    string public symbol = "ZTK";
    uint public decimals = 18;
    // 总代币值
    uint256 private totalSupply;

    // 部署者
    address private owner;

    // 使用 mapping 存储账户余额和授权信息。
    mapping (address => uint256) private balances;
    mapping (address => mapping(address => uint256)) private allowances;

    // 使用 event 记录转账和授权操作。
    // 使用 event 定义 Transfer 和 Approval 事件。
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor (uint256 initialSupply){
        owner = msg.sender;
        _mint(msg.sender, initialSupply);
    }

    // 只允许 owner 调用
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // 提供 mint 函数，允许合约所有者增发代币。
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // 内部增发代币方法
    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function allowancesOf(address ownerAddr, address spenderAddr) external view returns(uint256){
        return allowances[ownerAddr][spenderAddr];
    }

    // balanceOf：查询账户余额。
    function balanceOf(address addr) external view returns(uint256){
        return balances[addr];
    }

    // 查询代币总值
    function totalSupplyOf() external view returns (uint256){
        return totalSupply;
    }

    // transfer：转账。
    function transfer(address addr, uint256 amount) external returns(bool){
        require(balances[msg.sender] >= amount, "Insufficient funds");
        balances[msg.sender] -= amount;
        balances[addr] += amount;
        emit Transfer(msg.sender, addr, amount);
        return true;
    }

    // approve: 授权
    function approve(address addr, uint256 amount) external returns(bool){
        allowances[msg.sender][addr] = amount;
        emit Approval(msg.sender, addr, amount);
        return true;
    }

    // transferFrom：代扣转账
    function transFerFrom(address from, address to, uint256 amount) external returns(bool){
        require(balances[from] >= amount, "Insufficient funds");
        require(allowances[from][msg.sender] >= amount, "Insufficient allowance");
        balances[from] -= amount;
        allowances[from][msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}