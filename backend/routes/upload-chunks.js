const express = require('express');
const fs      = require('fs');
const path    = require('path');
const { v4: uuidv4 } = require('uuid');

const {
    insertSeed,
    checkAndConsumeQuota,
} = require('../db');

const router = express.Router();

// ============================================================
// 真·分片上传 + 断点续传
// ------------------------------------------------------------
// 流程：
//   POST /api/uploads/init     → 建会话，写 meta + 清理过期会话，返回 uploadId
//   PUT  /api/uploads/chunk    → 逐片上传（raw binary，带 uploadId + index）
//   GET  /api/uploads/status   → 查询已接收分片（断点续传用）
//   POST /api/uploads/complete → 分片齐全则合并→落最终目录→走配额/私密降级→插库
//   POST /api/uploads/abort    → 放弃并清理临时目录
//
// 设计要点：
//   - 每片独立落盘 + 独立重试，慢链路下单片失败只重传该片，不再整段重来。
//   - 上传中途中断/重试时，客户端用 status 比对服务端已收分片，从断点继续，
//     彻底解决「跨境慢链路整段超时 → 种子丢失」的问题。
//   - 会话目录 uploads/.chunks/<uploadId>/，含 meta.json 与 part_00000…part_NNNNN。
//   - 所有写操作都校验 uploadId 合法性 + 会话归属（防目录穿越 / 越权）。
// ============================================================

const uploadDir  = process.env.UPLOAD_DIR || path.join(__dirname, '..', 'uploads');
const chunksRoot = path.join(uploadDir, '.chunks');

fs.mkdirSync(chunksRoot, { recursive: true });

// 临时会话过期时间（孤儿清理）：24 小时
const SESSION_TTL_MS = 24 * 60 * 60 * 1000;
const CHUNK_LIMIT    = 10 * 1024 * 1024; // 单分片上限 10MB

function sessionDir(uploadId) { return path.join(chunksRoot, uploadId); }
function metaPath(uploadId)   { return path.join(sessionDir(uploadId), 'meta.json'); }
function partPath(uploadId, index) {
    return path.join(sessionDir(uploadId), `part_${String(index).padStart(5, '0')}`);
}

/// 仅接受标准 uuid，杜绝目录穿越
function isValidUploadId(id) {
    return typeof id === 'string' &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id);
}

function readMeta(uploadId) {
    try {
        return JSON.parse(fs.readFileSync(metaPath(uploadId), 'utf8'));
    } catch (_) {
        return null;
    }
}

/// 返回 meta 前先校验会话归属当前用户；不通过返回 null
function ensureOwner(uploadId, userId) {
    const meta = readMeta(uploadId);
    if (!meta || meta.userId !== userId) return null;
    return meta;
}

/// 清理超过 TTL 的过期会话（防磁盘堆积孤儿）
function cleanupExpiredSessions() {
    try {
        const now = Date.now();
        for (const name of fs.readdirSync(chunksRoot)) {
            const dir = path.join(chunksRoot, name);
            try {
                if (!fs.statSync(dir).isDirectory()) continue;
                const meta = readMeta(name);
                const created = meta?.createdAt ? new Date(meta.createdAt).getTime() : 0;
                if (now - created > SESSION_TTL_MS) {
                    fs.rmSync(dir, { recursive: true, force: true });
                    console.log(`[Chunks] 清理过期会话: ${name}`);
                }
            } catch (_) { /* 无 meta 或读失败，忽略 */ }
        }
    } catch (_) { /* 目录不存在等，忽略 */ }
}

// ============================================================
// POST /api/uploads/init
// ============================================================
router.post('/init', express.json(), (req, res) => {
    try {
        cleanupExpiredSessions();

        const b = req.body || {};
        const fileName    = b.fileName    || b.file_name    || 'recording.m4a';
        const fileSize    = Number(b.fileSize ?? b.file_size) || 0;
        const totalChunks = Number(b.totalChunks ?? b.total_chunks);
        const mimeType    = b.mimeType    || b.mime_type    || 'audio/mp4';
        const title       = b.title       || '语音种子';
        const privacy     = b.privacy === 'public' ? 'public' : 'private';
        const duration    = parseFloat(b.duration) || 0;

        if (!Number.isInteger(totalChunks) || totalChunks <= 0) {
            return res.status(400).json({ error: 'invalid_totalChunks' });
        }

        const uploadId = uuidv4();
        const meta = {
            userId:      req.user.id,
            fileName,
            fileSize,
            totalChunks,
            mimeType,
            title,
            privacy,
            duration,
            createdAt:   new Date().toISOString(),
        };

        fs.mkdirSync(sessionDir(uploadId), { recursive: true });
        fs.writeFileSync(metaPath(uploadId), JSON.stringify(meta));

        res.status(201).json({ uploadId, totalChunks });
    } catch (err) {
        console.error('[Chunks] init 失败:', err);
        res.status(500).json({ error: 'init_failed' });
    }
});

// ============================================================
// PUT /api/uploads/chunk?uploadId=&index=
// body: raw binary（单分片）
// ============================================================
const rawBody = express.raw({ type: () => true, limit: CHUNK_LIMIT });

router.put('/chunk', rawBody, (req, res) => {
    try {
        const uploadId = req.query.uploadId;
        const index    = Number(req.query.index);

        if (!isValidUploadId(uploadId) || !Number.isInteger(index) || index < 0) {
            return res.status(400).json({ error: 'invalid_params' });
        }
        const meta = ensureOwner(uploadId, req.user.id);
        if (!meta) return res.status(404).json({ error: 'session_not_found' });
        if (index >= meta.totalChunks) return res.status(400).json({ error: 'index_out_of_range' });
        if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
            return res.status(400).json({ error: 'empty_body' });
        }

        // 覆盖写，天然幂等（同一 index 重传安全）
        fs.writeFileSync(partPath(uploadId, index), req.body);
        res.json({ ok: true, index, size: req.body.length });
    } catch (err) {
        console.error('[Chunks] chunk 失败:', err);
        res.status(500).json({ error: 'chunk_failed' });
    }
});

// ============================================================
// GET /api/uploads/status?uploadId=  → 断点续传查询
// ============================================================
router.get('/status', (req, res) => {
    try {
        const uploadId = req.query.uploadId;
        if (!isValidUploadId(uploadId)) {
            return res.status(400).json({ error: 'invalid_uploadId' });
        }
        const meta = ensureOwner(uploadId, req.user.id);
        if (!meta) return res.status(404).json({ error: 'session_not_found' });

        const received = [];
        for (let i = 0; i < meta.totalChunks; i++) {
            if (fs.existsSync(partPath(uploadId, i))) received.push(i);
        }
        res.json({
            uploadId,
            totalChunks: meta.totalChunks,
            received,
            complete: received.length === meta.totalChunks,
        });
    } catch (err) {
        console.error('[Chunks] status 失败:', err);
        res.status(500).json({ error: 'status_failed' });
    }
});

// ============================================================
// POST /api/uploads/complete?uploadId=  → 合并 + 落库
// ============================================================
router.post('/complete', express.json(), (req, res) => {
    const uploadId = req.query.uploadId;
    try {
        if (!isValidUploadId(uploadId)) {
            return res.status(400).json({ error: 'invalid_uploadId' });
        }
        const meta = ensureOwner(uploadId, req.user.id);
        if (!meta) return res.status(404).json({ error: 'session_not_found' });

        // 校验分片齐全
        const missing = [];
        const parts = [];
        for (let i = 0; i < meta.totalChunks; i++) {
            const p = partPath(uploadId, i);
            if (!fs.existsSync(p)) { missing.push(i); continue; }
            parts.push(fs.readFileSync(p));
        }
        if (missing.length > 0) {
            return res.status(409).json({ error: 'chunks_incomplete', missing });
        }

        // 合并
        const merged = Buffer.concat(parts);
        if (meta.fileSize > 0 && merged.length !== meta.fileSize) {
            fs.rmSync(sessionDir(uploadId), { recursive: true, force: true });
            return res.status(422).json({ error: 'size_mismatch', expected: meta.fileSize, actual: merged.length });
        }

        // 落最终目录：uploads/<date>/<uuid>.<ext>
        const ext = path.extname(meta.fileName) || '.m4a';
        const dateDir = new Date().toISOString().slice(0, 10);
        const finalDir = path.join(uploadDir, dateDir);
        fs.mkdirSync(finalDir, { recursive: true });
        const finalName = `${uuidv4()}${ext}`;
        const finalPath = path.join(finalDir, finalName);
        fs.writeFileSync(finalPath, merged);

        // 配额 / 私密降级（与 seeds.js 一致）
        const isPublic = meta.privacy === 'public';
        let quotaResult = null;
        let seed;

        if (isPublic) {
            quotaResult = checkAndConsumeQuota(req.user.id, 'upload');
            if (!quotaResult.allowed) {
                // 配额不足 → 自动降级私密，不丢录音、不留孤儿
                seed = insertSeed.get(
                    uuidv4(), req.user.id, meta.title, meta.duration,
                    'private', finalPath, merged.length
                );
                fs.rmSync(sessionDir(uploadId), { recursive: true, force: true });
                return res.status(201).json({
                    uuid: seed.uuid,
                    privacy: 'private',
                    audioUrl: `/api/seeds/${seed.uuid}/audio`,
                    savedAsPrivateDueToQuota: true,
                    quota: {
                        creditsNeeded: quotaResult.creditsNeeded,
                        userCredits:   quotaResult.userCredits,
                        message:       quotaResult.message,
                    },
                });
            }
        }

        seed = insertSeed.get(
            uuidv4(), req.user.id, meta.title, meta.duration,
            isPublic ? 'public' : 'private', finalPath, merged.length
        );
        fs.rmSync(sessionDir(uploadId), { recursive: true, force: true });

        res.status(201).json({
            uuid: seed.uuid,
            privacy: seed.privacy,
            audioUrl: `/api/seeds/${seed.uuid}/audio`,
            savedAsPrivateDueToQuota: false,
            quota: quotaResult ? {
                creditsUsed:    quotaResult.creditsUsed,
                remainingFree:  quotaResult.remainingFree,
            } : null,
        });
    } catch (err) {
        console.error('[Chunks] complete 失败:', err);
        // 出错保留分片以便客户端重试，仅清可能的不完整合并产物
        if (uploadId && isValidUploadId(uploadId)) {
            try { fs.rmSync(path.join(sessionDir(uploadId), 'merged.bin'), { force: true }); } catch (_) {}
        }
        res.status(500).json({ error: 'complete_failed' });
    }
});

// ============================================================
// POST /api/uploads/abort?uploadId=  → 放弃并清理
// ============================================================
router.post('/abort', express.json(), (req, res) => {
    try {
        const uploadId = req.query.uploadId;
        if (!isValidUploadId(uploadId)) {
            return res.status(400).json({ error: 'invalid_uploadId' });
        }
        const meta = ensureOwner(uploadId, req.user.id);
        if (!meta) return res.status(404).json({ error: 'session_not_found' });
        fs.rmSync(sessionDir(uploadId), { recursive: true, force: true });
        res.json({ success: true });
    } catch (err) {
        console.error('[Chunks] abort 失败:', err);
        res.status(500).json({ error: 'abort_failed' });
    }
});

module.exports = router;
