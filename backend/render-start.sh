#!/bin/sh
# ============================================================
#  Render 启动脚本
#  首次部署自动初始化演示数据，后续重启不动数据
# ============================================================

set -e

echo ""
echo "  🌳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━🌳"
echo "  │      时间树洞 · Render 启动中...        │"
echo "  └──────────────────────────────────────────┘"
echo ""
echo "  📋 检查数据库状态..."

DB_PATH="${DB_PATH:-/app/data/timetreehole.db}"
UPLOADS_DIR="${UPLOADS_DIR:-/app/uploads}"
PORT="${PORT:-3000}"

# 确保目录存在
mkdir -p "$(dirname "$DB_PATH")" "$UPLOADS_DIR"

if [ -f "$DB_PATH" ]; then
    echo "  ✅ 数据库已存在，跳过种子数据初始化"
else
    echo "  🌱 首次启动：初始化演示数据..."
    node scripts/seed-demo.js
    echo "  ✅ 种子数据初始化完成"
fi

echo ""
echo "  🚀 启动 API 服务 (端口 $PORT)..."
echo ""

exec node server.js
