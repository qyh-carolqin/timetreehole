/**
 * APNs 推送服务（框架层）
 *
 * 生产环境需要：
 *   1. Apple Developer 账号 → Key ID + Team ID + .p8 密钥
 *   2. 替换 push() 中的实际推送逻辑
 *
 * 当前为桩实现，占位 ready for production integration。
 */

const { updateApnsToken, getUserByDeviceId, countUnreadNotifications } = require('../db');

class PushService {

    /**
     * 注册设备推送令牌
     * POST /api/device/register
     */
    registerToken(deviceId, token) {
        try {
            updateApnsToken.run(token, deviceId);
            console.log(`[Push] 设备注册成功: deviceId=${deviceId.slice(0,8)}...`);
            return { success: true };
        } catch (err) {
            console.error('[Push] 注册失败:', err.message);
            return { success: false, error: err.message };
        }
    }

    /**
     * 发送推送通知
     *
     * @param {number} userId - 接收方用户 ID
     * @param {object} payload - { title, body, type, seedId, replyId }
     */
    send(userId, payload) {
        try {
            const user = getUserByDeviceId.get(payload.deviceId);
            if (!user || !user.apns_token) {
                console.log(`[Push] 跳过: 用户 ${userId} 未注册推送令牌`);
                return;
            }

            // ============================================
            // TODO: 生产环境 — 接入 APNs
            // ============================================
            // 1. 安装 @parse/node-apn 或 node-apn
            // 2. 配置 apn.Provider({ token: { key, keyId, teamId } })
            // 3. 构造 apn.Notification({ alert: { title, body }, badge, sound, payload })
            // 4. provider.send(notification, user.apns_token)
            // ============================================

            const badge = countUnreadNotifications.get(user.id)?.count ?? 0;

            console.log(`[Push] 📬 发送通知 → user=${userId}`, {
                title: payload.title,
                body: payload.body,
                badge,
                type: payload.type,
            });

            // 桩：模拟推送发送
            console.log(`[Push] ⚠️  APNs 未接入，仅日志记录。令牌: ${user.apns_token.slice(0,8)}...`);

        } catch (err) {
            console.error('[Push] 发送失败:', err.message);
        }
    }
}

module.exports = new PushService();
