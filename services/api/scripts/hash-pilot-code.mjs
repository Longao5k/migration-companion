import { randomBytes, scryptSync } from 'node:crypto';

// 内测访问码逐邮箱绑定：一个码只能登录它对应的那个邮箱。
// 用法：pnpm --filter @migration-companion/api pilot:hash-code -- <邮箱> <访问码>
// 输出可直接追加到服务器 .env 的 PILOT_ACCESS_CODES（多个条目用逗号或换行分隔）。
const email = (process.argv[2] ?? process.env.PILOT_EMAIL_TO_HASH ?? '').trim().toLowerCase();
const code = process.argv[3] ?? process.env.PILOT_CODE_TO_HASH;

if (!email.includes('@')) {
  throw new Error('第一个参数必须是内测用户的邮箱。');
}
if (!code || code.length < 8) {
  throw new Error('第二个参数必须是至少 8 位的访问码，或设置 PILOT_CODE_TO_HASH。');
}

const salt = randomBytes(16);
const digest = scryptSync(code, salt, 32);
process.stdout.write(`${email}=${salt.toString('hex')}:${digest.toString('hex')}\n`);
