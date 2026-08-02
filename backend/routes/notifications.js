const express = require('express');
const {
    getNotificationsByUserId,
    markNotificationRead,
    markAllNotificationsRead,
    countUnreadNotifications,
} = require('../db');

const router = express.Router();

// ============================================================
// GET /api/notifications — 获取我的通知列表
// ============================================================

router.get('/', (req, res) => {
    try {
        const limit = Math.min(parseInt(req.query.limit) || 50, 100);
        const offset = parseInt(req.query.offset) || 0;

        const notifications = getNotificationsByUserId.all(req.user.id);
        const unread = countUnreadNotifications.get(req.user.id);

        // 分页
        const paged = notifications.slice(offset, offset + limit);

        res.json({
            notifications: paged.map(formatNotification),
            total: notifications.length,
            unread: unread?.count ?? 0,
        });
    } catch (err) {
        console.error('[Notif] 查询失败:', err);
        res.status(500).json({ error: 'query_failed' });
    }
});

// ============================================================
// GET /api/notifications/unread-count — 获取未读数
// ============================================================

router.get('/unread-count', (req, res) => {
    try {
        const result = countUnreadNotifications.get(req.user.id);
        res.json({ count: result?.count ?? 0 });
    } catch (err) {
        res.status(500).json({ error: 'query_failed' });
    }
});

// ============================================================
// PUT /api/notifications/:uuid/read — 标记单条已读
// ============================================================

router.put('/:uuid/read', (req, res) => {
    try {
        const result = markNotificationRead.run(req.params.uuid, req.user.id);
        if (result.changes === 0) {
            return res.status(404).json({ error: 'not_found' });
        }
        res.json({ success: true });
    } catch (err) {
        console.error('[Notif] 标记已读失败:', err);
        res.status(500).json({ error: 'update_failed' });
    }
});

// ============================================================
// PUT /api/notifications/read-all — 全部标记已读
// ============================================================

router.put('/read-all', (req, res) => {
    try {
        const result = markAllNotificationsRead.run(req.user.id);
        res.json({ success: true, marked: result.changes });
    } catch (err) {
        console.error('[Notif] 全部已读失败:', err);
        res.status(500).json({ error: 'update_failed' });
    }
});

// ============================================================
// 格式化输出
// ============================================================

function formatNotification(n) {
    return {
        uuid:      n.uuid,
        type:      n.type,
        title:     n.title,
        body:      n.body,
        isRead:    Boolean(n.is_read),
        createdAt: n.created_at,
        seedId:    n.seed_id,
        replyId:   n.reply_id,
    };
}

module.exports = router;
