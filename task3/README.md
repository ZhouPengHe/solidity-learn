# NFT 拍卖市场（Hardhat）

## 功能
- 可升级 `ERC721` NFT（UUPS）
- 拍卖合约（UUPS）：支持 ETH/ERC20 出价、USD 报价（Chainlink）
- 工厂合约：创建拍卖（ERC1967Proxy），集中管理、统一 owner 控制
- 价格预言机：通过工厂设置代理内的喂价地址
- 预留 CCIP 接口（占位）

## 目录
- `contracts/`
  - `NFTUpgradeable.sol`
  - `AuctionImplementation.sol`
  - `AuctionFactory.sol`
  - `test/MockV3Aggregator.sol`（测试用）
- `test/auction.test.js` 基础流程用例
- `deploy/00_deploy.ts` 一键部署脚本
- `scripts/deploy.ts` 简版部署脚本

## 准备
创建 `.env`：
```
SEPOLIA_RPC_URL=你的RPC
PRIVATE_KEY=你的私钥
NFT_BASE_URI=https://base/
CHAINLINK_ETH_USD=0x694AA1769357215DE4FAC081bf1f309aDC325306
```

## 本地测试
```
npx hardhat test
```

## 测试报告
- 覆盖率：
  - 运行：`npx hardhat coverage`
  - 结果：`coverage/index.html`（HTML）、`coverage/lcov.info`
- 测试结果：
  - 运行：`npx hardhat test`
  - 结果：`reports/junit.xml`（JUnit XML）、`reports/mochawesome/report.html`（HTML）

## 部署（本地与 Sepolia）
```
# 编译
npx hardhat compile

# 本地网络部署（JS 脚本）
npx hardhat run scripts/deploy.js --network hardhat

# Sepolia 部署
npx hardhat run scripts/deploy.js --network sepolia

# 升级演示（JS 脚本，需设置环境变量）
# FACTORY_ADDR=工厂地址 AUCTION_PROXY=拍卖代理地址
FACTORY_ADDR=0x... AUCTION_PROXY=0x... npx hardhat run scripts/upgrade-demo.js --network sepolia
```

## 部署地址（Sepolia）
- Deployer: `0x036826575d83fd79C1C950C8dD0E74404EBba25f`
- NFT proxy: `0x531bC677577E3AEDC05904697b3645F4be268Fe4`
- Auction implementation: `0xb6A64b48dcB54405858E46A233B8C3A539F725E2`
- Auction factory: `0x7123Ad402B27EdB16De3244A9218bA62d591709A`

## 使用
1. 卖家在 `NFTUpgradeable` 铸造 NFT 并 `approve(factory, tokenId)`
2. 调用 `AuctionFactory.createAuction(nft, tokenId, duration, startPrice, payToken)` 创建拍卖
3. 由工厂 owner 调用 `setAuctionPriceFeed(auctionProxy, token, aggregator)` 设置价格喂价
4. 用户调用 `bid(amount)` 或附带 `value` 出价
5. 到期后调用 `endAuction()` 完成交割

## 设计说明
- 工厂为拍卖代理的 owner，统一权限便于升级与配置
- USD 报价以 1e8 精度输出，`AggregatorV3` 的 `decimals` 自动换算
- ERC20 出价在实现内读取代币 `decimals`（IERC20Metadata）


- 增加 ERC20 出价测试
  - 增加 USDC/DAI 等不同小数位（6/18）代币的出价/退款/结算用例
  - 覆盖报价为 USD 的断言：`quoteBidInUsd` 在不同 `decimals()` 与喂价 `decimals()` 组合下的精度
  - 加入边界条件：零额度 `approve` 后再次授权、超额退款、出价与结束的事件断言
  - 引入负面用例：未 `approve`、不足余额、过期后出价、低于当前最高价
- 动态手续费
  - 为工厂新增只读视图：查询当前手续费收款地址与费率
  - 在拍卖创建时允许传入默认费率，或由工厂统一下发后再覆盖
  - 增加事件：`FeeConfigUpdated(auction, recipient, feeBps)`，在测试中断言
  - 在结算路径分别验证 ETH 与 ERC20 的手续费扣减与转账顺序（先手续费后卖家）
- CCIP 跨链拍卖实现
  - 新增最小可用 PoC：
    - 在 `AuctionImplementation` 中实现 `sendCrossChainBidRequest(bytes)` 并新增事件 `CcipBidRequested(router, payload)`；
    - 新增目标链执行器 `CcipBidExecutor.sol`，解码 `payload` 并对 `auctionProxy` 调用 `bid(amount)`；
  - 约束与注意：
    - 仅 PoC，不包含路由签名校验、重放保护与资金跨链托管；
    - 生产化需替换为 CCIP Router 的 `send`/`ccipReceive` 流程，附带 source/dest chainId 校验；
  - 示例 payload ABI：
    - `abi.encode((address auctionProxy, address bidder, uint256 amount))`
  - 接入实际 CCIP Router：新增 `setCcipRouter(address)` 与开启/关闭开关的事件
  - 规范化 `sendCrossChainBid(bytes payload)`：定义 payload 编解码结构（拍卖地址、token、金额、出价人）
  - 目标链接收器合约 PoC：接收消息后在目标链执行 `bid` 并回执结果
  - 设计资金托管：源链锁定/目标链释放或使用跨链稳定币；失败回滚与重放保护
  - 增加模拟测试与文档示例，注明各测试网的 Router 与 Link 代币地址

## 详细说明

### 1. 合约间关系与升级模型
- `AuctionImplementation`：单场拍卖的逻辑实现（UUPS 可升级）。不直接部署，用 `ERC1967Proxy` 代理承载状态。
- `AuctionFactory`：工厂负责创建每场拍卖的代理实例，并作为每个代理的 `owner`。这样可以：
  - 统一设置价格预言机（不同支付资产对应不同喂价）。
  - 统一设置手续费（收款地址、万分比）。
  - 统一执行 UUPS 升级（调用代理的 `upgradeTo`）。

为什么要代理？
- 逻辑合约可以替换，但代理上的存储（状态）不变。升级前后拍卖的 `highestBid`、`highestBidder` 等不会丢失。

### 2. 出价与资金流
- ETH 出价：
  - 用户直接给 `bid()` 附带 `value`（单位 wei）。
  - 合约会判断是否高于当前最高价；如果之前有人出价，会把对方的钱原路退回。
- ERC20 出价：
  - 用户先在 ERC20 合约 `approve(拍卖代理地址, 金额)`。
  - 然后调用 `bid(amount)`，合约内部用 `transferFrom` 收到代币。
  - 退款时使用 `transfer` 把上一个最高价人的代币退回。

结束：
- `endAuction()` 到期可调用：
  - 若无人出价：把 NFT 还给卖家。
  - 若有人出价：把 NFT 给最高出价者；把资金（扣手续费后）转给卖家/手续费地址。

### 3. USD 报价（Chainlink 预言机）
- 价格来自 `AggregatorV3Interface`（喂价合约），如 `ETH/USD`、`USDC/USD`。
- 合约内提供 `quoteBidInUsd(amount)` 用于换算为 1e8 精度的 USD 值：
  - 自动读取支付资产的小数位（ETH 按 18 位，ERC20 读 `decimals()`）。
  - 自动适配喂价的 `decimals()`。
- 预言机地址通过工厂的 `setAuctionPriceFeed(auction, token, aggregator)` 设置：
  - `token = address(0)` 代表 ETH/USD。
  - 其他 `token` 地址代表该 ERC20 的 USD 喂价。

### 4. 手续费（动态可调）
- 工厂作为 owner 通过 `setAuctionFeeConfig(auction, recipient, feeBps)` 设置：
  - `feeBps` 为万分比，如 200 = 2%。
  - 结算时先计算手续费，再把余下金额转给卖家。
  - 同时支持 ETH 与 ERC20 结算。

### 5. CCIP 跨链（当前为占位）
- 合约中预留了 `ccipRouter` 与 `ccipEnabled`，以及 `sendCrossChainBid(bytes)` 占位函数：
  - 当前仅返回是否开启与路由是否设置，不做真实跨链。
- 真正落地 CCIP 时通常需要：
  - 路由合约地址（不同测试网/主网不同）。
  - 把出价信息编码为消息，通过路由发送到目标链；目标链的接收器合约执行 `bid`。
  - 设计好跨链资金的托管与结算（如源链锁定、目标链释放，或反向消息回执等）。

