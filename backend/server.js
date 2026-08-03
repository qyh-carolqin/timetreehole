// 全局异常捕获 — 确保任何未捕获错误都能输出到 Railway 日志
process.on('uncaughtException', (err) => {
    console.error('[FATAL] 未捕获异常:', err.message);
    console.error(err.stack);
    process.exit(1);
});
process.on('unhandledRejection', (reason) => {
    console.error('[FATAL] 未处理的 Promise 拒绝:', reason);
    process.exit(1);
});

const express = require('express');
const cors    = require('cors');
const path    = require('path');

// 数据库加载（带错误捕获以便诊断）
let db, updateApnsToken;
try {
    const dbModule = require('./db');
    db = dbModule.db;
    updateApnsToken = dbModule.updateApnsToken;
    console.log('[启动] 数据库模块加载成功');
} catch (err) {
    console.error('[FATAL] 数据库模块加载失败:', err.message);
    console.error(err.stack);
    process.exit(1);
}

const authMiddleware = require('./middleware/auth');
const seedsRouter     = require('./routes/seeds');
const treeholeRouter  = require('./routes/treehole');
const notifRouter     = require('./routes/notifications');

const app = express();
const PORT = process.env.PORT || 3000;
const NODE_ENV = process.env.NODE_ENV || 'development';

// ============================================================
// 生产环境：信任反向代理（Nginx / Cloudflare）
// ============================================================
if (NODE_ENV === 'production') {
    app.set('trust proxy', 1); // 信任第一层代理
}

// ============================================================
// 全局中间件
// ============================================================

app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'X-Device-Id'],
}));

app.use(express.json({ limit: '5mb' }));

// 请求日志
app.use((req, res, next) => {
    const start = Date.now();
    res.on('finish', () => {
        const ms = Date.now() - start;
        const device = req.headers['x-device-id']?.slice(0, 8) || 'unknown';
        console.log(`${req.method} ${req.path} → ${res.statusCode} (${ms}ms) [${device}]`);
    });
    next();
});

// ============================================================
// 健康检查（无需认证）
// ============================================================

app.get('/api/health', (req, res) => {
    res.json({
        status: 'ok',
        service: '时间树洞 · API',
        version: '1.0.0',
        timestamp: new Date().toISOString(),
    });
});

// ============================================================
// 设备注册（无需认证中间件，但需要 deviceId）
// ============================================================

app.post('/api/device/register', express.json(), (req, res) => {
    try {
        const deviceId = req.headers['x-device-id'];
        const { token } = req.body;

        if (!deviceId) {
            return res.status(400).json({ error: 'missing_device_id' });
        }
        if (!token) {
            return res.status(400).json({ error: 'missing_token' });
        }

        const { findOrCreateUser, updateApnsToken } = require('./db');
        const user = findOrCreateUser.get(deviceId);
        updateApnsToken.run(token, deviceId);

        res.json({ success: true, message: '推送令牌已注册' });
    } catch (err) {
        res.status(500).json({ error: 'register_failed' });
    }
});

// ============================================================
// 全局认证 — 以下路由需要 X-Device-Id
// ============================================================

app.use('/api', authMiddleware);

// 挂载路由
app.use('/api/seeds',         seedsRouter);
app.use('/api/treehole',      treeholeRouter);
app.use('/api/notifications', notifRouter);
app.use('/api/user',          require('./routes/quota'));
app.use('/api/user',          require('./routes/user'));    // 用户系统：注册/资料/恢复/设备
app.use('/api/iap',           require('./routes/iap'));     // App Store IAP 收据验证

// 兼容别名
app.get('/api/my/seeds', (req, res) => {
    req.url = '/my';
    seedsRouter(req, res);
});

// ============================================================
// 静态文件 — 开发环境音频直接访问（生产用 CDN）
// ============================================================

app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// ============================================================
// 404 / 500 处理
// ============================================================

app.use((req, res) => {
    res.status(404).json({ error: 'not_found', path: req.path });
});

app.use((err, req, res, next) => {
    console.error('[Server] 未捕获错误:', err);
    if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(413).json({ error: 'file_too_large', message: '文件大小不能超过 20MB' });
    }
    res.status(500).json({ error: 'internal_error', message: '服务器内部错误' });
});

// ============================================================
// 启动
// ============================================================

const server = app.listen(PORT, '0.0.0.0', () => {
    console.log('');
    console.log('  🌳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━🌳');
    console.log('  │      时间树洞 · 后端服务 v1.0.0         │');
    console.log('  │      TimeTreehole API Server            │');
    console.log('  ├──────────────────────────────────────────┤');
    console.log(`  │  地址: http://0.0.0.0:${PORT}                │`);
    console.log(`  │  健康: http://0.0.0.0:${PORT}/api/health     │`);
    console.log('  │  认证: X-Device-Id (请求头)              │');
    console.log('  └──────────────────────────────────────────┘');
    console.log('');
    console.log('  📡 API 端点:');
    console.log('     POST   /api/seeds                上传种子');
    console.log('     POST   /api/seeds/with-duration  上传种子(含时长)');
    console.log('     GET    /api/my/seeds             我的种子列表');
    console.log('     GET    /api/seeds/:uuid          种子详情');
    console.log('     GET    /api/seeds/:uuid/audio    播放音频');
    console.log('     DELETE /api/seeds/:uuid          删除种子');
    console.log('     GET    /api/treehole/random      随机公共种子');
    console.log('     GET    /api/treehole/stats       树洞统计');
    console.log('     POST   /api/treehole/:id/reply   匿名回复');
    console.log('     GET    /api/notifications        通知列表');
    console.log('     GET    /api/notifications/unread-count');
    console.log('     PUT    /api/notifications/:id/read');
    console.log('     PUT    /api/notifications/read-all');
    console.log('     POST   /api/device/register      注册推送');
    console.log('     GET    /api/user/quota           配额+灵叶余额');
    console.log('     GET    /api/user/credits         灵叶余额');
    console.log('     GET    /api/user/packages        充值套餐');
    console.log('     POST   /api/user/recharge        充值灵叶');
    console.log('     POST   /api/iap/verify           App Store IAP 收据验证');
    console.log('     GET    /api/user/transactions    消费记录');
    console.log('     POST   /api/user/register        注册匿名账号');
    console.log('     GET    /api/user/profile         用户资料');
    console.log('     PUT    /api/user/profile         更新资料');
    console.log('     POST   /api/user/recover         恢复码恢复账号');
    console.log('     POST   /api/user/recover/confirm 确认恢复(覆盖)');
    console.log('     GET    /api/user/devices         设备列表');
    console.log('     DELETE /api/user/devices/:id     解绑设备');
    console.log('');
});

server.on('error', (err) => {
    console.error('[Server] 启动失败:', err.message);
    process.exit(1);
});
