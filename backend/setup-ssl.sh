#!/bin/bash
# ============================================================
#  时间树洞 · SSL 证书初始化脚本
#  首次部署时运行，为 Nginx 获取 Let's Encrypt 证书
#
#  前提: docker-compose.prod.yml 中的 nginx 服务已启动
#  用法: bash setup-ssl.sh
# ============================================================

set -e

DOMAIN="${1:-api.timetreehole.com}"
EMAIL="${2:-admin@timetreehole.com}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  🌳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━🌳"
echo "  │      时间树洞 · SSL 证书初始化          │"
echo "  └──────────────────────────────────────────┘"
echo ""
echo "  域名: $DOMAIN"
echo "  邮箱: $EMAIL"
echo ""

# ============================================================
# Step 1: 检查 Docker 环境
# ============================================================
if ! command -v docker &> /dev/null; then
    echo "❌ 未安装 Docker"
    exit 1
fi

# ============================================================
# Step 2: 确保 Nginx 正在运行
# ============================================================
cd "$PROJECT_DIR"

if ! docker ps --format '{{.Names}}' | grep -q "timetreehole-nginx"; then
    echo "🚀 Nginx 未启动，先启动生产环境..."
    docker compose -f docker-compose.prod.yml up -d nginx api
    sleep 5
fi

# ============================================================
# Step 3: 获取 SSL 证书
# ============================================================
echo ""
echo "🔒 正在获取 Let's Encrypt SSL 证书..."

docker run --rm \
    -v "$PROJECT_DIR/nginx/ssl:/etc/letsencrypt" \
    -v "$PROJECT_DIR/nginx/www:/var/www/certbot" \
    certbot/certbot:latest \
    certonly --webroot \
    --webroot-path=/var/www/certbot \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    --force-renewal \
    -d "$DOMAIN"

# ============================================================
# Step 4: 重新加载 Nginx
# ============================================================
echo ""
echo "🔄 重新加载 Nginx 配置..."
docker exec timetreehole-nginx nginx -t
docker exec timetreehole-nginx nginx -s reload

# ============================================================
# Step 5: 验证
# ============================================================
echo ""
echo "✅ SSL 证书初始化完成！"
echo ""
echo "  验证 HTTPS:  curl https://$DOMAIN/api/health"
echo "  证书位置:    ./nginx/ssl/live/$DOMAIN/"
echo "  自动续期:    certbot 容器每 12 小时检查一次"
echo ""
