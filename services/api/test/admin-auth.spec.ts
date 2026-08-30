import { HttpException, UnauthorizedException } from '@nestjs/common';
import { randomBytes, scryptSync } from 'node:crypto';
import { AdminAuthService } from '../src/auth/admin-auth.service';

function credential(email: string, password: string) {
  const salt = randomBytes(16);
  const digest = scryptSync(password, salt, 32);
  return `${email}=${salt.toString('hex')}:${digest.toString('hex')}`;
}

describe('AdminAuthService', () => {
  const secret = 'x'.repeat(48);
  const email = 'owner@example.com';
  const password = 'correct horse battery staple';

  let attempts: Record<string, { attempts: number; lockedUntil: Date | null }>;
  let jwt: { signAsync: jest.Mock; verifyAsync: jest.Mock };
  let service: AdminAuthService;

  beforeEach(() => {
    attempts = {};
    jwt = {
      signAsync: jest.fn().mockResolvedValue('token'),
      verifyAsync: jest.fn(),
    };
    const prisma = {
      pilotLoginAttempt: {
        findUnique: jest.fn(({ where }) => Promise.resolve(attempts[where.email] ?? null)),
        upsert: jest.fn(({ where, create, update }) => {
          attempts[where.email] = { ...(attempts[where.email] ?? {}), ...create, ...update } as never;
          return Promise.resolve(attempts[where.email]);
        }),
        deleteMany: jest.fn(({ where }) => {
          delete attempts[where.email];
          return Promise.resolve({ count: 1 });
        }),
      },
    } as never;
    service = new AdminAuthService(jwt as never, prisma);
    process.env.ADMIN_JWT_SECRET = secret;
    process.env.ADMIN_LOGIN_CREDENTIALS = credential(email, password);
  });

  it('signs a short-lived admin token on the right password', async () => {
    const result = await service.login({ email, password });
    expect(result.email).toBe(email);
    // 8 小时，不是内测那套的 7 天：后台权限更大，token 泄露的代价也更大。
    const ttl = result.expiresAt.getTime() - Date.now();
    expect(ttl).toBeLessThanOrEqual(8 * 60 * 60 * 1000);
    expect(ttl).toBeGreaterThan(7 * 60 * 60 * 1000);
    expect(jwt.signAsync).toHaveBeenCalledWith(
      expect.objectContaining({ kind: 'admin' }),
      expect.objectContaining({ secret, expiresIn: 8 * 60 * 60 }),
    );
  });

  it('rejects a wrong password', async () => {
    await expect(service.login({ email, password: 'wrong password!!' })).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('locks out after five failures', async () => {
    for (let i = 0; i < 5; i += 1) {
      await expect(service.login({ email, password: 'wrong password!!' })).rejects.toBeDefined();
    }
    // 第六次连密码都不该再校验——这是暴力破解的唯一有效防线。
    await expect(service.login({ email, password })).rejects.toBeInstanceOf(HttpException);
  });

  it('keeps its lockout counter separate from the pilot one', async () => {
    await expect(service.login({ email, password: 'wrong password!!' })).rejects.toBeDefined();
    // 同一个邮箱在 App 上输错密码，不能把后台一起锁死。
    expect(Object.keys(attempts)).toEqual([`admin:${email}`]);
  });

  it('refuses a token that is validly signed but not an admin token', async () => {
    // 内测 token 与后台 token 结构相同。只验签名就等于把 App 用户放进后台。
    jwt.verifyAsync.mockResolvedValue({ email, kind: 'pilot' });
    expect(await service.verify('any')).toBeNull();
  });

  it('accepts a genuine admin token', async () => {
    jwt.verifyAsync.mockResolvedValue({ email, kind: 'admin' });
    expect(await service.verify('any')).toEqual({ email });
  });

  it('refuses to run without a long enough signing secret', async () => {
    process.env.ADMIN_JWT_SECRET = 'short';
    await expect(service.login({ email, password })).rejects.toBeDefined();
  });
});
