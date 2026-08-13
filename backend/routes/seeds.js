const express = require('express');
const multer  = require('multer');
const path    = require('path');
const fs      = require('fs');
const { v4: uuidv4 } = require('uuid');

const {
    insertSeed,
    getSeedByUuid,
    getSeedsByUserId,
    deleteSeedByUuid,
    incrementReplyCount,
    updateSeedPrivacy,
    checkAndConsumeQuota,
} = require('../db');

const router = express.Router();

// ============================================================
// Multer 配置 — 音频上传
// ============================================================

const uploadDir = path.join(__dirname, '..', 'uploads');
fs.mkdirSync(uploadDir, { recursive: true });

const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        // 按日期分子目录
        const dateDir = new Date().toISOString().slice(0, 10);
        const dir = path.join(uploadDir, dateDir);
        fs.mkdirSync(dir, { recursive: true });
        cb(null, dir);
    },
    filename: (req, file, cb) => {
        const ext = path.extname(file.originalname) || '.m4a';
        cb(null, `${uuidv4()}${ext}`);
    }
});

const upload = multer({
    storage,
    limits: {
        fileSize: 20 * 1024 * 1024,  // 20MB 上限
    },
    fileFilter: (req, file, cb) => {
        const allowed = ['.m4a', '.mp3', '.wav', '.aac', '.caf'];
        const ext = path.extname(file.originalname).toLowerCase();
        if (allowed.includes(ext)) {
            cb(null, true);
        } else {
            cb(new Error(`不支持的音频格式: ${ext}。支持: ${allowed.join(', ')}`));
        }
    }
});

// ============================================================
// POST /api/seeds — 上传语音种子
// ============================================================

router.post('/', upload.single('audio'), (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ error: 'missing_file', message: '请提供音频文件' });
        }

        const { title, privacy } = req.body;
        const isPublic = privacy === 'public';

        // 公开种子 → 检查每日配额
        let quotaResult = null;
        if (isPublic) {
            quotaResult = checkAndConsumeQuota(req.user.id, 'upload');
            if (!quotaResult.allowed) {
                // 免费额度用完且灵叶不足 → 拒绝上传
                return res.status(402).json({
                    error: 'quota_exceeded',
                    message: quotaResult.message,
                    creditsNeeded: quotaResult.creditsNeeded,
                    userCredits: quotaResult.userCredits,
                });
            }
        }

        const uuid = uuidv4();
        const seed = insertSeed.get(
            uuid,
            req.user.id,
            title || '语音种子',
            0,
            isPublic ? 'public' : 'private',
            req.file.path,
            req.file.size
        );

        res.status(201).json({
            ...formatSeed(seed),
            quota: quotaResult ? {
                creditsUsed:    quotaResult.creditsUsed,
                remainingFree:  quotaResult.remainingFree,
            } : null,
        });
    } catch (err) {
        console.error('[Seeds] 上传失败:', err);
        res.status(500).json({ error: 'upload_failed', message: '种子保存失败' });
    }
});

// ============================================================
// POST /api/seeds/with-duration — 上传并指定时长
// ============================================================

router.post('/with-duration', upload.single('audio'), (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ error: 'missing_file', message: '请提供音频文件' });
        }

        const { title, privacy, duration } = req.body;
        const isPublic = privacy === 'public';

        // 公开种子 → 检查每日配额
        let quotaResult = null;
        if (isPublic) {
            quotaResult = checkAndConsumeQuota(req.user.id, 'upload');
            if (!quotaResult.allowed) {
                return res.status(402).json({
                    error: 'quota_exceeded',
                    message: quotaResult.message,
                    creditsNeeded: quotaResult.creditsNeeded,
                    userCredits: quotaResult.userCredits,
                });
            }
        }

        const uuid = uuidv4();
        const seed = insertSeed.get(
            uuid,
            req.user.id,
            title || '语音种子',
            parseFloat(duration) || 0,
            isPublic ? 'public' : 'private',
            req.file.path,
            req.file.size
        );

        res.status(201).json({
            ...formatSeed(seed),
            quota: quotaResult ? {
                creditsUsed:    quotaResult.creditsUsed,
                remainingFree:  quotaResult.remainingFree,
            } : null,
        });
    } catch (err) {
        console.error('[Seeds] 上传失败:', err);
        res.status(500).json({ error: 'upload_failed', message: '种子保存失败' });
    }
});

// ============================================================
// GET /api/my/seeds — 获取我的所有种子
// ============================================================

router.get('/my', (req, res) => {
    try {
        const seeds = getSeedsByUserId.all(req.user.id);
        res.json({
            seeds: seeds.map(formatSeed),
            total: seeds.length,
        });
    } catch (err) {
        console.error('[Seeds] 查询失败:', err);
        res.status(500).json({ error: 'query_failed' });
    }
});

// ============================================================
// GET /api/seeds/:uuid — 获取种子详情
// ============================================================

router.get('/:uuid', (req, res) => {
    try {
        const seed = getSeedByUuid.get(req.params.uuid);
        if (!seed) {
            return res.status(404).json({ error: 'not_found', message: '种子不存在' });
        }
        res.json(formatSeed(seed));
    } catch (err) {
        console.error('[Seeds] 查询失败:', err);
        res.status(500).json({ error: 'query_failed' });
    }
});

// ============================================================
// GET /api/seeds/:uuid/audio — 播放种子音频
// ============================================================

router.get('/:uuid/audio', (req, res) => {
    try {
        const seed = getSeedByUuid.get(req.params.uuid);
        if (!seed) {
            return res.status(404).json({ error: 'not_found' });
        }

        // 私密种子只能自己听
        if (seed.privacy === 'private' && seed.user_id !== req.user.id) {
            return res.status(403).json({ error: 'forbidden', message: '这是一颗私密种子' });
        }

        if (!fs.existsSync(seed.file_path)) {
            return res.status(404).json({ error: 'file_missing', message: '音频文件已丢失' });
        }

        const stat = fs.statSync(seed.file_path);
        res.writeHead(200, {
            'Content-Type': 'audio/mp4',
            'Content-Length': stat.size,
            'Accept-Ranges': 'bytes',
        });

        fs.createReadStream(seed.file_path).pipe(res);
    } catch (err) {
        console.error('[Seeds] 音频流失败:', err);
        res.status(500).json({ error: 'stream_failed' });
    }
});

// ============================================================
// DELETE /api/seeds/:uuid — 删除种子
// ============================================================

router.delete('/:uuid', (req, res) => {
    try {
        const seed = getSeedByUuid.get(req.params.uuid);
        if (!seed) {
            return res.status(404).json({ error: 'not_found' });
        }

        // 只能删除自己的种子
        if (seed.user_id !== req.user.id) {
            return res.status(403).json({ error: 'forbidden' });
        }

        // 删除音频文件
        if (fs.existsSync(seed.file_path)) {
            fs.unlinkSync(seed.file_path);
        }

        deleteSeedByUuid.run(req.params.uuid);
        res.json({ success: true });
    } catch (err) {
        console.error('[Seeds] 删除失败:', err);
        res.status(500).json({ error: 'delete_failed' });
    }
});

// ============================================================
// PATCH /api/seeds/:uuid/privacy — 修改种子私密/公域属性
// ============================================================

router.patch('/:uuid/privacy', (req, res) => {
    try {
        const { privacy } = req.body;
        if (privacy !== 'private' && privacy !== 'public') {
            return res.status(400).json({
                error: 'invalid_privacy',
                message: 'privacy 必须是 private 或 public',
            });
        }

        const seed = getSeedByUuid.get(req.params.uuid);
        if (!seed) {
            return res.status(404).json({ error: 'not_found', message: '种子不存在' });
        }

        // 只能修改自己的种子
        if (seed.user_id !== req.user.id) {
            return res.status(403).json({ error: 'forbidden', message: '只能修改自己的种子' });
        }

        const currentPrivacy = seed.privacy;
        const targetPrivacy = privacy;

        // 属性未变化
        if (currentPrivacy === targetPrivacy) {
            return res.json({
                success: true,
                privacy: targetPrivacy,
                changed: false,
                creditsUsed: 0,
            });
        }

        // 公域 → 私密：直接改，不退回灵叶
        if (currentPrivacy === 'public' && targetPrivacy === 'private') {
            updateSeedPrivacy.run('private', req.params.uuid, req.user.id);
            return res.json({
                success: true,
                privacy: 'private',
                changed: true,
                creditsUsed: 0,
                message: '已收回为私密种子',
            });
        }

        // 私密 → 公域：重新走上传配额（扣 10 灵叶 或 用每日免费额度）
        if (currentPrivacy === 'private' && targetPrivacy === 'public') {
            const quotaResult = checkAndConsumeQuota(req.user.id, 'upload');
            if (!quotaResult.allowed) {
                return res.status(402).json({
                    error: 'quota_exceeded',
                    message: quotaResult.message,
                    creditsNeeded: quotaResult.creditsNeeded,
                    userCredits: quotaResult.userCredits,
                });
            }

            updateSeedPrivacy.run('public', req.params.uuid, req.user.id);
            return res.json({
                success: true,
                privacy: 'public',
                changed: true,
                creditsUsed: quotaResult.creditsUsed,
                remainingFree: quotaResult.remainingFree,
                message: quotaResult.creditsUsed > 0
                    ? `种子已发布到公共域，消耗 ${quotaResult.creditsUsed} 灵叶`
                    : '种子已发布到公共域',
            });
        }

        return res.json({ success: true, privacy: targetPrivacy, changed: false });
    } catch (err) {
        console.error('[Seeds] 修改隐私失败:', err);
        res.status(500).json({ error: 'update_failed', message: '隐私修改失败' });
    }
});

// ============================================================
// 格式化输出
// ============================================================

function formatSeed(seed) {
    return {
        uuid:          seed.uuid,
        title:         seed.title,
        duration:      seed.duration,
        privacy:       seed.privacy,
        replyCount:    seed.reply_count,
        fileSize:      seed.file_size,
        createdAt:     seed.created_at,
        authorDevice:  seed.author_device_id || undefined,
        audioUrl:      `/api/seeds/${seed.uuid}/audio`,
    };
}

module.exports = router;
