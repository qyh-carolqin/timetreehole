// 本地集成验证：演示数据清理 + random 免配额逻辑
// 用临时 DB，不触碰真实数据
import fs from 'fs';
import os from 'os';
import path from 'path';

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tth-test-'));
process.env.DB_DIR = tmpDir;
process.env.NODE_ENV = 'production';

const { db } = await import('../backend/db.js');

function assert(cond, msg) {
  if (!cond) { console.error('❌ FAIL:', msg); process.exitCode = 1; }
  else console.log('✅', msg);
}

// 插入演示用户 + 演示种子(file_size=28) + 0字节真实种子 + 正常真实种子
const u1 = db.prepare('INSERT INTO users (device_id, credits) VALUES (?,0)').run('device-demo-user-001');
const u2 = db.prepare('INSERT INTO users (device_id, credits) VALUES (?,0)').run('device-demo-user-002');
const u3 = db.prepare('INSERT INTO users (device_id, credits) VALUES (?,5)').run('real-user-1'); // 有灵叶的真实用户

const demoSeed = db.prepare("INSERT INTO seeds (uuid,user_id,title,privacy,file_path,file_size) VALUES (?,?,?,?,?,?)").run('demo-seed-1', u1.lastInsertRowid, '深夜的感慨', 'public', '/tmp/demo.m4a', 28);
const brokenSeed = db.prepare("INSERT INTO seeds (uuid,user_id,title,privacy,file_path,file_size) VALUES (?,?,?,?,?,?)").run('broken-seed-1', u3.lastInsertRowid, '坏种子', 'public', '/tmp/broken.m4a', 0);
const goodSeed = db.prepare("INSERT INTO seeds (uuid,user_id,title,privacy,file_path,file_size) VALUES (?,?,?,?,?,?)").run('good-seed-1', u3.lastInsertRowid, '好种子', 'public', '/tmp/good.m4a', 1234);

console.log('\n--- 清理前 ---');
console.log('users:', db.prepare('SELECT COUNT(*) c FROM users').get().c, 'seeds:', db.prepare('SELECT COUNT(*) c FROM seeds').get().c);

// === 复制 server.js 的清理逻辑 ===
const DEMO_DEVICES = ['device-demo-user-001', 'device-demo-user-002', 'device-demo-user-003'];
const demoIds = DEMO_DEVICES
  .map(d => db.prepare('SELECT id FROM users WHERE device_id = ?').get(d))
  .filter(Boolean)
  .map(r => r.id);
if (demoIds.length) {
  const ph = demoIds.map(() => '?').join(',');
  db.prepare(`DELETE FROM users WHERE id IN (${ph})`).run(...demoIds);
}
const broken = db.prepare("DELETE FROM seeds WHERE file_size = 0 OR file_size IS NULL").run();

console.log('\n--- 清理后 ---');
console.log('删除演示用户数:', demoIds.length, ' 删除损坏种子数:', broken.changes);
assert(db.prepare("SELECT COUNT(*) c FROM users WHERE device_id='device-demo-user-001'").get().c === 0, '演示用户已删除');
assert(db.prepare("SELECT COUNT(*) c FROM seeds WHERE uuid='demo-seed-1'").get().c === 0, '演示种子已删除(级联)');
assert(db.prepare("SELECT COUNT(*) c FROM seeds WHERE uuid='broken-seed-1'").get().c === 0, '0字节种子已删除');
assert(db.prepare("SELECT COUNT(*) c FROM seeds WHERE uuid='good-seed-1'").get().c === 1, '正常种子保留');
assert(db.prepare("SELECT COUNT(*) c FROM users WHERE device_id='real-user-1'").get().c === 1, '真实用户保留');

// 验证 randomPublicSeed 能命中正常种子(模拟免配额后)
const seed = db.prepare("SELECT * FROM seeds WHERE privacy='public' AND user_id != ? ORDER BY RANDOM() LIMIT 1").get(0);
assert(seed && seed.uuid === 'good-seed-1', 'random 查询能返回正常公共种子');

console.log('\n测试完成。临时DB:', tmpDir);
