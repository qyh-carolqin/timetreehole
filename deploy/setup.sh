#!/bin/bash
# ============================================================
#  时间树洞 · 服务器一键部署（Ubuntu / Debian）
#
#  用法（root 执行）:
#    curl -fsSL <raw-url>/setup.sh -o setup.sh && bash setup.sh
#  或直接把仓库 deploy/ 目录拷到服务器后运行:
#    bash setup.sh
#
#  会做三件事:
#    1. 安装 Docker + Compose + sqlite3
#    2. 写入域名到 Caddyfile，启动 API + Caddy（自动 HTTPS）
#    3. 配置每日 4:00 自动备份（保留 7 天）
# ============================================================

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}"

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GRN}▶ $*${NC}"; }
warn() { echo -e "${YEL}⚠ $*${NC}"; }
die()  { echo -e "${RED}✗ $*${NC}"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "请用 root 执行: sudo bash setup.sh"

# ---------- 1. 依赖 ----------
if ! command -v docker >/dev/null 2>&1; then
    info "安装 Docker..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg sqlite3
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://get.docker.com | sh
else
    info "Docker 已安装: $(docker --version)"
fi

command -v sqlite3 >/dev/null 2>&1 || { info "安装 sqlite3..."; apt-get update -qq && apt-get install -y -qq sqlite3; }
docker compose version >/dev/null 2>&1 || die "未找到 docker compose 插件，请升级 Docker"

# ---------- 2. 域名 ----------
echo ""
read -rp "请输入已解析到本机的域名 (例: api.yourdomain.com): " DOMAIN
[ -n "${DOMAIN}" ] || die "域名不能为空"

info "写入 Caddyfile: ${DOMAIN}"
sed -i "s|^api\.example\.com {|${DOMAIN} {|" Caddyfile
grep -q "^${DOMAIN} {" Caddyfile || die "Caddyfile 写入失败，请手动检查"

# ---------- 3. 环境变量 ----------
if [ ! -f .env ]; then
    info "生成 .env"
    cat > .env <<'EOF'
# App Store Connect 内购共享密钥（无内购可留空）
APPLE_SHARED_SECRET=
EOF
    warn "已生成 .env，如需内购请填入 APPLE_SHARED_SECRET"
fi

# ---------- 4. 目录 ----------
mkdir -p data uploads backups
touch data/.gitkeep uploads/.gitkeep

# ---------- 5. 构建并启动 ----------
info "构建并启动服务（首次约 2-5 分钟）..."
docker compose up -d --build

# ---------- 6. 每日备份 ----------
CRON_LINE="0 4 * * * ${DIR}/backup.sh >> ${DIR}/backups/backup.log 2>&1"
if ! crontab -l 2>/dev/null | grep -Fq "${DIR}/backup.sh"; then
    info "配置每日 4:00 自动备份"
    ( crontab -l 2>/dev/null; echo "${CRON_LINE}" ) | crontab -
else
    info "备份定时任务已存在"
fi

# ---------- 7. 自检 ----------
echo ""
info "等待服务就绪..."
for i in $(seq 1 30); do
    if curl -fsS "https://${DOMAIN}/api/health" >/dev/null 2>&1; then
        echo ""
        info "🎉 部署成功！"
        echo -e "   API 地址: ${GRN}https://${DOMAIN}${NC}"
        echo -e "   健康检查: ${GRN}https://${DOMAIN}/api/health${NC}"
        echo -e "   隐私政策: ${GRN}https://${DOMAIN}/privacy.html${NC}"
        echo ""
        curl -fsS "https://${DOMAIN}/api/health"; echo ""
        echo ""
        warn "下一步: 把 iOS 端 APIConfig.swift 的 baseURL 改成 https://${DOMAIN}"
        exit 0
    fi
    sleep 5
done

warn "服务暂未就绪，可能证书还在申请。查看日志:"
echo "   cd ${DIR} && docker compose logs -f"
exit 1
