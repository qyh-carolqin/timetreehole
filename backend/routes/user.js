const express = require('express');
const router = express.Router();

const {
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
} = require('../db');

// ============================================================
// 用户系统路由 — 匿名账号 + 设备标识 + 恢复码
// ============================================================

// ---- 辅助函数 ----

/// 格式化用户资料返回体（隐藏敏感字段）
function formatProfile(user) {
    return {
        id: user.id,
        nickname: user.nickname || generateNickname(),
        avatarColor: user.avatar_color ?? 0,
        bio: user.bio || '',
        recoveryCode: user.recovery_code || '',
        credits: user.credits ?? 0,
        createdAt: user.created_at,
        deviceId: user.device_id?.slice(0, 8) + '****',
    };
}

/// 更新设备活跃时间
function touchDevice(userId, deviceId, platform, model) {
    try {
        upsertDevice.run(userId, deviceId, platform || 'ios', model || null);
    } catch (_) { /* 静默 */ }
}

// ============================================================
// POST /api/user/register — 注册匿名账号（首次启动）
// ============================================================

router.post('/register', (req, res) => {
    const user = req.user; // auth 中间件已 findOrCreateUser
    const platform = req.headers['x-platform'] || 'ios';
    const model = req.headers['x-model'] || null;

    // 如果用户还没有 nickname / recovery_code，自动生成
    const nickname = req.body?.nickname || user.nickname || generateNickname();
    const avatarColor = req.body?.avatarColor ?? user.avatar_color ?? Math.floor(Math.random() * 8);
    const recoveryCode = user.recovery_code || generateRecoveryCode();

    const updated = registerUser.get(user.device_id, nickname, avatarColor, recoveryCode);

    // 记录设备
    touchDevice(updated.id, user.device_id, platform, model);

    res.json({
        success: true,
        user: formatProfile(updated),
    });
});

// ============================================================
// GET /api/user/profile — 获取当前用户资料
// ============================================================

router.get('/profile', (req, res) => {
    const user = req.user;
    touchDevice(user.id, user.device_id, req.headers['x-platform'], req.headers['x-model']);
    res.json({ user: formatProfile(user) });
});

// ============================================================
// PUT /api/user/profile — 更新用户资料
// ============================================================

router.put('/profile', (req, res) => {
    const { nickname, avatarColor, bio } = req.body || {};

    // 昵称校验
    if (nickname !== undefined) {
        if (typeof nickname !== 'string' || nickname.trim().length === 0) {
            return res.status(400).json({ error: 'invalid_nickname', message: '昵称不能为空' });
        }
        if (nickname.trim().length > 20) {
            return res.status(400).json({ error: 'invalid_nickname', message: '昵称最多 20 个字符' });
        }
    }

    // 头像色校验
    if (avatarColor !== undefined && (typeof avatarColor !== 'number' || avatarColor < 0 || avatarColor > 7)) {
        return res.status(400).json({ error: 'invalid_avatar_color', message: '头像色编号 0-7' });
    }

    const updated = updateUserProfile.get(
        nickname?.trim() || null,
        avatarColor ?? null,
        bio?.trim() || null,
        req.user.id
    );

    res.json({ success: true, user: formatProfile(updated) });
});

// ============================================================
// POST /api/user/recover — 通过恢复码恢复账号（设备迁移）
// ============================================================

router.post('/recover', (req, res) => {
    const { recoveryCode } = req.body || {};
    const currentDeviceId = req.deviceId; // auth 中间件已注入

    if (!recoveryCode || typeof recoveryCode !== 'string') {
        return res.status(400).json({ error: 'missing_recovery_code', message: '请输入恢复码' });
    }

    const normalizedCode = recoveryCode.trim().toUpperCase();

    // 按恢复码查找原始账号
    const originalUser = getUserByRecoveryCode.get(normalizedCode);
    if (!originalUser) {
        return res.status(404).json({ error: 'recovery_code_not_found', message: '恢复码无效或不存在' });
    }

    // 如果当前设备已经绑定了这个账号，无需操作
    if (originalUser.device_id === currentDeviceId) {
        return res.json({ success: true, user: formatProfile(originalUser), message: '当前设备已绑定该账号' });
    }

    // 如果当前设备已经绑定了另一个账号（auto-created），需要清理
    const currentUser = req.user;
    if (currentUser.id !== originalUser.id) {
        // 当前设备已有一个匿名账号，检查是否有数据
        const hasData = currentUser.credits > 0;
        if (hasData && !req.body?.confirm) {
            return res.status(409).json({
                error: 'device_has_data',
                message: '当前设备已有灵叶余额，恢复将覆盖现有数据。确定继续？',
                needConfirm: true,
            });
        }
        // 删除自动创建的空用户（释放 device_id 唯一约束）
        deleteEmptyUser.run(currentUser.id);
    }

    // 将原始账号的 device_id 更新为当前设备
    const updated = bindDeviceToUser.get(currentDeviceId, originalUser.id);

    // 记录设备绑定
    touchDevice(originalUser.id, currentDeviceId, req.headers['x-platform'], req.headers['x-model']);

    res.json({
        success: true,
        user: formatProfile(updated),
        message: '账号恢复成功！已绑定到当前设备',
    });
});

// ============================================================
// POST /api/user/recover/confirm — 确认覆盖现有设备数据
// ============================================================

router.post('/recover/confirm', (req, res) => {
    const { recoveryCode } = req.body || {};
    const currentDeviceId = req.deviceId;

    if (!recoveryCode) {
        return res.status(400).json({ error: 'missing_recovery_code' });
    }

    const normalizedCode = recoveryCode.trim().toUpperCase();
    const originalUser = getUserByRecoveryCode.get(normalizedCode);

    if (!originalUser) {
        return res.status(404).json({ error: 'recovery_code_not_found' });
    }

    // 强制绑定：先删除当前设备的空用户，再绑定
    const currentUser = req.user;
    if (currentUser.id !== originalUser.id) {
        deleteEmptyUser.run(currentUser.id);
    }
    const updated = bindDeviceToUser.get(currentDeviceId, originalUser.id);
    touchDevice(originalUser.id, currentDeviceId, req.headers['x-platform'], req.headers['x-model']);

    res.json({
        success: true,
        user: formatProfile(updated),
        message: '账号恢复成功',
    });
});

// ============================================================
// GET /api/user/devices — 获取绑定的设备列表
// ============================================================

router.get('/devices', (req, res) => {
    const devices = getDevicesByUserId.all(req.user.id);
    res.json({
        devices: devices.map(d => ({
            id: d.id,
            platform: d.platform,
            model: d.model,
            isCurrent: d.device_id === req.deviceId,
            lastActiveAt: d.last_active_at,
            createdAt: d.created_at,
        })),
    });
});

// ============================================================
// DELETE /api/user/devices/:id — 解绑设备
// ============================================================

router.delete('/devices/:id', (req, res) => {
    const deviceId = parseInt(req.params.id, 10);
    if (isNaN(deviceId)) {
        return res.status(400).json({ error: 'invalid_device_id' });
    }

    // 不能解绑当前设备
    const devices = getDevicesByUserId.all(req.user.id);
    const target = devices.find(d => d.id === deviceId);
    if (!target) {
        return res.status(404).json({ error: 'device_not_found', message: '设备不存在或不属于当前账号' });
    }
    if (target.device_id === req.deviceId) {
        return res.status(400).json({ error: 'cannot_unbind_current', message: '不能解绑当前正在使用的设备' });
    }

    deleteDevice.run(deviceId, req.user.id);
    res.json({ success: true, message: '设备已解绑' });
});

module.exports = router;
