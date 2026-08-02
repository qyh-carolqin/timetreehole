/**
 * 种子数据脚本 — 初始化演示数据
 *
 * 用法: node scripts/seed-demo.js
 *
 * 创建 3 个虚拟用户 + 5 颗语音种子（含私密和公开）+ 2 条回复
 */

const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');

const {
    db,
    findOrCreateUser,
    insertSeed,
    insertReply,
    insertNotification,
    incrementReplyCount,
} = require('../db');

console.log('🌱 开始生成演示数据...\n');

// 清空旧数据
db.exec('DELETE FROM notifications');
db.exec('DELETE FROM replies');
db.exec('DELETE FROM seeds');
db.exec('DELETE FROM users');

// ============================================================
// 创建用户
// ============================================================

const users = [
    { deviceId: 'device-demo-user-001', name: 'Alice' },
    { deviceId: 'device-demo-user-002', name: 'Bob'   },
    { deviceId: 'device-demo-user-003', name: 'Carol' },
].map(u => findOrCreateUser.get(u.deviceId));

console.log(`👤 创建了 ${users.length} 个用户:`);
users.forEach(u => console.log(`   ID=${u.id}  device=${u.device_id}`));

// ============================================================
// 创建空的 m4a 占位文件（真实场景用上传的音频）
// ============================================================

const uploadDir = path.join(__dirname, '..', 'uploads', 'demo');
fs.mkdirSync(uploadDir, { recursive: true });

function createDummyAudio(name) {
    const filePath = path.join(uploadDir, `${name}.m4a`);
    // 写入最小的有效 m4a 文件头（ftyp box），使文件可被识别
    const ftyp = Buffer.from([
        0x00, 0x00, 0x00, 0x1C, // box size
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x4D, 0x34, 0x41, 0x20, // 'M4A '
        0x00, 0x00, 0x00, 0x00, // minor version
        0x4D, 0x34, 0x41, 0x20, // 'M4A '
        0x6D, 0x70, 0x34, 0x32, // 'mp42'
        0x69, 0x73, 0x6F, 0x6D  // 'isom'
    ]);
    fs.writeFileSync(filePath, ftyp);
    return filePath;
}

const audio1 = createDummyAudio('seed_001');
const audio2 = createDummyAudio('seed_002');
const audio3 = createDummyAudio('seed_003');
const audio4 = createDummyAudio('seed_004');
const audio5 = createDummyAudio('seed_005');
const replyAudio1 = createDummyAudio('reply_001');
const replyAudio2 = createDummyAudio('reply_002');

// ============================================================
// 创建种子
// ============================================================

const seeds = [
    { userId: users[0].id, title: '心事片段',   duration: 24,  privacy: 'private', replyCount: 0, file: audio1 },
    { userId: users[0].id, title: '深夜的感慨',   duration: 65,  privacy: 'public',  replyCount: 0, file: audio2 },
    { userId: users[1].id, title: '雨天的回忆',   duration: 42,  privacy: 'public',  replyCount: 0, file: audio3 },
    { userId: users[2].id, title: '一个人的旅行',   duration: 78,  privacy: 'public',  replyCount: 0, file: audio4 },
    { userId: users[0].id, title: '今天的小确幸',   duration: 33,  privacy: 'private', replyCount: 0, file: audio5 },
].map(s => {
    const seed = insertSeed.get(
        uuidv4(),
        s.userId,
        s.title,
        s.duration,
        s.privacy,
        s.file,
        fs.statSync(s.file).size
    );
    return seed;
});

console.log(`\n🌰 创建了 ${seeds.length} 颗种子:`);
seeds.forEach(s => console.log(`   "${s.title}"  [${s.privacy}]  ${s.duration}s  by user#${s.user_id}`));

// ============================================================
// 创建回复（匿名）
// ============================================================

const replies = [
    {
        seed: seeds[1],  // 「深夜的感慨」by Alice → Bob 回复
        replierId: users[1].id,
        duration: 12,
        file: replyAudio1,
    },
    {
        seed: seeds[1],  // 「深夜的感慨」by Alice → Carol 回复
        replierId: users[2].id,
        duration: 18,
        file: replyAudio2,
    },
].map(r => {
    const reply = insertReply.get(
        uuidv4(),
        r.seed.id,
        r.replierId,
        r.duration,
        r.file
    );

    // 增加回复计数
    incrementReplyCount.run(r.seed.uuid);

    return reply;
});

console.log(`\n💬 创建了 ${replies.length} 条回复:`);
replies.forEach(r => console.log(`   reply#${r.id}  → seed#${r.seed_id}  by user#${r.replier_id}`));

// ============================================================
// 创建通知
// ============================================================

const notifications = [
    {
        userId:  users[0].id,
        type:    'new_reply',
        seedId:  seeds[1].id,
        replyId: replies[0].id,
        title:   '你的种子收到了新回复',
        body:    `「${seeds[1].title}」收到了一条匿名语音回复`,
    },
    {
        userId:  users[0].id,
        type:    'growth_sprout',
        seedId:  seeds[1].id,
        replyId: null,
        title:   '你的种子发芽了！',
        body:    `「${seeds[1].title}」收到了第1条回复，开始发芽`,
    },
    {
        userId:  users[0].id,
        type:    'new_reply',
        seedId:  seeds[1].id,
        replyId: replies[1].id,
        title:   '你的种子收到了新回复',
        body:    `「${seeds[1].title}」收到了第2条匿名语音回复`,
    },
].map(n => {
    return insertNotification.get(
        uuidv4(),
        n.userId,
        n.type,
        n.seedId,
        n.replyId,
        n.title,
        n.body
    );
});

console.log(`\n🔔 创建了 ${notifications.length} 条通知:`);
notifications.forEach(n => console.log(`   "${n.title}" → user#${n.user_id}`));

// ============================================================
// 统计
// ============================================================

const { countPublicSeeds, countUnreadNotifications } = require('../db');

console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log('📊 数据统计:');
console.log(`   用户:     ${users.length}`);
console.log(`   种子:     ${seeds.length} (公开: ${countPublicSeeds.get().total})`);
console.log(`   回复:     ${replies.length}`);
console.log(`   通知:     ${notifications.length} (未读: ${countUnreadNotifications.get(users[0].id)?.count})`);
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log('\n✅ 演示数据生成完毕！运行 node server.js 启动服务。\n');
