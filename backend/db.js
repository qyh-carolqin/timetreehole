const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

// 确保数据目录存在
const dataDir = process.env.DB_DIR || path.join(__dirname, 'data');
try {
    fs.mkdirSync(dataDir, { recursive: true });
    console.log(`[DB] 数据目录: ${dataDir}`);
} catch (err) {
    console.error('[FATAL] 无法创建数据目录:', err.message);
    process.exit(1);
}

const DB_PATH = path.join(dataDir, 'timetreehole.db');

// 单例连接
let db;
try {
    db = new Database(DB_PATH);
    console.log(`[DB] SQLite 数据库已连接: ${DB_PATH}`);
} catch (err) {
    console.error('[FATAL] 无法打开数据库:', err.message);
    console.error(err.stack);
    process.exit(1);
}

// 开启 WAL 模式提升并发
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');
console.log('[DB] WAL 模式已启用');

// ============================================================
// 表结构初始化
// ============================================================

db.exec(`
    -- 用户表（匿名，仅用 deviceId 标识）
    CREATE TABLE IF NOT EXISTS users (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id     TEXT    NOT NULL UNIQUE,
        created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
        updated_at    TEXT    NOT NULL DEFAULT (datetime('now')),
        apns_token    TEXT,
        credits       INTEGER NOT NULL DEFAULT 0,
        nickname      TEXT,
        avatar_color  INTEGER NOT NULL DEFAULT 0,
        recovery_code TEXT,
        bio           TEXT
    );

    -- 语音种子表
    CREATE TABLE IF NOT EXISTS seeds (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid        TEXT    NOT NULL UNIQUE,
        user_id     INTEGER NOT NULL,
        title       TEXT    NOT NULL DEFAULT '语音种子',
        duration    REAL    NOT NULL DEFAULT 0,
        privacy     TEXT    NOT NULL CHECK(privacy IN ('private','public')) DEFAULT 'private',
        reply_count INTEGER NOT NULL DEFAULT 0,
        file_path   TEXT    NOT NULL,
        file_size   INTEGER NOT NULL DEFAULT 0,
        created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );

    -- 回复表
    CREATE TABLE IF NOT EXISTS replies (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid        TEXT    NOT NULL UNIQUE,
        seed_id     INTEGER NOT NULL,
        replier_id  INTEGER NOT NULL,
        duration    REAL    NOT NULL DEFAULT 0,
        file_path   TEXT    NOT NULL,
        created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (seed_id)   REFERENCES seeds(id) ON DELETE CASCADE,
        FOREIGN KEY (replier_id) REFERENCES users(id) ON DELETE CASCADE
    );

    -- 通知表
    CREATE TABLE IF NOT EXISTS notifications (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid        TEXT    NOT NULL UNIQUE,
        user_id     INTEGER NOT NULL,
        type        TEXT    NOT NULL CHECK(type IN ('new_reply','growth_sprout','growth_sapling','growth_tree')),
        seed_id     INTEGER,
        reply_id    INTEGER,
        title       TEXT    NOT NULL,
        body        TEXT    NOT NULL,
        is_read     INTEGER NOT NULL DEFAULT 0,
        created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY (seed_id) REFERENCES seeds(id) ON DELETE SET NULL
    );

    -- 每日用量表（追踪自由额度消耗）
    CREATE TABLE IF NOT EXISTS daily_usage (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id           INTEGER NOT NULL,
        date              TEXT    NOT NULL,
        public_uploads    INTEGER NOT NULL DEFAULT 0,
        public_retrievals INTEGER NOT NULL DEFAULT 0,
        UNIQUE(user_id, date),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );

    -- 消费记录表（用于审计和售后）
    CREATE TABLE IF NOT EXISTS credit_transactions (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     INTEGER NOT NULL,
        amount      INTEGER NOT NULL,
        reason      TEXT    NOT NULL,
        created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );

    -- 索引
    CREATE INDEX IF NOT EXISTS idx_seeds_user_id     ON seeds(user_id);
    CREATE INDEX IF NOT EXISTS idx_seeds_privacy     ON seeds(privacy);
    CREATE INDEX IF NOT EXISTS idx_seeds_created_at  ON seeds(created_at);
    CREATE INDEX IF NOT EXISTS idx_replies_seed_id   ON replies(seed_id);
    CREATE INDEX IF NOT EXISTS idx_notif_user_id     ON notifications(user_id);
    CREATE INDEX IF NOT EXISTS idx_notif_is_read     ON notifications(user_id, is_read);
    CREATE INDEX IF NOT EXISTS idx_users_device_id   ON users(device_id);
    CREATE INDEX IF NOT EXISTS idx_daily_usage_date  ON daily_usage(user_id, date);
    CREATE INDEX IF NOT EXISTS idx_credit_tx_user    ON credit_transactions(user_id);
`);

// 如果旧表已有 users 但没有 credits 列，追加（兼容性 ALTER）
try {
    db.exec(`ALTER TABLE users ADD COLUMN credits INTEGER NOT NULL DEFAULT 0`);
} catch (_) { /* 列已存在，忽略 */ }

// credit_transactions 追加 Apple IAP 相关列（兼容旧表）
try {
    db.exec(`ALTER TABLE credit_transactions ADD COLUMN transaction_id TEXT`);
} catch (_) { /* 列已存在 */ }
try {
    db.exec(`ALTER TABLE credit_transactions ADD COLUMN original_transaction_id TEXT`);
} catch (_) { /* 列已存在 */ }
try {
    db.exec(`ALTER TABLE credit_transactions ADD COLUMN receipt_data TEXT`);
} catch (_) { /* 列已存在 */ }
try {
    db.exec(`ALTER TABLE credit_transactions ADD COLUMN apple_product_id TEXT`);
} catch (_) { /* 列已存在 */ }
try {
    db.exec(`ALTER TABLE credit_transactions ADD COLUMN environment TEXT`);
} catch (_) { /* 列已存在 */ }

// Apple transaction_id 唯一索引（防重放）
try {
    db.exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_credit_tx_apple_id ON credit_transactions(transaction_id) WHERE transaction_id IS NOT NULL`);
} catch (_) { /* 已存在 */ }

// ============================================================
// 用户系统升级：匿名账号 + 设备标识 + 恢复码
// ============================================================

// users 表追加用户资料列（兼容旧表）
try { db.exec(`ALTER TABLE users ADD COLUMN nickname TEXT`); } catch (_) {}
try { db.exec(`ALTER TABLE users ADD COLUMN avatar_color INTEGER NOT NULL DEFAULT 0`); } catch (_) {}
try { db.exec(`ALTER TABLE users ADD COLUMN recovery_code TEXT`); } catch (_) {}
try { db.exec(`ALTER TABLE users ADD COLUMN bio TEXT`); } catch (_) {}
try { db.exec(`ALTER TABLE users ADD COLUMN updated_at TEXT`); } catch (_) {}

// 回填 updated_at 为 NULL 的行
try { db.exec(`UPDATE users SET updated_at = datetime('now') WHERE updated_at IS NULL`); } catch (_) {}

// recovery_code 唯一索引
try {
    db.exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_users_recovery_code ON users(recovery_code) WHERE recovery_code IS NOT NULL`);
} catch (_) { /* 已存在 */ }

// 设备表（多设备绑定）
db.exec(`
    CREATE TABLE IF NOT EXISTS devices (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id       INTEGER NOT NULL,
        device_id     TEXT    NOT NULL,
        platform      TEXT    NOT NULL DEFAULT 'ios',
        model         TEXT,
        last_active_at TEXT   NOT NULL DEFAULT (datetime('now')),
        created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
        UNIQUE(device_id),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);
`);

// ============================================================
// 费用常量
// ============================================================

const QUOTA = {
    FREE_DAILY_UPLOADS:     1,   // 每天免费上传公共种子数
    FREE_DAILY_RETRIEVALS:  1,   // 每天免费获取公共种子数
    COST_EXTRA_UPLOAD:      10,  // 超限后每次上传消耗的灵叶数
    COST_EXTRA_RETRIEVAL:   5,   // 超限后每次获取消耗的灵叶数
};

const RECHARGE_PACKAGES = [
    { id: 'small',  name: '一袋灵叶', credits: 50,  price: 6,   desc: '50 灵叶 · ¥6',  appleProductId: 'com.timetreehole.credits.small' },
    { id: 'medium', name: '一捧灵叶', credits: 120, price: 12,  desc: '120 灵叶 · ¥12', appleProductId: 'com.timetreehole.credits.medium', popular: true },
    { id: 'large',  name: '一篮灵叶', credits: 300, price: 25,  desc: '300 灵叶 · ¥25', appleProductId: 'com.timetreehole.credits.large' },
];

/// 根据 Apple productID 查找套餐
function findPackageByAppleProductId(appleProductId) {
    return RECHARGE_PACKAGES.find(p => p.appleProductId === appleProductId) || null;
}

/// 根据套餐 ID 查找 Apple productID
function findAppleProductId(packageId) {
    const pkg = RECHARGE_PACKAGES.find(p => p.id === packageId);
    return pkg ? pkg.appleProductId : null;
}

// ============================================================
// Prepared Statements — Users
// ============================================================

const findOrCreateUser = db.prepare(`
    INSERT INTO users (device_id)
    VALUES (?)
    ON CONFLICT(device_id) DO UPDATE SET device_id=device_id
    RETURNING *
`);

const getUserByDeviceId = db.prepare(`
    SELECT * FROM users WHERE device_id = ?
`);

const updateApnsToken = db.prepare(`
    UPDATE users SET apns_token = ? WHERE device_id = ?
`);

const addCredits = db.prepare(`
    UPDATE users SET credits = credits + ? WHERE id = ?
`);

const deductCredits = db.prepare(`
    UPDATE users SET credits = credits - ? WHERE id = ? AND credits >= ?
`);

// ============================================================
// Prepared Statements — 用户资料 & 设备管理
// ============================================================

/// 注册匿名用户（带昵称和恢复码）
const registerUser = db.prepare(`
    INSERT INTO users (device_id, nickname, avatar_color, recovery_code, updated_at)
    VALUES (?, ?, ?, ?, datetime('now'))
    ON CONFLICT(device_id) DO UPDATE SET
        nickname      = COALESCE(excluded.nickname, users.nickname),
        avatar_color  = COALESCE(excluded.avatar_color, users.avatar_color),
        recovery_code = COALESCE(excluded.recovery_code, users.recovery_code),
        updated_at    = datetime('now')
    RETURNING *
`);

/// 更新用户资料
const updateUserProfile = db.prepare(`
    UPDATE users
    SET nickname     = COALESCE(?, nickname),
        avatar_color = COALESCE(?, avatar_color),
        bio          = COALESCE(?, bio),
        updated_at   = datetime('now')
    WHERE id = ?
    RETURNING *
`);

/// 按恢复码查用户（用于设备迁移/恢复）
const getUserByRecoveryCode = db.prepare(`
    SELECT * FROM users WHERE recovery_code = ?
`);

/// 将设备绑定到已有用户（恢复账号时使用）
const bindDeviceToUser = db.prepare(`
    UPDATE users
    SET device_id = ?, updated_at = datetime('now')
    WHERE id = ?
    RETURNING *
`);

/// 删除无数据的匿名用户（恢复账号时清理）
const deleteEmptyUser = db.prepare(`
    DELETE FROM users
    WHERE id = ? AND credits = 0
      AND NOT EXISTS (SELECT 1 FROM seeds WHERE seeds.user_id = users.id)
      AND NOT EXISTS (SELECT 1 FROM credit_transactions WHERE credit_transactions.user_id = users.id)
`);

/// 按用户 ID 查用户
const getUserById = db.prepare(`
    SELECT * FROM users WHERE id = ?
`);

// ---- 设备表 ----

/// 插入或更新设备记录
const upsertDevice = db.prepare(`
    INSERT INTO devices (user_id, device_id, platform, model)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(device_id) DO UPDATE SET
        user_id       = excluded.user_id,
        platform      = excluded.platform,
        model         = COALESCE(excluded.model, devices.model),
        last_active_at = datetime('now')
    RETURNING *
`);

/// 查询用户绑定的所有设备
const getDevicesByUserId = db.prepare(`
    SELECT * FROM devices WHERE user_id = ? ORDER BY last_active_at DESC
`);

/// 删除设备绑定
const deleteDevice = db.prepare(`
    DELETE FROM devices WHERE id = ? AND user_id = ?
`);

/// 按 device_id 查设备
const getDeviceByDeviceId = db.prepare(`
    SELECT * FROM devices WHERE device_id = ?
`);

// ============================================================
// 用户系统辅助函数
// ============================================================

const crypto = require('crypto');

/// 生成 8 位恢复码（格式: XXXX-XXXX，大写字母+数字）
function generateRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 排除易混淆字符
    let code;
    let attempts = 0;
    do {
        let raw = '';
        for (let i = 0; i < 8; i++) {
            raw += chars[Math.floor(Math.random() * chars.length)];
        }
        code = raw.slice(0, 4) + '-' + raw.slice(4);
        attempts++;
    } while (getUserByRecoveryCode.get(code) && attempts < 10);
    return code;
}

/// 随机昵称生成器（自然系词库）
const NATURE_PREFIXES = ['萤火', '晨雾', '星苔', '林溪', '风铃', '月穗', '松果', '露珠', '竹影', '雪原', '橡叶', '潮汐'];
const NATURE_SUFFIXES = ['旅人', '访客', '漫步者', '守望者', '拾光者', '寄信人', '拾叶人', '听风者', '寻声者', '种树人'];

function generateNickname() {
    const prefix = NATURE_PREFIXES[Math.floor(Math.random() * NATURE_PREFIXES.length)];
    const suffix = NATURE_SUFFIXES[Math.floor(Math.random() * NATURE_SUFFIXES.length)];
    const num = Math.floor(Math.random() * 900 + 100);
    return `${prefix}${suffix}${num}`;
}

// ============================================================
// Prepared Statements — Seeds
// ============================================================

const insertSeed = db.prepare(`
    INSERT INTO seeds (uuid, user_id, title, duration, privacy, file_path, file_size)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    RETURNING *
`);

const getSeedByUuid = db.prepare(`
    SELECT s.*, u.device_id as author_device_id
    FROM seeds s
    JOIN users u ON s.user_id = u.id
    WHERE s.uuid = ?
`);

const getSeedsByUserId = db.prepare(`
    SELECT * FROM seeds
    WHERE user_id = ?
    ORDER BY created_at DESC
`);

const deleteSeedByUuid = db.prepare(`
    DELETE FROM seeds WHERE uuid = ?
`);

const incrementReplyCount = db.prepare(`
    UPDATE seeds SET reply_count = reply_count + 1 WHERE uuid = ?
`);

const updateSeedPrivacy = db.prepare(`
    UPDATE seeds SET privacy = ? WHERE uuid = ? AND user_id = ?
`);

// ============================================================
// Prepared Statements — Treehole (公共树洞)
// ============================================================

function randomPublicSeed(userId, excludeUuids) {
    if (excludeUuids.length === 0) {
        return db.prepare(`
            SELECT s.*, u.device_id as author_device_id
            FROM seeds s
            JOIN users u ON s.user_id = u.id
            WHERE s.privacy = 'public'
              AND s.user_id != ?
            ORDER BY RANDOM()
            LIMIT 1
        `).get(userId);
    }

    const placeholders = excludeUuids.map(() => '?').join(',');
    const stmt = db.prepare(`
        SELECT s.*, u.device_id as author_device_id
        FROM seeds s
        JOIN users u ON s.user_id = u.id
        WHERE s.privacy = 'public'
          AND s.user_id != ?
          AND s.uuid NOT IN (${placeholders})
        ORDER BY RANDOM()
        LIMIT 1
    `);
    return stmt.get(userId, ...excludeUuids);
}

const countPublicSeeds = db.prepare(`
    SELECT COUNT(*) as total FROM seeds WHERE privacy = 'public'
`);

// ============================================================
// Prepared Statements — Replies
// ============================================================

const insertReply = db.prepare(`
    INSERT INTO replies (uuid, seed_id, replier_id, duration, file_path)
    VALUES (?, ?, ?, ?, ?)
    RETURNING *
`);

const getRepliesBySeedId = db.prepare(`
    SELECT r.*, u.device_id as replier_device_id
    FROM replies r
    JOIN users u ON r.replier_id = u.id
    WHERE r.seed_id = ?
    ORDER BY r.created_at ASC
`);

// ============================================================
// Prepared Statements — Notifications
// ============================================================

const insertNotification = db.prepare(`
    INSERT INTO notifications (uuid, user_id, type, seed_id, reply_id, title, body)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    RETURNING *
`);

const getNotificationsByUserId = db.prepare(`
    SELECT * FROM notifications
    WHERE user_id = ?
    ORDER BY created_at DESC
    LIMIT 50
`);

const markNotificationRead = db.prepare(`
    UPDATE notifications SET is_read = 1 WHERE uuid = ? AND user_id = ?
`);

const markAllNotificationsRead = db.prepare(`
    UPDATE notifications SET is_read = 1 WHERE user_id = ? AND is_read = 0
`);

const countUnreadNotifications = db.prepare(`
    SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND is_read = 0
`);

// ============================================================
// Prepared Statements — 配额与额度
// ============================================================

// 注意：用 date('now', '+8 hours') 按「中国时区(UTC+8)」划分每日，
// 保证每日免费额度在中国 0:00 重置（而非 UTC 0:00 = 中国 8:00）。
// 中国无夏令时，+8 小时即可长期稳定对齐。
const getTodayUsage = db.prepare(`
    SELECT * FROM daily_usage WHERE user_id = ? AND date = date('now', '+8 hours')
`);

const upsertDailyUsage = db.prepare(`
    INSERT INTO daily_usage (user_id, date, public_uploads, public_retrievals)
    VALUES (?, date('now', '+8 hours'), ?, ?)
    ON CONFLICT(user_id, date) DO UPDATE SET
        public_uploads    = public_uploads    + excluded.public_uploads,
        public_retrievals = public_retrievals + excluded.public_retrievals
    RETURNING *
`);

const insertCreditTransaction = db.prepare(`
    INSERT INTO credit_transactions (user_id, amount, reason) VALUES (?, ?, ?)
`);

const insertIAPTransaction = db.prepare(`
    INSERT INTO credit_transactions (user_id, amount, reason, transaction_id, original_transaction_id, receipt_data, apple_product_id, environment)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
`);

const findTransactionByAppleId = db.prepare(`
    SELECT id FROM credit_transactions WHERE transaction_id = ? LIMIT 1
`);

// ============================================================
// 额度辅助函数
// ============================================================

/**
 * 检查并消耗配额：如果免费额度够用，就增量记录；如果不够且用户有灵叶，就扣费
 * @returns {{ allowed: boolean, creditsUsed: number, message: string }}
 */
function checkAndConsumeQuota(userId, actionType) {
    const today = getTodayUsage.get(userId);
    const user = db.prepare('SELECT credits FROM users WHERE id = ?').get(userId);
    const userCredits = user?.credits || 0;

    if (actionType === 'upload') {
        const usedCount = today?.public_uploads || 0;

        if (usedCount < QUOTA.FREE_DAILY_UPLOADS) {
            // 免费额度内
            upsertDailyUsage.run(userId, 1, 0);
            return {
                allowed: true,
                creditsUsed: 0,
                remainingFree: QUOTA.FREE_DAILY_UPLOADS - usedCount - 1,
                message: `今日免费上传剩余 ${QUOTA.FREE_DAILY_UPLOADS - usedCount - 1} 次`
            };
        } else {
            // 检查灵叶是否足够
            if (userCredits >= QUOTA.COST_EXTRA_UPLOAD) {
                deductCredits.run(QUOTA.COST_EXTRA_UPLOAD, userId, QUOTA.COST_EXTRA_UPLOAD);
                upsertDailyUsage.run(userId, 1, 0);
                insertCreditTransaction.run(userId, -QUOTA.COST_EXTRA_UPLOAD, 'upload');
                return {
                    allowed: true,
                    creditsUsed: QUOTA.COST_EXTRA_UPLOAD,
                    remainingCredits: userCredits - QUOTA.COST_EXTRA_UPLOAD,
                    message: `已消耗 ${QUOTA.COST_EXTRA_UPLOAD} 灵叶上传种子`
                };
            } else {
                return {
                    allowed: false,
                    creditsUsed: 0,
                    creditsNeeded: QUOTA.COST_EXTRA_UPLOAD,
                    userCredits: userCredits,
                    message: `灵叶不足！上传公共种子需要 ${QUOTA.COST_EXTRA_UPLOAD} 灵叶，你当前有 ${userCredits} 灵叶。前往商店充值 →`
                };
            }
        }
    }

    if (actionType === 'retrieval') {
        const usedCount = today?.public_retrievals || 0;

        if (usedCount < QUOTA.FREE_DAILY_RETRIEVALS) {
            upsertDailyUsage.run(userId, 0, 1);
            return {
                allowed: true,
                creditsUsed: 0,
                remainingFree: QUOTA.FREE_DAILY_RETRIEVALS - usedCount - 1,
                message: `今日免费获取剩余 ${QUOTA.FREE_DAILY_RETRIEVALS - usedCount - 1} 次`
            };
        } else {
            if (userCredits >= QUOTA.COST_EXTRA_RETRIEVAL) {
                deductCredits.run(QUOTA.COST_EXTRA_RETRIEVAL, userId, QUOTA.COST_EXTRA_RETRIEVAL);
                upsertDailyUsage.run(userId, 0, 1);
                insertCreditTransaction.run(userId, -QUOTA.COST_EXTRA_RETRIEVAL, 'retrieval');
                return {
                    allowed: true,
                    creditsUsed: QUOTA.COST_EXTRA_RETRIEVAL,
                    remainingCredits: userCredits - QUOTA.COST_EXTRA_RETRIEVAL,
                    message: `已消耗 ${QUOTA.COST_EXTRA_RETRIEVAL} 灵叶获取种子`
                };
            } else {
                return {
                    allowed: false,
                    creditsUsed: 0,
                    creditsNeeded: QUOTA.COST_EXTRA_RETRIEVAL,
                    userCredits: userCredits,
                    message: `灵叶不足！获取公共种子需要 ${QUOTA.COST_EXTRA_RETRIEVAL} 灵叶，你当前有 ${userCredits} 灵叶。前往商店充值 →`
                };
            }
        }
    }

    return { allowed: false, creditsUsed: 0, message: '未知操作类型' };
}

// ============================================================
// 导出接口
// ============================================================

module.exports = {
    db,

    // 常量
    QUOTA,
    RECHARGE_PACKAGES,
    findPackageByAppleProductId,
    findAppleProductId,

    // Users
    findOrCreateUser,
    getUserByDeviceId,
    updateApnsToken,
    addCredits,
    deductCredits,

    // Seeds
    insertSeed,
    getSeedByUuid,
    getSeedsByUserId,
    deleteSeedByUuid,
    incrementReplyCount,
    updateSeedPrivacy,

    // Treehole
    randomPublicSeed,
    countPublicSeeds,

    // Replies
    insertReply,
    getRepliesBySeedId,

    // Notifications
    insertNotification,
    getNotificationsByUserId,
    markNotificationRead,
    markAllNotificationsRead,
    countUnreadNotifications,

    // 配额
    getTodayUsage,
    upsertDailyUsage,
    insertCreditTransaction,
    insertIAPTransaction,
    findTransactionByAppleId,
    checkAndConsumeQuota,

    // 用户资料 & 设备管理
    registerUser,
    updateUserProfile,
    getUserByRecoveryCode,
    bindDeviceToUser,
    deleteEmptyUser,
    getUserById,
    upsertDevice,
    getDevicesByUserId,
    deleteDevice,
    getDeviceByDeviceId,
    generateRecoveryCode,
    generateNickname,
};
