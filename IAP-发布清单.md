# 时间树洞 · IAP 提交审核 + App 新版本发布清单

> 适用对象：时间树洞 iOS App（Bundle ID `com.carolqin.timetreehole`，版本 `1.0`）
> 目标：把 3 个灵叶 IAP 随 App 1.0 版本提交 App Store 审核，批准后真实购买走通。
> 前置已就绪：✅ 付费应用协议已签（姓名 Yaohan Qin）✅ 共享密钥已配 Railway ✅ 三个 IAP「可供审核」✅ 构建 `11bf310` 已上 TestFlight

---

## 一、提交前确认（打勾）

- [x] **付费应用协议 (Paid Apps Agreement)** 状态 = 有效/Active
  - 路径：App Store Connect → 商务 → 协议、税务和银行业务 → 「付费 App」协议
  - 协议持有人姓名需用开发者法定名 `Yaohan Qin`
- [x] **银行 / 税务信息** 已填（中国大陆银行，币种由 Apple 按地区自动定，无需手动选）
- [x] **App 专用共享密钥** 已生成，并填入 Railway Variables 的 `APPLE_SHARED_SECRET`
- [x] **三个 IAP 状态 = 可供审核 (Ready to Submit)**
  - `com.timetreehole.credits.small` — 50 灵叶 / ¥6
  - `com.timetreehole.credits.medium` — 120 灵叶 / ¥12
  - `com.timetreehole.credits.large` — 300 灵叶 / ¥25
- [ ] **IAP 类型确认**：灵叶是消耗型货币 → 三个产品必须都是 **消耗型 (Consumable)**。若是「非消耗型」会被拒，需改成消耗型再提交。
- [x] **隐私政策 URL** 可访问（线上 `privacy-policy.html` / `privacy-policy-site/`）

---

## 二、为每个 IAP 补齐审核素材（3 个各做一次）

App Store Connect → 我的 App → 时间树洞 → **功能 / App 内购买项目** → 点开每个产品：

- [ ] **审核截图（1024×1024）**：已备 `design-exports/credits-store-1024.png`（72 dpi、无 alpha、JPEG/PNG）。上传到每个产品的「审核信息 → 截图」。
- [ ] **审核备注 (Review Notes)**：用中文写清，降低被拒率：
  > 灵叶是「时间树洞」应用内的虚拟消耗型货币，用于兑换应用内功能（如将私密种子投放至公域）。用户进入「灵叶商店」点击对应档位，通过 StoreKit 2 完成购买，购买成功后灵叶即时到账。本产品为消耗型，不提供退款。
- [ ] **购买路径说明**：备注里指明购买入口在 App 内「灵叶商店」页，必要时附一张 App 内商店界面截图（可用 `design-exports/credits-store-iphone16promax.jpg` 辅助说明）。
- [ ] **价格与地区**：确认三个档位定价等级（Tier）分别 ≈ ¥6 / ¥12 / ¥25，销售地区包含「中国区」。

> 注意：全新 App 首次上架时，单个 IAP **不能独立提交**，必须挂在 App 版本里一起送审（见第三步）。

---

## 三、创建 / 编辑 App 1.0 版本并挂接 IAP

- [ ] **进入版本页**：App Store Connect → 时间树洞 → **App Store 标签页**
  - 若还没有 1.0 版本：点「+ 版本或平台」→ 新建版本 **`1.0`**（须与 App 内 `MARKETING_VERSION` 一致）。
  - 若已有 1.0 在「准备提交 / 被拒绝」状态：直接编辑它。
- [ ] **添加 IAP**：在版本编辑页的 **「App 内购买项目」** 区域 → 「+」→ 勾选上面三个灵叶产品（它们会显示为「等待提交」）。
- [ ] **选择构建版本 (Build)**：在 **「构建版本」** 区域 → 「+」→ 选择 TestFlight 中已处理完成（状态不再是「处理中」）的 `11bf310` 对应 build（版本 1.0，build 号 > 历史值）。
- [ ] **版本元信息**（首次提交必填）：
  - [ ] 名称、副标题、描述、关键词（中文）
  - [ ] 截图：App 实际 UI 截图（iPhone 6.7" 1290×2796 为主，建议再补 6.5"）。**不要用 IAP 的 1024 图当 App 截图。**
  - [ ] 技术支持网址、营销网址（可选）
  - [ ] 隐私政策网址（填线上隐私政策 URL）
  - [ ] 分级（年龄评级）问卷

---

## 四、提交审核

- [ ] 在版本页底部点 **「提交审核 / Submit for Review」**
- [ ] 回答送审问卷：
  - **加密 / 出口合规**：App 使用 StoreKit（Apple 标准加密），通常适用豁免，选「否 / 适用豁免」。
  - **广告标识符 (IDFA)**：本 App 未使用广告追踪 → 选「否」。
  - **其他合规问题**：按实回答。
- [ ] 确认三个 IAP 出现在送审内容里（状态变为「正在审核 / Waiting for Review」）。

---

## 五、审核期间 & 通过后

- [ ] **审核时长**：通常 1–2 个工作日；节假日顺延。状态在「我的 App → 活动 → 所有构建版本 / App 审核」查看。
- [ ] **被拒处理**：若收到「被拒绝 (Rejected)」，读拒绝理由 → 在版本页修改 → 重新提交；IAP 通常无需重传截图，除非理由涉及 IAP。
- [ ] **批准后**：三个 IAP 状态变「已批准 (Approved)」，App 可选「手动发布」或「自动发布」。
- [ ] **真机验收（真买链路）**：
  - [ ] 用 **沙盒测试账号**（设置 → App Store → 沙盒账号）登录后真机购买，验证走通 StoreKit 2 → 后端 `verifyReceipt` → 灵叶到账。
  - [ ] 正式发布后，普通用户购买同样链路，确认 Railway 后端 `APPLE_SHARED_SECRET` 校验通过、402 引导正常。

---

## 六、常见坑位 & 提醒

1. **IAP 必须与 App 版本一起提交**：全新 App 无法单独上架 IAP，挂版本是必经之路。
2. **版本号一致性**：App Store Connect 版本号必须 = App 内 `MARKETING_VERSION`（当前 `1.0`）；Build 号必须 > 已上传历史值（已由 `11bf310` 的 Fastfile 动态递增解决）。
3. **消耗型 vs 非消耗型**：灵叶是货币，务必消耗型，否则审核必拒且无法「购买后永久拥有」。
4. **1024 审核图规格**：72 dpi、不含透明通道、JPEG 或 PNG —— `credits-store-1024.png` 已满足。
5. **隐私政策 URL 必须公网可访问**：Apple 会抓取校验，本地/内网地址会被拒。
6. **沙盒测试 ≠ 真买**：内测阶段你验证的是切换/额度逻辑；真购买要等审核批准 + 沙盒或正式环境买一次确认。
7. **CI 复用**：本次 Fastfile 已改用仓库根绝对路径 + xcodegen `--project` 传父目录，后续改完代码 push 即自动重建，无需再手动处理路径。

---

## 七、待办回顾（项目级）

- [ ] 按本清单完成 IAP + 1.0 版本送审
- [ ] 审核通过后真机沙盒购买验收灵叶到账
- [ ] （可选）把本次「Codemagic + XcodeGen + fastlane 绝对路径」的 CI 修复沉淀为 skill，复用给其他 iOS 项目
