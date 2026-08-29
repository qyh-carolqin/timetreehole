const express = require('express');
const {
    db,
    QUOTA,
    RECHARGE_PACKAGES,
    getTodayUsage,
    addCredits,
    insertCreditTransaction,
} = require('../db');

const router = express.Router();

// ============================================================
// GET /api/user/quota — 用户配额 + 灵叶余额
// ============================================================

router.get('/quota', (req, res) => {
    try {
        const user = db.prepare('SELECT id, credits FROM users WHERE id = ?').get(req.user.id);
        const today = getTodayUsage.get(req.user.id);

        res.json({
            credits: user?.credits || 0,

            dailyUploads:    today?.public_uploads    || 0,
            dailyRetrievals: today?.public_retrievals || 0,

            maxDailyUploads:    QUOTA.FREE_DAILY_UPLOADS,
            maxDailyRetrievals: QUOTA.FREE_DAILY_RETRIEVALS,

            costExtraUpload:    QUOTA.COST_EXTRA_UPLOAD,
            costExtraRetrieval: QUOTA.COST_EXTRA_RETRIEVAL,
        });
    } catch (err) {
        console.error('[Quota] 查询失败:', err);
        res.status(500).json({ error: 'query_failed' });
    }
});

// ============================================================
// GET /api/user/credits — 仅灵叶余额（轻量）
// ============================================================

router.get('/credits', (req, res) => {
    try {
        const user = db.prepare('SELECT credits FROM users WHERE id = ?').get(req.user.id);
        res.json({ credits: user?.credits || 0 });
    } catch (err) {
        res.status(500).json({ error: 'query_failed' });
    }
});

// ============================================================
// GET /api/user/packages — 充值套餐列表
// ============================================================

router.get('/packages', (req, res) => {
    res.json({ packages: RECHARGE_PACKAGES });
});

// ============================================================
// POST /api/user/recharge — 充值灵叶（模拟 IAP 回调）
// ============================================================

router.post('/recharge', (req, res) => {
    try {
        const { packageId } = req.body;

        if (!packageId) {
            return res.status(400).json({ error: 'missing_package', message: '请选择充值套餐' });
        }

        const pkg = RECHARGE_PACKAGES.find(p => p.id === packageId);
        if (!pkg) {
            return res.status(400).json({ error: 'invalid_package', message: '无效的充值套餐' });
        }

        // 发放灵叶
        const result = addCredits.run(pkg.credits, req.user.id);

        // 记录交易
        insertCreditTransaction.run(req.user.id, pkg.credits, `recharge_${packageId}`);

        // 获取最新余额
        const updated = db.prepare('SELECT credits FROM users WHERE id = ?').get(req.user.id);

        console.log(`💰 [充值] user_id=${req.user.id} 套餐=${packageId} +${pkg.credits}灵叶 → 余额=${updated.credits}`);

        res.json({
            success: true,
            addedCredits: pkg.credits,
            totalCredits: updated.credits,
            package: pkg.name,
        });
    } catch (err) {
        console.error('[Quota] 充值失败:', err);
        res.status(500).json({ error: 'recharge_failed', message: '充值失败，请稍后再试' });
    }
});

// ============================================================
// GET /api/user/transactions — 消费/充值记录
// ============================================================

router.get('/transactions', (req, res) => {
    try {
        const txs = db.prepare(`
            SELECT *, strftime('%Y-%m-%dT%H:%M:%fZ', created_at) AS created_at
            FROM credit_transactions
            WHERE user_id = ?
            ORDER BY created_at DESC
            LIMIT 50
        `).all(req.user.id);

        res.json({
            transactions: txs.map(tx => ({
                amount:    tx.amount,
                reason:    tx.reason,
                createdAt: tx.created_at,
            })),
        });
    } catch (err) {
        res.status(500).json({ error: 'query_failed' });
    }
});

module.exports = router;
