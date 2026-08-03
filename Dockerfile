# ============================================================
#  时间树洞 · 后端 Docker 镜像
#  基于 Node 22 完整镜像（最大兼容性）
#  用于 Railway 等从根目录构建的平台
# ============================================================

FROM node:22

WORKDIR /app

# 复制 package.json 并安装依赖
COPY backend/package.json ./
RUN npm install --omit=dev && npm cache clean --force

# 🔍 诊断: 验证 better-sqlite3 能正常加载
RUN node -e "const db=require('better-sqlite3'); console.log('✅ better-sqlite3 加载成功, 版本:', require('better-sqlite3/package.json').version)"

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

# 健康检查 — 使用 Node.js 发起 HTTP 请求
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "const http=require('http');http.get('http://localhost:3000/api/health',r=>{process.exit(r.statusCode===200?0:1)})"

EXPOSE 3000

ENV NODE_ENV=production
ENV PORT=3000

CMD ["sh", "render-start.sh"]
