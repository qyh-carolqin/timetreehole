const { findOrCreateUser } = require('../db');

/**
 * 匿名认证中间件
 *
 * 每个请求必须携带 X-Device-Id 头。
 * 首次请求自动创建匿名用户记录，后续请求从数据库匹配。
 * 将 user 对象挂载到 req.user。
 */
function authMiddleware(req, res, next) {
    const deviceId = req.headers['x-device-id'];

    if (!deviceId || typeof deviceId !== 'string' || deviceId.trim().length === 0) {
        return res.status(401).json({
            error: 'unauthorized',
            message: '缺少 X-Device-Id 请求头，请先注册设备'
        });
    }

    try {
        const user = findOrCreateUser.get(deviceId.trim());
        req.user = user;
        req.deviceId = deviceId.trim();
        next();
    } catch (err) {
        console.error('[Auth] 数据库错误:', err.message);
        return res.status(500).json({ error: 'internal_error', message: '认证服务异常' });
    }
}

module.exports = authMiddleware;
