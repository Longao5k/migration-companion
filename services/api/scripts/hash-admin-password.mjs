import { randomBytes, scryptSync } from 'node:crypto';

// 后台账号逐邮箱绑定，格式与内测访问码一致，但用的是独立的环境变量和签名密钥——
// 内测密钥泄露不应该顺带交出发布政策内容的权限。
//
// 用法：pnpm --filter @migration-companion/api admin:hash-password -- <邮箱> <密码>
// 输出追加到服务器 .env 的 ADMIN_LOGIN_CREDENTIALS（多个条目用逗号或换行分隔）。
const email = (process.argv[2] ?? '').trim().toLowerCase();
const password = process.argv[3] ?? process.env.ADMIN_PASSWORD_TO_HASH;

if (!email.includes('@')) {
  throw new Error('第一个参数必须是管理员邮箱。');
}
// 12 位下限和 DTO 一致。这个账号能向全部用户发布政策内容，不设下限就会出现 admin123。
if (!password || password.length < 12) {
  throw new Error('第二个参数必须是至少 12 位的密码，或设置 ADMIN_PASSWORD_TO_HASH。');
}

const salt = randomBytes(16);
const digest = scryptSync(password, salt, 32);
process.stdout.write(`${email}=${salt.toString('hex')}:${digest.toString('hex')}\n`);
