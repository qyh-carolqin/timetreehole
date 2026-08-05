#!/bin/bash
# ============================================================
#  时间树洞 · 一键部署脚本 (增强版)
#  用法: bash deploy.sh [平台]
#
#  平台:
#    docker      — 本地 Docker 部署 (API only, 端口 3000)
#    prod        — 生产环境 Docker Compose (API + Nginx + SSL)
#    local       — 本地 Node.js 开发运行
#    railway     — 云平台部署指南 (Railway, 推荐, 不要信用卡)
#    cloud       — 云平台部署指南 (Render, 需信用卡)
#    vps         — 自建 VPS 部署指南 (阿里云 / 腾讯云)
# ============================================================

set -e

PLATFORM="${1:-docker}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  🌳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━🌳"
echo "  │      时间树洞 · 后端部署工具 v1.0       │"
echo "  └──────────────────────────────────────────┘"
echo ""
echo "  项目目录: $PROJECT_DIR"
echo "  部署平台: $PLATFORM"
echo ""

# ============================================================
# Docker 本地部署（开发/测试用）
# ============================================================
deploy_docker() {
    echo "🐳 Docker 部署..."

    if ! command -v docker &> /dev/null; then
        echo "❌ 未安装 Docker"
        exit 1
    fi

    cd "$PROJECT_DIR"

    # 检查 .env 文件
    if [ ! -f ".env" ]; then
        echo "📝 未找到 .env 文件，从 .env.example 创建..."
        cp .env.example .env
        echo "⚠️  请编辑 .env 填入实际配置后重新运行"
        exit 1
    fi

    echo "🔨 构建镜像..."
    docker compose build --no-cache

    echo "🚀 启动服务..."
    docker compose up -d

    echo ""
    echo "✅ 部署完成！"
    echo "   健康检查:  curl http://localhost:3000/api/health"
    echo "   查看日志:  docker compose logs -f api"
    echo "   停止服务:  docker compose down"
}

# ============================================================
# 生产部署（API + Nginx + SSL）
# ============================================================
deploy_prod() {
    echo "🏭 生产环境部署..."

    if ! command -v docker &> /dev/null; then
        echo "❌ 未安装 Docker"
        exit 1
    fi

    cd "$PROJECT_DIR"

    # 检查 .env
    if [ ! -f ".env" ]; then
        echo "📝 未找到 .env 文件，从 .env.example 创建..."
        cp .env.example .env
        echo "⚠️  请编辑 .env 填入实际配置后重新运行"
        exit 1
    fi

    # 检查 Nginx 配置中的域名
    echo ""
    echo "🔍 当前 Nginx 域名配置:"
    grep "server_name" nginx/conf.d/timetreehole.conf | head -2
    echo ""
    read -p "⚠️  域名配置正确吗？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "请先修改 nginx/conf.d/timetreehole.conf 中的域名"
        exit 1
    fi

    echo "🔨 构建镜像..."
    docker compose -f docker-compose.prod.yml build --no-cache

    echo ""
    echo "⚠️  首次部署需要 SSL 证书。选择:"
    echo "  1) 暂不启用 HTTPS（只用 HTTP，Nginx 未启动 SSL 前会失败）"
    echo "  2) 现在创建 Let's Encrypt SSL 证书"
    echo ""
    read -p "请选择 (1/2): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[2]$ ]]; then
        # 先启动 HTTP-only Nginx 以完成验证
        echo "🚀 启动 HTTP 服务..."
        cp nginx/conf.d/timetreehole.conf nginx/conf.d/timetreehole.conf.bak

        # 临时移除 SSL server block，只保留 HTTP
        # (实际生产建议手动编辑或用更精细的 sed)
        docker compose -f docker-compose.prod.yml up -d nginx api

        # 获取 SSL 证书
        echo ""
        read -p "请输入你的域名 [api.timetreehole.com]: " DOMAIN
        DOMAIN=${DOMAIN:-api.timetreehole.com}
        read -p "请输入你的邮箱 [admin@timetreehole.com]: " EMAIL
        EMAIL=${EMAIL:-admin@timetreehole.com}

        bash setup-ssl.sh "$DOMAIN" "$EMAIL"

        echo "🔄 重新加载完整配置..."
        docker compose -f docker-compose.prod.yml up -d --force-recreate nginx
    else
        echo "🚀 启动生产环境（HTTP only）..."
        docker compose -f docker-compose.prod.yml up -d api
        echo ""
        echo "⚠️  暂未配置 HTTPS。你可以稍后运行 setup-ssl.sh 获取证书。"
    fi

    echo ""
    echo "✅ 生产环境部署完成！"
    echo "   查看日志:  docker compose -f docker-compose.prod.yml logs -f"
}

# ============================================================
# VPS 自建服务器指南
# ============================================================
deploy_vps() {
    echo "🖥️  VPS 自建服务器部署指南"
    echo ""
    echo "  📋 前置条件:"
    echo "     - 一台安装了 Ubuntu 22.04+ 的服务器"
    echo "     - 域名已解析到服务器 IP"
    echo "     - 防火墙开放 80/443 端口"
    echo ""
    echo "  🔧 部署步骤:"
    echo ""
    echo "  第 1 步: SSH 连接服务器"
    echo "    ssh root@你的服务器IP"
    echo ""
    echo "  第 2 步: 安装 Docker"
    echo "    curl -fsSL https://get.docker.com | bash"
    echo "    sudo usermod -aG docker \$USER"
    echo "    newgrp docker"
    echo ""
    echo "  第 3 步: 上传项目"
    echo "    # 在本地执行:"
    echo "    rsync -avz --exclude 'node_modules' --exclude 'data/*.db*' ./ root@你的服务器IP:/opt/timetreehole/"
    echo "    # 或使用 git clone"
    echo ""
    echo "  第 4 步: 配置环境变量"
    echo "    cd /opt/timetreehole/backend"
    echo "    cp .env.example .env"
    echo "    nano .env   # 填入实际值"
    echo ""
    echo "  第 5 步: 修改 Nginx 域名"
    echo "    nano nginx/conf.d/timetreehole.conf"
    echo "    # 把 api.timetreehole.com 替换为你的域名"
    echo ""
    echo "  第 6 步: 一键部署"
    echo "    bash deploy.sh prod"
    echo ""
    echo "  💰 推荐服务器:"
    echo "     - 腾讯云轻量应用服务器 (2核2G ¥58/月)"
    echo "     - 阿里云 ECS (2核2G ¥68/月)"
    echo "     - Vultr / DigitalOcean ($6/月)"
    echo ""
    echo "  📊 资源需求:"
    echo "     - CPU: 1 核以上"
    echo "     - 内存: 1 GB 以上"
    echo "     - 磁盘: 10 GB 以上 (音频存储)"
}

# ============================================================
# 本地开发
# ============================================================
deploy_local() {
    echo "📦 本地开���运行..."
    cd "$PROJECT_DIR"
    if [ ! -d "node_modules" ]; then
        npm install
    fi
    if [ ! -f "data/timetreehole.db" ]; then
        echo "🌱 初始化示例数据..."
        node scripts/seed-demo.js
    fi
    echo "🚀 启动 (端口 3000)..."
    node server.js
}

# ============================================================
# 云平台：Railway 免费部署（推荐，不要信用卡！��
# ============================================================
deploy_railway() {
    echo ""
    echo "  🚂  Railway 免费部署 — 不要信用卡、自动 HTTPS、零运维"
    echo ""
    echo "  📋 前置条件："
    echo "     - GitHub 仓库（代码在 https://github.com/qyh-carolqin/timetreehole）"
    echo "     - Railway 账号（https://railway.app 用 GitHub 登���）"
    echo ""
    echo "  🔧 操作步骤（3 分钟）："
    echo ""
    echo "  ┌─ 第 1 步：注册 Railway ──────────────────────┐"
    echo "  │  ① 浏览器打开 https://railway.app             │"
    echo "  │  ② 点击 Login → Continue with GitHub           │"
    echo "  │  ③ 授权后进入控制台                            │"
    echo "  │  💡 无需信用卡！                               │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ┌─ 第 2 步：创建项目并部署 ────────────────────┐"
    echo "  │  ① 控制台点击 New Project                      │"
    echo "  │  ② 选择 Deploy from GitHub repo                │"
    echo "  │  ③ 搜索并选择 timetreehole 仓库                │"
    echo "  │  ④ 等待 Railway 读取根目录 railway.json        │"
    echo "  │     和 Dockerfile (自动使用 Dockerfile builder)│"
    echo "  │  ⑤ 点击 Deploy Now                             │"
    echo "  │  ⑥ 等待 3-5 分钟构建完成                       │"
    echo "  │     若提示找不到 dockerfile, 删服务重新部署   │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ┌─ 第 3 步：生成域名 ──────────────────────────┐"
    echo "  │  ① 部署完成后, 点击服务面板                    │"
    echo "  │  ② Settings → Networking → Generate Domain     │"
    echo "  │  ③ 获得域名: https://xxxx.railway.app          │"
    echo "  │  ④ 浏览器验证: https://<域名>/api/health       │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ┌─ 第 4 步：配置环境变量 ──────────────────────┐"
    echo "  │  在 Railway 控制台 → 服务 → Variables:         │"
    echo "  │  NODE_ENV                  = production        │"
    echo "  │  APPLE_SHARED_SECRET       = <App Store 共享密钥>│"
    echo "  │  APPLE_IAP_ENV             = sandbox            │"
    echo "  │  APNS_KEY_ID               = <Apple Developer Key ID>│"
    echo "  │  APNS_TEAM_ID              = <10位TeamID>      │"
    echo "  │  APNS_TOPIC                = com.carolqin.timetreehole│"
    echo "  │  (APNS/IAP 密钥上线前必须填入)                 │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ┌─ 第 5 步：更新 iOS 客户端 ───────────────────┐"
    echo "  │  编辑 TimeTreehole/Services/APIConfig.swift    │"
    echo "  │  把 baseURL 改成 Railway 分配的域名            │"
    echo "  │  static let baseURL =                          │"
    echo "  │    \"https://你的域名.up.railway.app\"           │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ┌─ 第 6 步：防休眠 ────────────────────────────┐"
    echo "  │  注册 https://uptimerobot.com                  │"
    echo "  │  添加 HTTP 监控: https://<域名>/api/health      │"
    echo "  │  间隔: 5 分钟                                 │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ✅ Railway 免费层优势："
    echo "     - 不要信用卡！GitHub 直接登录注册"
    echo "     - 自动 HTTPS (Let's Encrypt)"
    echo "     - 免费域名 *.railway.app"
    echo "     - 自动从 GitHub 构建 + 持续部署"
    echo "     - $5/月免费额度 (小 App 用不完)"
    echo "     - 支持 Dockerfile + Nixpacks 双构建方式"
    echo "     - 中国用户可以正常注册使用"
    echo ""
    echo "  ⚠️  免费层限制："
    echo "     - $5/月信用额度 (流量+CPU, 小 App 够用)"
    echo "     - 不活跃项目自动休眠"
    echo "     - 磁盘临时存储 (部署间数据不持久)"
    echo ""
    echo "  📖 完整部署文档: DEPLOYMENT.md"
    echo ""
}

# ============================================================
# iOS 构建上架 — Codemagic 免费层 (推荐, 无需 Mac)
# ============================================================
deploy_codemagic() {
    echo ""
    echo "  📱 Codemagic 免费构建 — 无需 Mac 自动上架"
    echo ""
    echo "  📋 前置条件："
    echo "     - Apple Developer 账号 (\$99/年, 唯一硬支出)"
    echo "     - App Store Connect API Key (.p8 文件)"
    echo "     - GitHub 仓库已推送代码"
    echo ""
    echo "  🔧 操作步骤："
    echo ""
    echo "  ┌─ 第 1 步：创建 App Store Connect API Key ─────┐"
    echo "  │  ① appstoreconnect.apple.com                  │"
    echo "  │  ② 用户和访问 → 密钥 → 生成                   │"
    echo "  │  ③ 权限选 App Manager                         │"
    echo "  │  ④ 下载 .p8 文件 (只能下载一次!)             │"
    echo "  │  ⑤ 记录 Issuer ID, Key ID, Team ID            │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ┌─ 第 2 步：填入 Team ID ──────────────────────┐"
    echo "  │  编辑 TimeTreehole/project.yml                │"
    echo "  │  DEVELOPMENT_TEAM: \"你的10位TeamID\"           │"
    echo "  │  Team ID 在 developer.apple.com → Membership  │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ┌─ 第 3 步：注册 Codemagic ────────────────────┐"
    echo "  │  ① 访问 codemagic.io, 用 GitHub 登录          │"
    echo "  │  ② Add Application → 选 GitHub 仓库           │"
    echo "  │  ③ 免费层: 500 分钟/月, Mac mini M1          │"
    echo "  └───���──────────────────────────────────────────┘"
    echo ""
    echo "  ┌─ 第 4 步：配置变量组 appstore_credentials ────┐"
    echo "  │  App settings → Environment variables:        │"
    echo "  │  APP_STORE_CONNECT_ISSUER_ID   = <Issuer ID>   │"
    echo "  │  APP_STORE_CONNECT_KEY         = <.p8 内容>   │"
    echo "  │  APP_STORE_CONNECT_KEY_IDENTIFIER = <Key ID>  │"
    echo "  │  DEVELOPMENT_TEAM_ID           = <Team ID>    │"
    echo "  │  每个变量勾选 Secure (加密)                   │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ┌─ 第 5 步：启动构建 ──────────────────────────┐"
    echo "  │  Start build (或 git push 到 main 自动触发)   │"
    echo "  │  等待 10-15 分钟                              │"
    echo "  │  Codemagic 自动完成:                          │"
    echo "  │    XcodeGen 安装 → 生成工程 → 编译归档         │"
    echo "  │    → 自动签名 → 上传 TestFlight                │"
    echo "  └───���──────────────────────────────────────────┘"
    echo ""
    echo "  ┌─ 第 6 步：TestFlight 测试 ───────────────────┐"
    echo "  │  ① iPhone 安装 TestFlight App                 │"
    echo "  │  ② App Store Connect → TestFlight → 加测试员  │"
    echo "  │  ③ 收到邮件 → 点击安装 → 真机测试              │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ⚠️  免费层限制（详见 DEPLOYMENT.md 第 4 节）："
    echo "     - 500 分钟/月, 约 30-50 次构建"
    echo "     - 不能交互调试 (无断点/模拟器)"
    echo "     - TestFlight 处理延迟 5-15 分钟"
    echo "     - 签名出错只能看 CI 日志排查"
    echo ""
    echo "  💡 完整部署文档: DEPLOYMENT.md (项目根目录)"
    echo ""
}

# ============================================================
# 入口
# ============================================================
case "$PLATFORM" in
    docker)
        deploy_docker
        ;;
    prod|production)
        deploy_prod
        ;;
    local|dev)
        deploy_local
        ;;
    vps|server)
        deploy_vps
        ;;
    railway)
        deploy_railway
        ;;
    cloud|render|fly|koyeb)
        echo ""
        echo "  ⚠️  该平台需要信用卡认证（国内银行卡通过率低），不推荐。"
        echo ""
        echo "  🚂  推荐使用 Railway（不要信用卡！）："
        echo "     bash deploy.sh railway"
        echo ""
        ;;
    codemagic|ios)
        deploy_codemagic
        ;;
    *)
        echo "用法: bash deploy.sh [平台]"
        echo ""
        echo "  平台:"
        echo "    docker     — 本地 Docker 测试部署"
        echo "    prod       — 生产环境 (API + Nginx + SSL)"
        echo "    local      — 本地 Node.js 开发"
        echo "    vps        — VPS 自建服务器指南"
        echo "    railway    — 云平台部署 (Railway, 推荐, 不要信用卡)"
        echo "    codemagic  — iOS 构建上架 (Codemagic 免费层)"
        echo ""
        echo "  📖 完整部署文档: DEPLOYMENT.md"
        echo ""
        ;;
esac
