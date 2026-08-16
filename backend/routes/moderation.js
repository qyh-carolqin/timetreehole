const express = require('express');
const {
    reportSeed,
    blockUser,
    unblockUser,
    getBlockedUserIds,
    getBlockedUsers,
    deleteAccount,
} = require('../db');

const router = express.Router();

// ============================================================
// POST /api/moderation/report — 举报种子/内容
// Body: { seedUuid: string, reason?: string }
// ============================================================
router.post('/report', (req, res) => {
    try {
        const { seedUuid, reason } = req.body;
        if (!seedUuid || typeof seedUuid !== 'string') {
            return res.status(400).json({ error: 'missing_seed_uuid' });
        }

        const report = reportSeed(req.user.id, seedUuid, reason || '');
        res.json({
            success: true,
            report: {
                id: report.id,
                status: report.status,
                createdAt: report.created_at,
            }
        });
    } catch (err) {
        if (err.message === 'seed_not_found') {
            return res.status(404).json({ error: 'seed_not_found' });
        }
        if (err.message === 'already_reported') {
            return res.status(409).json({ error: 'already_reported', message: '你已经举报过该内容' });
        }
        console.error('[Moderation] 举报失败:', err);
        res.status(500).json({ error: 'report_failed' });
    }
});

// ============================================================
// POST /api/moderation/block — 屏蔽某用户
// Body: { targetUserId: number }
// ============================================================
router.post('/block', (req, res) => {
    try {
        const targetUserId = parseInt(req.body.targetUserId, 10);
        if (!targetUserId || isNaN(targetUserId)) {
            return res.status(400).json({ error: 'missing_target_user_id' });
        }

        const block = blockUser(req.user.id, targetUserId);
        res.json({
            success: true,
            block: {
                id: block.id,
                blockedUserId: block.blocked_user_id,
                createdAt: block.created_at,
            }
        });
    } catch (err) {
        if (err.message === 'cannot_block_self') {
            return res.status(400).json({ error: 'cannot_block_self' });
        }
        if (err.message === 'user_not_found') {
            return res.status(404).json({ error: 'user_not_found' });
        }
        console.error('[Moderation] 屏蔽失败:', err);
        res.status(500).json({ error: 'block_failed' });
    }
});

// ============================================================
// DELETE /api/moderation/block/:targetUserId — 取消屏蔽
// ============================================================
router.delete('/block/:targetUserId', (req, res) => {
    try {
        const targetUserId = parseInt(req.params.targetUserId, 10);
        if (!targetUserId || isNaN(targetUserId)) {
            return res.status(400).json({ error: 'invalid_target_user_id' });
        }

        unblockUser(req.user.id, targetUserId);
        res.json({ success: true });
    } catch (err) {
        console.error('[Moderation] 取消屏蔽失败:', err);
        res.status(500).json({ error: 'unblock_failed' });
    }
});

// ============================================================
// GET /api/moderation/blocked — 当前用户屏蔽列表
// ============================================================
router.get('/blocked', (req, res) => {
    try {
        const list = getBlockedUsers.all(req.user.id);
        res.json({
            blocked: list.map(b => ({
                id: b.id,
                blockedUserId: b.blocked_user_id,
                deviceId: b.device_id,
                nickname: b.nickname,
                avatarColor: b.avatar_color,
                createdAt: b.created_at,
            }))
        });
    } catch (err) {
        console.error('[Moderation] 获取屏蔽列表失败:', err);
        res.status(500).json({ error: 'query_failed' });
    }
});

// ============================================================
// DELETE /api/account — 删除当前账号及所有数据
// ============================================================
router.delete('/account', (req, res) => {
    try {
        const result = deleteAccount(req.user.id);
        if (!result.success) {
            return res.status(404).json({ error: 'account_not_found' });
        }
        res.json({
            success: true,
            message: '账号及关联数据已删除',
            deletedFiles: result.deletedFiles,
        });
    } catch (err) {
        console.error('[Moderation] 账号删除失败:', err);
        res.status(500).json({ error: 'delete_account_failed' });
    }
});

module.exports = router;
