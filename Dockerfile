# ============================================================
#  时间树洞 · 后端 Docker 镜像 (项目根目录版本)
#  用于 Railway 等直接从根目录构建的平台
#  基于 Node 22 Alpine，轻量化部署
# ============================================================

FROM node:22-alpine AS builder

WORKDIR /app

# 安装编译工具（better-sqlite3 需要原生编译）
RUN apk add --no-cache python3 make g++

COPY backend/package.json ./
RUN npm install --production && \
    npm cache clean --force

# ============================================================
# 运行阶段
# ============================================================

FROM node:22-alpine

WORKDIR /app

# 从构建阶段复制依赖
COPY --from=builder /app/node_modules ./node_modules

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

# 健康检查
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:${PORT:-3000}/api/health || exit 1

EXPOSE 3000

ENV NODE_ENV=production

# 启动：先检查/初始化 DB，再启动服务
CMD ["sh", "render-start.sh"]
