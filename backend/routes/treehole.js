const express = require('express');
const multer  = require('multer');
const path    = require('path');
const fs      = require('fs');
const { v4: uuidv4 } = require('uuid');

const {
    getSeedByUuid,
    insertReply,
    incrementReplyCount,
    randomPublicSeed,
    countPublicSeeds,
    insertNotification,
    checkAndConsumeQuota,
    getBlockedUserIds,
} = require('../db');

const pushService = require('../services/push');

const router = express.Router();

// ============================================================
// Multer 配置 — 回复音频上传
// ============================================================

// 上传目录可由 UPLOAD_DIR 环境变量覆盖（Railway 持久卷方案）
const uploadDir = process.env.UPLOAD_DIR || path.join(__dirname, '..', 'uploads');
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        const dateDir = new Date().toISOString().slice(0, 10);
        const dir = path.join(uploadDir, dateDir);
        fs.mkdirSync(dir, { recursive: true });
        cb(null, dir);
    },
    filename: (req, file, cb) => {
        const ext = path.extname(file.originalname) || '.m4a';
        cb(null, `reply_${uuidv4()}${ext}`);
    }
});

const upload = multer({
    storage,
    limits: { fileSize: 20 * 1024 * 1024 },
    fileFilter: (req, file, cb) => {
        const allowed = ['.m4a', '.mp3', '.wav', '.aac', '.caf'];
        if (allowed.includes(path.extname(file.originalname).toLowerCase())) {
            cb(null, true);
        } else {
            cb(new Error('不支持的音频格式'));
        }
    }
});

// ============================================================
// GET /api/treehole/random — 随机获取一颗公共种子
// ============================================================

router.get('/random', (req, res) => {
    try {
        const excludeUuids = req.query.exclude
            ? req.query.exclude.split(',').filter(Boolean)
            : [];

        // 公共树洞「浏览」免费 —— 核心社交体验，不设灵叶门槛。
        // 否则 0 灵叶的新用户第 1 次免费浏览后每次都会被 402 挡死，看不到任何公共种子。
        // 灵叶仅用于「发布公共种子」等主动创作行为（见 seeds.js 的上传配额）。

        // 获取当前用户屏蔽列表，避免推荐被屏蔽用户的内容
        const blockedRows = getBlockedUserIds.all(req.user.id);
        const blockedUserIds = blockedRows.map(r => r.blocked_user_id);

        const seed = randomPublicSeed(req.user.id, excludeUuids, blockedUserIds);

        if (!seed) {
            return res.status(404).json({
                error: 'no_seeds',
                message: '公共树洞里暂时还没有种子，去做第一个播种的人吧 🌱',
                total: countPublicSeeds.get().total
            });
        }

        // 获取该种子的回复列表
        const { getRepliesBySeedId } = require('../db');
        const replies = getRepliesBySeedId.all(seed.id);

        res.json({
            seed: {
                uuid:         seed.uuid,
                title:        seed.title,
                duration:     seed.duration,
                replyCount:   seed.reply_count,
                createdAt:    seed.created_at,
                audioUrl:     `/api/seeds/${seed.uuid}/audio`,
                authorUserId: seed.user_id,
            },
            stats: {
                totalPublicSeeds: countPublicSeeds.get().total,
            },
        });
    } catch (err) {
        console.error('[Treehole] 随机种子失败:', err);
        res.status(500).json({ error: 'query_failed' });
    }
});

// ============================================================
// GET /api/treehole/stats — 公共树洞统计
// ============================================================

router.get('/stats', (req, res) => {
    try {
        res.json({
            totalPublicSeeds: countPublicSeeds.get().total,
        });
    } catch (err) {
        res.status(500).json({ error: 'query_failed' });
    }
});

// ============================================================
// POST /api/treehole/:uuid/reply — 匿名回复种子
// ============================================================

router.post('/:uuid/reply', upload.single('audio'), (req, res) => {
    try {
        // 查找目标种子
        const seed = getSeedByUuid.get(req.params.uuid);
        if (!seed) {
            return res.status(404).json({ error: 'not_found', message: '种子不存在' });
        }

        // 只能回复公开的种子
        if (seed.privacy !== 'public') {
            return res.status(403).json({ error: 'forbidden', message: '不能回复私密种子' });
        }

        // 不能回复自己的种子
        if (seed.user_id === req.user.id) {
            return res.status(400).json({ error: 'self_reply', message: '不能回复自己的种子' });
        }

        if (!req.file) {
            return res.status(400).json({ error: 'missing_file', message: '请提供评论音频' });
        }

        const replyUuid = uuidv4();
        const duration = parseFloat(req.body.duration) || 0;

        // 保存回复
        const reply = insertReply.get(
            replyUuid,
            seed.id,
            req.user.id,
            duration,
            req.file.path
        );

        // 增加回复计数
        incrementReplyCount.run(seed.uuid);

        // 重新获取种子以得到最新 reply_count
        const updatedSeed = getSeedByUuid.get(seed.uuid);

        // --- 生长阶段判定 ---
        const newCount = (seed.reply_count || 0) + 1;
        let stageType = null;

        if (newCount === 1) {
            // 第一条回复 → 发芽通知
            stageType = 'growth_sprout';
        } else if (newCount === 3) {
            stageType = 'growth_sapling';
        } else if (newCount === 6) {
            stageType = 'growth_tree';
        }

        // --- 发送通知给种子主人 ---
        const notifUuid = uuidv4();

        // 1) 新回复通知（每次都发）
        insertNotification.get(
            notifUuid,
            seed.user_id,
            'new_reply',
            seed.id,
            reply.id,
            '你的种子收到了新回复',
            `「${seed.title}」收到了一条匿名语音回复`
        );

        // 2) 生长阶段通知（仅关键节点）
        if (stageType) {
            const stageNames = {
                growth_sprout:  '你的种子发芽了！',
                growth_sapling: '你的种子长成幼苗了！',
                growth_tree:    '你的种子长成大树了！',
            };

            const stageBodies = {
                growth_sprout:  `「${seed.title}」收到了第1条回复，开始发芽`,
                growth_sapling: `「${seed.title}」已收到3条回复，茁壮成长中`,
                growth_tree:    `「${seed.title}」已收到${newCount}条回复，长成了一棵大树🌳`,
            };

            insertNotification.get(
                uuidv4(),
                seed.user_id,
                stageType,
                seed.id,
                null,
                stageNames[stageType],
                stageBodies[stageType]
            );
        }

        // --- 推送通知 ---
        const { getUserByDeviceId } = require('../db');
        const owner = getUserByDeviceId.get(seed.author_device_id);
        if (owner) {
            pushService.send(seed.user_id, {
                title:   '🌱 你的种子收到了新回复',
                body:    `「${seed.title}」收到了一条匿名语音回复`,
                type:    'new_reply',
                seedId:  seed.uuid,
                replyId: replyUuid,
                deviceId: seed.author_device_id,
            });
        }

        res.status(201).json({
            success: true,
            reply: {
                uuid:      replyUuid,
                duration:  duration,
                createdAt: reply.created_at,
            },
            seed: {
                uuid:       seed.uuid,
                replyCount: updatedSeed.reply_count,
                stage:      stageType || 'no_change',
            }
        });
    } catch (err) {
        console.error('[Treehole] 回复失败:', err);
        res.status(500).json({ error: 'reply_failed', message: err.message });
    }
});

module.exports = router;
