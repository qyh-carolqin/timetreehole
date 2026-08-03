# ============================================================
#  时间树洞 · 后端 Docker 镜像
#  基于 Node 22 Debian Slim（原生模块兼容性好）
#  用于 Railway 等直接从根目录构建的平台
# ============================================================

FROM node:22-slim

WORKDIR /app

# better-sqlite3 编译依赖（无预编译二进制时需从源码编译）
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 make g++ && \
    rm -rf /var/lib/apt/lists/*

# 安装生产依赖
COPY backend/package.json ./
RUN npm install --omit=dev && \
    npm cache clean --force

# 复制后端源码
COPY backend/server.js backend/db.js ./
COPY backend/middleware/ ./middleware/
COPY backend/routes/     ./routes/
COPY backend/services/   ./services/
COPY backend/scripts/    ./scripts/

# 复制启动脚本
COPY backend/render-start.sh ./
RUN chmod +x render-start.sh

# 创建持久化目录
RUN mkdir -p /app/data /app/uploads

# 健康检查 — 使用 Node.js 发起 HTTP 请求，兼容所有 Linux 发行版
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD node -e "const http=require('http');http.get('http://localhost:3000/api/health',r=>{process.exit(r.statusCode===200?0:1)})"

EXPOSE 3000

ENV NODE_ENV=production

# 启动：检查/初始化 DB → 启动 API 服务
CMD ["sh", "render-start.sh"]
