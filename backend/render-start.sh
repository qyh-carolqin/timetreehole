#!/bin/sh
# ============================================================
#  Render/Railway 启动脚本
#  非生产环境首次部署自动初始化演示数据；生产环境/数据库已存在时不碰数据
# ============================================================

set -e

echo ""
echo "  🌳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━🌳"
echo "  │      时间树洞 · Railway 启动中...        │"
echo "  └──────────────────────────────────────────┘"
echo ""
echo "  📋 检查数据库状态..."

# DB_PATH 必须从 DB_DIR 派生，避免被旧的 DB_PATH 环境变量误导到临时层
DB_DIR="${DB_DIR:-/app/data}"
DB_PATH="${DB_DIR}/timetreehole.db"
# 优先使用 UPLOAD_DIR（与 Railway 持久卷一致），向后兼容 UPLOADS_DIR
UPLOADS_DIR="${UPLOAD_DIR:-${UPLOADS_DIR:-/app/uploads}}"
PORT="${PORT:-3000}"

# 确保目录存在
mkdir -p "$(dirname "$DB_PATH")" "$UPLOADS_DIR"

# 生产环境绝不再跑 seed-demo.js（它会 DELETE FROM users/seeds/replies/notifications）
if [ "$NODE_ENV" = "production" ]; then
    echo "  ✅ 生产环境，跳过演示数据初始化"
elif [ -f "$DB_PATH" ]; then
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
