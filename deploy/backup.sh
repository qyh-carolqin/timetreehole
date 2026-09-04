#!/bin/bash
# ============================================================
#  时间树洞 · 每日备份
#  备份 SQLite（热备份，保证一致性） + uploads 音频目录
#  默认保留最近 7 天
#  建议: crontab -e → 0 4 * * * /root/timetreehole/deploy/backup.sh
# ============================================================

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${DIR}/backups"
KEEP_DAYS="${KEEP_DAYS:-7}"
STAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "${BACKUP_DIR}"

# --- 1. 数据库热备份（sqlite3 .backup 比直接 cp 更安全）---
DB_SRC="${DIR}/data/timetreehole.db"
if [ ! -f "${DB_SRC}" ]; then
    echo "⚠️  未找到数据库 ${DB_SRC}，跳过数据库备份"
else
    if command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "${DB_SRC}" ".backup '${BACKUP_DIR}/db-${STAMP}.db'" \
            || cp "${DB_SRC}" "${BACKUP_DIR}/db-${STAMP}.db"
    else
        cp "${DB_SRC}" "${BACKUP_DIR}/db-${STAMP}.db"
    fi
    echo "✅ 数据库已备份 → db-${STAMP}.db"
fi

# --- 2. 音频文件备份 ---
if [ -d "${DIR}/uploads" ]; then
    tar czf "${BACKUP_DIR}/uploads-${STAMP}.tar.gz" -C "${DIR}/uploads" . \
        && echo "✅ 音频已备份 → uploads-${STAMP}.tar.gz"
fi

# --- 3. 清理过期备份 ---
find "${BACKUP_DIR}" -name 'db-*.db'            -mtime "+${KEEP_DAYS}" -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name 'uploads-*.tar.gz'   -mtime "+${KEEP_DAYS}" -delete 2>/dev/null || true

echo "🧹 已清理 ${KEEP_DAYS} 天前的旧备份"
echo "📦 当前备份占用: $(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1)"
