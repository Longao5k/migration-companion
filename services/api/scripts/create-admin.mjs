import { PrismaClient } from '@prisma/client';
import { randomBytes, scryptSync } from 'node:crypto';
import { createInterface } from 'node:readline';

// 建立或更新后台管理员账号。
//
// **在服务器上跑**，不在本机：
//
//   ssh tencent-light
//   cd ~/migration-companion/infra/server
//   docker compose exec api node scripts/create-admin.mjs
//
// 密码在服务器上敲一次，直接哈希写库。不跨机器、不进本机 shell 历史、
// 不用把哈希粘到命令行里，改密码也不用重启 API。
//
// 想改密码就再跑一次同一个邮箱，会覆盖。停用账号用 --disable。

const MIN_LENGTH = 12;

function ask(question, { hidden = false } = {}) {
  return new Promise((resolve) => {
    const rl = createInterface({
      input: process.stdin,
      output: process.stdout,
      terminal: true,
    });
    if (hidden) {
      // 输入时不回显。这是当着屏幕敲的密码。
      const write = rl._writeToOutput?.bind(rl);
      rl._writeToOutput = (chunk) => {
        if (chunk.includes(question)) write?.(chunk);
      };
    }
    rl.question(question, (answer) => {
      rl.close();
      if (hidden) process.stdout.write('\n');
      resolve(answer.trim());
    });
  });
}

const prisma = new PrismaClient();

try {
  const disable = process.argv.includes('--disable');
  let email = (process.argv[2] ?? '').trim().toLowerCase();
  while (!email.includes('@') || email.startsWith('--')) {
    if (email && !email.startsWith('--')) process.stdout.write('这不像一个邮箱地址。\n');
    email = (await ask('管理员邮箱：')).toLowerCase();
  }

  if (disable) {
    // 停用而不是删除：审计记录要能指回是谁做的操作。
    await prisma.adminUser.update({ where: { email }, data: { disabled: true } });
    process.stdout.write(`已停用 ${email}。审计记录保留。\n`);
    process.exit(0);
  }

  let password = '';
  while (password.length < MIN_LENGTH) {
    if (password) {
      process.stdout.write(`密码至少 ${MIN_LENGTH} 位，当前 ${password.length} 位。\n`);
    }
    // 这个账号能向所有用户发布政策内容，长度下限不是形式主义。
    password = await ask(`密码（至少 ${MIN_LENGTH} 位，不显示）：`, { hidden: true });
  }
  const confirm = await ask('再输一次：', { hidden: true });
  if (confirm !== password) {
    process.stderr.write('两次输入不一致，什么都没改。\n');
    process.exit(1);
  }

  const salt = randomBytes(16);
  const passwordHash = `${salt.toString('hex')}:${scryptSync(password, salt, 32).toString('hex')}`;
  const existing = await prisma.adminUser.findUnique({ where: { email } });
  await prisma.adminUser.upsert({
    where: { email },
    create: { email, passwordHash },
    update: { passwordHash, disabled: false },
  });

  process.stdout.write(
    existing
      ? `已更新 ${email} 的密码。旧会话仍然有效到过期（最长 8 小时）。\n`
      : `已创建管理员 ${email}。\n`,
  );
} finally {
  await prisma.$disconnect();
}
