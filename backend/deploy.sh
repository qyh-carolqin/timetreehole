#!/bin/bash
# ============================================================
#  时间树洞 · 一键部署脚本 (增强版)
#  用法: bash deploy.sh [平台]
#
#  平台:
#    docker      — 本地 Docker 部署 (API only, 端口 3000)
#    prod        — 生产环境 Docker Compose (API + Nginx + SSL)
#    local       — 本地 Node.js 开发运行
#    cloud       — 云平台部署指南 (Railway / Render)
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
        echo "⚠��  请编辑 .env 填入实际配置后重新运行"
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
    echo "📦 本地开发运行..."
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
# 云平台：Render 免费部署（推荐）
# ============================================================
deploy_cloud() {
    echo ""
    echo "  ☁️  Render 免费部署 — 零成本、零运维"
    echo ""
    echo "  📋 前置条件："
    echo "     - GitHub 仓库（把项目 push 上去）"
    echo "     - Render 账号（https://render.com 用 GitHub 登录）"
    echo ""
    echo "  🔧 操作步骤（5 分钟）："
    echo ""
    echo "  ┌─ 第 1 步：Push 到 GitHub ─────────────────────┐"
    echo "  │  cd D:/时间树洞APP                           │"
    echo "  │  git init                                     │"
    echo "  │  git add .                                    │"
    echo "  │  git commit -m '🚀 初始提交 - 时间树洞'        │"
    echo "  │  git remote add origin <你的仓库地址>          │"
    echo "  │  git push -u origin main                      │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ┌─ 第 2 步：修改 render.yaml ───────────────────┐"
    echo "  │  编辑项目根目录的 render.yaml                  │"
    echo "  │  把 YOUR_USERNAME 改成你的 GitHub 用户名       │"
    echo "  │  repo: https://github.com/<你的用户名>/仓库名   │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ┌─ 第 3 步：Render 控制台操作 ─────────────────┐"
    echo "  │  ① 登录 https://dashboard.render.com          │"
    echo "  │  ② 点击 New → Blueprint                       │"
    echo "  │  ③ 连接 GitHub 仓库，选择 render.yaml          │"
    echo "  │  ④ Render 自动创建 Web Service：               │"
    echo "  │     - 检测 Dockerfile，自动构建镜像             │"
    echo "  │     - 分配免费域名 *.onrender.com              │"
    echo "  │     - 自动配置 HTTPS 证书                      │"
    echo "  │     - 健康检查 /api/health                     │"
    echo "  │     - 首次启动自动初始化演示数据                │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ┌─ 第 4 步：配置环境变量 ──────────────────────┐"
    echo "  │  在 Render Dashboard → Environment 设置:       │"
    echo "  │  APPLE_SHARED_SECRET = <从 App Store Connect>  │"
    echo "  │  APNS_KEY_ID        = <从 Apple Developer>     │"
    echo "  │  APNS_TEAM_ID       = <从 Apple Developer>     │"
    echo "  │  (IAP/推送上线前必须填入)                      │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ┌─ 第 5 步：更新 iOS 客户端 ───────────────────┐"
    echo "  │  编辑 TimeTreehole/Services/APIConfig.swift    │"
    echo "  │  把 baseURL 改成 Render 分配的域名             │"
    echo "  │  static let baseURL =                          │"
    echo "  │    \"https://timetreehole-api.onrender.com\"     │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    echo "  ⚠️  免费层限制（可接受）："
    echo "     - 15 分钟无请求后休眠，下次请求冷启动 ~30秒"
    echo "     - 磁盘是临时的（每次部署重新初始化 DB）"
    echo "     - 750 小时/月（刚好 24/7 运行）"
    echo "     - 月流量 100 GB（够用）"
    echo ""
    echo "  💡 解决休眠问题："
    echo "     用 uptimerobot.com 设一个免费监控，"
    echo "     每 5 分钟 ping 一次 /api/health，保持不休眠"
    echo ""
    echo "  📦 其他云平台："
    echo "     Railway: https://railway.app  ($5/月免费额度)"
    echo "     Fly.io:  fly launch --dockerfile Dockerfile"
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
    echo "  └──────────────────────────────────────────────┘"
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
    echo "  └──────────────────────────────────────────────┘"
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
    cloud|railway|render|fly)
        deploy_cloud
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
        echo "    cloud      — 云平台部署指南 (Render)"
        echo "    codemagic  — iOS 构建上架 (Codemagic 免费层)"
        echo ""
        echo "  📖 完整部署文档: DEPLOYMENT.md"
        echo ""
        ;;
esac
