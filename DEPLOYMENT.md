# 时间树洞 · 部署文档

> 最后更新: 2026-08-03
> 架构: 后端 Render 免费层 + iOS 构建 Codemagic 免费层
> 总成本: $0/月 (仅 Apple Developer 年费 $99/年)

---

## 目录

1. [整体架构](#1-整体架构)
2. [后端部署 — Render 免费层](#2-后端部署--render-免费层)
3. [iOS 构建上架 — Codemagic 免费层](#3-ios-构建上架--codemagic-免费层)
4. [Codemagic 免费方案已知缺点与应对](#4-codemagic-免费方案已知缺点与应对)
5. [上线前检查清单](#5-上线前检查清单)
6. [上线后日常运维](#6-上线后日常运维)
7. [备选方案](#7-备选方案)

---

## 1. 整体架构

```
┌─────────────────────────────────────────────────────┐
│                     用户 iPhone                      │
│              (TestFlight / App Store)                │
└──────────────────────┬──────────────────────────────┘
                       │ HTTPS
                       ▼
┌─────────────────────────────────────────────────────┐
│              Render 免费层 (后端 API)                 │
│  https://timetreehole-api.onrender.com              │
│  ┌─────────────────────────────────────────────┐     │
│  │  Node.js + Express + SQLite                 │     │
│  │  Docker 容器, 自动 HTTPS, 自动重启          │     │
│  └─────────────────────────────────────────────┘     │
└──────────────────────┬──────────────────────────────┘
                       │ git push
                       ▼
┌─────────────────────────────────────────────────────┐
│                 GitHub 仓库 (代码)                    │
│  ┌──────────┐        ┌──────────────────────────┐   │
│  │ main 分支 │───────▶│  Render (自动部署后端)   │   │
│  │          │        └──────────────────────────┘   │
│  │          │        ┌──────────────────────────┐   │
│  │          │───────▶│  Codemagic (构建上传 iOS) │   │
│  └──────────┘        └──────────────────────────┘   │
└─────────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│  Codemagic Mac mini M1 (免费层, 500 分钟/月)         │
│  自动: 安装 XcodeGen → 生成工程 → 编译 → 签名        │
│  → 归档 → 上传 TestFlight                            │
└─────────────────────────────────────────────────────┘
```

**两条流水线，全部免费**:
- **后端**: git push → Render 自动构建部署 → API 上线
- **iOS**: git push → Codemagic 构建 → TestFlight 安装测试

---

## 2. 后端部署 — Render 免费层

### 配置文件

| 文件 | 作用 |
|------|------|
| `render.yaml` | Render Blueprint 配置 (基础设施即代码) |
| `backend/Dockerfile` | Docker 多阶段构建 |
| `backend/render-start.sh` | 启动脚本 (首次自动初始化演示数据) |

### 操作步骤

```bash
# 1. 把代码 push 到 GitHub
cd D:/时间树洞APP
git remote add origin https://github.com/<你的用户名>/timetreehole.git
git push -u origin main

# 2. 修改 render.yaml 第 9 行
#    repo: https://github.com/<你的用户名>/timetreehole.git

# 3. 登录 Render Dashboard
#    https://dashboard.render.com
#    New → Blueprint → 连接 GitHub 仓库
#    Render 自动读取 render.yaml 创建服务

# 4. 等待 3-5 分钟构建完成
#    获得: https://timetreehole-api.onrender.com

# 5. 验证
curl https://timetreehole-api.onrender.com/api/health
# 预期: {"status":"ok","service":"时间树洞 · API",...}

# 6. 配置环境变量 (Render Dashboard → Environment)
#    APPLE_SHARED_SECRET  — App Store Connect 共享密钥
#    APNS_KEY_ID         — Apple Developer Key ID
#    APNS_TEAM_ID        — Apple Developer Team ID
#    APPLE_IAP_ENV       — sandbox (测试) / production (上线)

# 7. 防休眠 (免费层 15 分钟无请求会休眠)
#    注册 https://uptimerobot.com
#    添加 HTTP 监控: https://timetreehole-api.onrender.com/api/health
#    间隔: 5 分钟
```

### Render 免费层限制

| 限制 | 影响 | 应对 |
|------|------|------|
| 15 分钟休眠 | 冷启动 ~30 秒 | UptimeRobot 5 分钟 ping |
| 临时存储 | 每次重新部署重置 DB | 首次启动自动初始化演示数据 |
| 750 小时/月 | 刚好 24/7 | 配合 UptimeRobot 可覆盖 |
| 100 GB/月流量 | 小型 App 够用 | 用户量上来后升级 |
| 512 MB 内存 | 够用 | 注意内存泄漏 |

---

## 3. iOS 构建上架 — Codemagic 免费层

### 配置文件

| 文件 | 作用 |
|------|------|
| `codemagic.yaml` | Codemagic CI/CD 配置 (推荐, 全自动) |
| `TimeTreehole/project.yml` | XcodeGen 工程配置 (需填入 Team ID) |

### 前置准备 (一次性)

1. **注册 Apple Developer** ($99/年)
   - https://developer.apple.com/programs/enroll/
   - 等待审核通过 (1-2 天)

2. **创建 App Store Connect API Key**
   - 登录 https://appstoreconnect.apple.com
   - 用户和访问 → 密钥 → 生成 API Key
   - 权限: App Manager (或 Admin)
   - **下载 `.p8` 文件** (只能下载一次, 妥善保存)
   - 记录: Issuer ID, Key ID, Team ID

3. **填入 Team ID**
   - 编辑 `TimeTreehole/project.yml`
   - 把 `DEVELOPMENT_TEAM: ""` 改为 `DEVELOPMENT_TEAM: "你的10位TeamID"`
   - Team ID 获取: Apple Developer → Membership

### Codemagic 操作步骤

```
注册 Codemagic → 连接 GitHub → 配置变量组 → 一键构建
```

**第 1 步: 注册 Codemagic**

- 访问 https://codemagic.io
- 用 GitHub 账号登录 (免费层 500 分钟/月)
- 点击 Add Application → 选 GitHub 仓库

**第 2 步: 创建变量组**

Codemagic Dashboard → App settings → Environment variables → 创建变量组 `appstore_credentials`:

| 变量名 | 值 | 来源 |
|--------|-----|------|
| `APP_STORE_CONNECT_ISSUER_ID` | UUID 格式 | App Store Connect → 密钥页面顶部 |
| `APP_STORE_CONNECT_KEY` | `.p8` 文件完整内容 | 下载的 AuthKey_xxxx.p8 |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | 10 位字符 | 密钥列表中的 Key ID |
| `DEVELOPMENT_TEAM_ID` | 10 位字符 | Apple Developer → Membership |

每个变量勾选 **Secure** (加密存储)。

**第 3 步: 启动构建**

- Codemagic Dashboard → Start build
- 或: git push 到 main 分支自动触发
- 等待 10-15 分钟

**Codemagic 自动完成的流程**:

```
brew install xcodegen          ← 安装 XcodeGen
    ↓
sed 替换 project.yml Team ID   ← 填入你的 Team ID
    ↓
xcodegen generate              ← 生成 .xcodeproj
    ↓
xcodebuild archive             ← 编译 + 归档
    ↓
自动创建签名证书 + 描述文件      ← 用 API Key 签名
    ↓
上传 App Store Connect          ← 自动推送到 TestFlight
    ↓
邮件通知                       ← 成功/失败都会收到
```

**第 4 步: TestFlight 测试**

- iPhone 安装 TestFlight App
- App Store Connect → TestFlight → 添加测试员 (你的邮箱)
- 收到邮件 → 点击安装 → 在手机上测试

### Codemagic 免费层配额

| 项目 | 免费额度 | 实际消耗 | 够用吗 |
|------|---------|---------|--------|
| 每月构建分钟 | 500 分钟 | ~10-15 分钟/次 | 够 30-50 次/月 |
| 并行构建 | 1 个 | — | 够用 |
| 构建 Mac 型号 | Mac mini M1 | — | 够用 |
| 存储 | 30 天 | — | 够用 |

---

## 4. Codemagic 免费方案已知缺点与应对

### 4.1 迭代慢 (最大痛点)

| 场景 | 有 Mac | Codemagic |
|------|--------|-----------|
| 改一行代码到看到效果 | Cmd+B, 3 秒 | git push → CI → TestFlight → 安装, **10-30 分钟** |
| 调试 UI 布局 | 模拟器实时看 | 每改一次都要等一轮构建上传 |

**应对**: 开发阶段把改动攒一批再 push, 不要改一行就构建一次。

### 4.2 不能交互式调试

- 不能打断点 (Xcode LLDB 调试器)
- 不能看实时 console (只有 CI 日志)
- 不能查看视图层级 (Debug View Hierarchy)
- 出 bug 只能靠 `print()` + CI 日志排查

**应对**: 代码里多加 `print()` 日志, 复杂逻辑提前在本地用 Swift Playground 验证。

### 4.3 免费额度有限

- 500 分钟/月, iOS 构建约 10-15 分钟/次
- 理论够 30-50 次构建, 调试期可能一天 5-10 次
- 超了得等下月或升级付费 ($200/月)

**应对**: 
- 确保代码能编译通过再 push (避免浪费构建在编译错误上)
- 取消前一次构建: `codemagic.yaml` 已配 `cancel_previous_builds: true`
- 非紧急改动攒到一批一起 push

### 4.4 没有模拟器

- 不能在模拟器上测试不同屏幕尺寸
- 所有测试必须用真机 + TestFlight
- 没有 iPhone 的话, 基本无法验证 UI

**应对**: 至少准备一台 iPhone 用于 TestFlight 测试。没有的话考虑租云 Mac ($1-2/小时) 做关键阶段的 UI 验证。

### 4.5 TestFlight 处理延迟

- 每次构建上传后 Apple 需处理 5-15 分钟
- 新版本首个构建可能需要 TestFlight Beta 审核 (几小时到 1 天)
- 这段时间内什么都做不了

**应对**: 新版本提前构建上传, 不要卡在截止时间。

### 4.6 签名出错难排查

- Codemagic 自动管理证书通常没问题
- 但如果签名失败 (Team ID 填错, Bundle ID 冲突), CI 日志报错往往很长
- 没有 Xcode 可视化签名面板, 排错全靠读日志

**应对**: 确保 `project.yml` 的 Bundle ID 和 Team ID 正确, API Key 权限为 App Manager 以上。

### 4.7 应对策略总结

| 阶段 | 推荐做法 | 理由 |
|------|---------|------|
| 日常开发 | 攒批 push + Codemagic 构建 | 免费额度内高效迭代 |
| UI 微调期 | 租云 Mac $1/小时按需用 | 需要 Xcode 模拟器实时预览 |
| 功能完成后 | Codemagic 签名上传 | 全自动省心 |
| 偶尔小改 | 直接 Codemagic | 改一行不值得租 Mac |
| 预算: 开发期约 20 小时 Mac | ~$30 | 比买 Mac Mini (¥4000+) 便宜 100 倍 |

---

## 5. 上线前检查清单

### 后端

- [ ] 代码已 push 到 GitHub
- [ ] `render.yaml` 中 `repo` 已改为真实 GitHub 地址
- [ ] Render Blueprint 已创建, 服务正在运行
- [ ] 访问 `https://<你的域名>.onrender.com/api/health` 返回 ok
- [ ] 访问 `https://<你的域名>.onrender.com/api/treehole/stats` 有数据
- [ ] Render Environment 已配置 `APPLE_SHARED_SECRET`
- [ ] Render Environment 已配置 `APNS_KEY_ID`, `APNS_TEAM_ID`
- [ ] `APPLE_IAP_ENV` 设为 `sandbox` (上线后改 `production`)
- [ ] UptimeRobot 已配置 5 分钟 ping 防休眠
- [ ] iOS 客户端 `APIConfig.swift` baseURL 与 Render 域名一致

### iOS

- [ ] Apple Developer 账号已激活 ($99/年)
- [ ] App Store Connect API Key 已创建, `.p8` 文件已保存
- [ ] `TimeTreehole/project.yml` 中 `DEVELOPMENT_TEAM` 已填入
- [ ] Codemagic 已连接 GitHub 仓库
- [ ] Codemagic 变量组 `appstore_credentials` 已配置 4 个变量
- [ ] 首次构建成功, TestFlight 可安装
- [ ] 真机测试: 录音 → 上传 → 树洞 → 回复 → 通知
- [ ] IAP 沙盒测试: 购买灵叶 → 确认到账
- [ ] App Store Connect 中 App 信息已填写
- [ ] App Store Connect 中 3 个 IAP 产品已创建
- [ ] App Store Connect 中「付费 App 协议」状态为有效
- [ ] App Store Connect 中截图已上传 (design-exports/)
- [ ] App Store Connect 中描述已粘贴 (design-exports/app-store-description.txt)
- [ ] App Store Connect 中关键词已粘贴 (design-exports/app-store-keywords.txt)
- [ ] 隐私政策 URL 已填写 (CloudStudio 链接)
- [ ] 提交审核

---

## 6. 上线后日常运维

### 后端运维 (接近零)

| 任务 | 频率 | 操作 |
|------|------|------|
| 检查服务是否在线 | 每天 | UptimeRobot 自动告警 |
| 更新后端代码 | 按需 | git push, Render 自动部署 |
| 查看日志 | 按需 | Render Dashboard → Logs |
| 检查构建状态 | 按需 | Codemagic Dashboard → Builds |
| 检查配额 | 每月 | Codemagic Dashboard → Billing |

### iOS 更新流程

```bash
# 1. 修改代码
# 2. 本地确认能编译 (如有 Mac: xcodegen generate && xcodebuild build)
# 3. git push
# 4. Codemagic 自动构建 → TestFlight
# 5. TestFlight 测试通过后
# 6. App Store Connect → 选择新版本 → 提交审核
```

### 什么时候需要花钱升级

| 场景 | 触发条件 | 解决方案 | 费用 |
|------|----------|----------|------|
| 数据不能丢 | 有真实用户 | Render 加持久磁盘 | $7/月 |
| 流量超限 | 月访问 > 100GB | 升级 Render 付费层 | $7/月 |
| 冷启动慢 | 忍不了 30 秒 | 升级后不休眠 | $7/月 |
| 自定义域名 | 想要品牌域名 | 买域名 + 绑定 Render | ¥50/年 |
| Codemagic 不够 | 月构建 > 50 次 | 升级付费或租云 Mac | $200/月或$1-2/小时 |

**建议**: 现在先用免费层上线, 等有真实用户和收入了再升级。一个内购收入 (¥6) 就够覆盖一个月的 Render 付费层。

---

## 7. 备选方案

### 备选 A: GitHub Actions (公开仓库免费)

- 配置文件: `.github/workflows/ios-build-upload.yml`
- 适合: GitHub 仓库可以公开
- 缺点: 需要手动用 `generate-csr.sh` 生成证书并存为 Secrets, 签名出问题需要自己排
- 触发: 打 `v1.0.0` tag 自动触发

### 备选 B: 云 Mac 租赁 ($1-2/小时)

- 平台: MacinCloud, MacStadium, Flow
- 适合: 需要 Xcode 图形界面操作 (UI 微调, 交互调试)
- 优点: 跟用 Mac 一样, 模拟器 + 断点调试全都有
- 缺点: 按小时收费, 开发期成本可能累积
- 建议: 开发期按需租, 发布后用 Codemagic

### 备选 C: VPS 自建 ($5-20/月)

- 配置文件: `docker-compose.prod.yml`, `nginx/`, `setup-ssl.sh`
- 适合: 用户量大了, 需要持久存储和稳定服务
- 操作: `bash deploy.sh vps` 查看指南
- 缺点: 需要自己运维 (SSL 续期, 监控, 安全更新)

---

## 附录: 关键文件速查

| 文件 | 用途 | 部署时需要修改 |
|------|------|----------------|
| `render.yaml` | Render 后端配置 | ✅ 第 9 行 repo 地址 |
| `backend/Dockerfile` | Docker 构建 | ❌ 无需改 |
| `backend/render-start.sh` | 启动脚本 | ❌ 无需改 |
| `backend/.env.example` | 环境变量模板 | ❌ 参考, 不直接用 |
| `codemagic.yaml` | iOS CI/CD 配置 | ❌ 无需改 (变量在网页配) |
| `TimeTreehole/project.yml` | XcodeGen 配置 | ✅ DEVELOPMENT_TEAM |
| `generate-csr.sh` | 生成证书 (备选用) | ❌ 仅 GitHub Actions 方案需要 |
| `.github/workflows/ios-build-upload.yml` | GitHub Actions (备选用) | ❌ 仅备选方案 |
| `backend/deploy.sh` | 部署辅助脚本 | ❌ 参考 |
| `TimeTreehole/TimeTreehole/Services/APIConfig.swift` | iOS API 地址 | ✅ Release baseURL |
