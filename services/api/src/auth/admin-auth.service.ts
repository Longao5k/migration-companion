import {
  HttpException,
  HttpStatus,
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { AdminLoginDto } from './admin-auth.dto';

const issuer = 'migration-companion-admin';
const audience = 'migration-companion-console';

/**
 * 后台登录。
 *
 * 目前后台只监听回环，靠 SSH 隧道加一个共享密钥进入。要把它放到公网子域名上，
 * 共享密钥就不够了：**后台能发布政策内容**，密钥泄露等于别人可以向所有用户推送假政策。
 * 一个填在输入框里、会被复制粘贴、没有有效期、泄露了也无从察觉的字符串，不适合挂在公网上。
 *
 * 账号存在**数据库**里，不是环境变量。内测访问码用 env 是合理的——那是一次性、按人发的；
 * 管理员账号不是。env 那条路要求「本机生成哈希 → 粘进服务器 .env → 重启 API」：密码要跨机器，
 * 哈希要经过命令行，改一次密码重启一次服务，而且逗号分隔的配置里一个格式错误会让
 * **所有管理员一起登不进去**。
 *
 * 这里沿用内测登录那套已经验证过的做法（逐账号 scrypt、失败锁定、诱饵哈希防时序侧信道），
 * 只改三处：
 *
 * 1. **会话短得多**（8 小时 vs 7 天）。后台的权限比用户账号大，token 泄露的代价也大。
 * 2. **失败计数与内测账号隔离**，用 `admin:` 前缀。否则同一个邮箱既是内测用户又是管理员时，
 *    在 App 上输错几次密码会把后台一起锁死。
 * 3. **签名密钥独立**（`ADMIN_JWT_SECRET`）。内测密钥泄露不应该顺带交出后台。
 *
 * 仍然没做、上线前要补的：TOTP 二次验证。单管理员 + 强随机密码 + 锁定，在封闭测试期间
 * 是可接受的起点，但不是终点。
 */
const tokenLifetimeSeconds = 8 * 60 * 60;
const maxAttempts = 5;
const lockoutMs = 15 * 60_000;
// 邮箱不存在时也走一次等价的 scrypt，让「邮箱不对」和「密码不对」在耗时上无法区分。
const decoySalt = randomBytes(16);

@Injectable()
export class AdminAuthService {
  constructor(
    private readonly jwt: JwtService,
    private readonly prisma: PrismaService,
  ) {}

  async login(dto: AdminLoginDto) {
    const secret = this.requireSecret();
    const email = dto.email.trim().toLowerCase();

    await this.assertNotLocked(email);
    const account = await this.prisma.adminUser.findUnique({ where: { email } });
    // 停用的账号也走完整的校验流程再拒绝，否则响应快慢会暴露哪些邮箱存在。
    const accepted =
      this.verifyPassword(dto.password, account?.passwordHash) && !account?.disabled;
    if (!accepted) {
      await this.registerFailure(email);
      throw new UnauthorizedException('邮箱或密码无效');
    }
    await this.clearFailures(email);
    await this.prisma.adminUser.update({
      where: { email },
      data: { lastLoginAt: new Date() },
    });

    const accessToken = await this.jwt.signAsync(
      { email, kind: 'admin' },
      {
        secret,
        subject: `admin:${email}`,
        issuer,
        audience,
        expiresIn: tokenLifetimeSeconds,
      },
    );
    return {
      accessToken,
      email,
      expiresAt: new Date(Date.now() + tokenLifetimeSeconds * 1000),
    };
  }

  /** 校验后台会话 token；无效返回 null，由调用方决定报什么错。 */
  async verify(token: string): Promise<{ email: string } | null> {
    try {
      const payload = await this.jwt.verifyAsync<{ email?: string; kind?: string }>(
        token,
        { secret: this.requireSecret(), issuer, audience },
      );
      // kind 必须显式检查：内测 token 与后台 token 结构相同，
      // 只靠签名有效不足以区分二者。
      if (payload.kind !== 'admin' || !payload.email) return null;
      return { email: payload.email };
    } catch {
      return null;
    }
  }

  private requireSecret() {
    const secret = process.env.ADMIN_JWT_SECRET;
    if (!secret || secret.length < 32) {
      throw new ServiceUnavailableException('后台身份服务配置不完整');
    }
    return secret;
  }

  private verifyPassword(password: string, encoded: string | undefined | null) {
    if (!encoded || !/^[a-f0-9]{32}:[a-f0-9]{64}$/i.test(encoded)) {
      // 账号不存在、被停用、或哈希格式损坏时，同样跑一次等价的 scrypt，
      // 让「邮箱不对」和「密码不对」在耗时上无法区分。
      scryptSync(password, decoySalt, 32);
      return false;
    }
    const [saltHex, digestHex] = encoded.split(':');
    const expected = Buffer.from(digestHex, 'hex');
    const actual = scryptSync(password, Buffer.from(saltHex, 'hex'), expected.length);
    return timingSafeEqual(actual, expected);
  }

  /** 后台的失败计数与内测账号分开，避免 App 端输错密码把后台锁死。 */
  private attemptKey(email: string) {
    return `admin:${email}`;
  }

  private async assertNotLocked(email: string) {
    const record = await this.prisma.pilotLoginAttempt.findUnique({
      where: { email: this.attemptKey(email) },
    });
    if (record?.lockedUntil && record.lockedUntil > new Date()) {
      throw new HttpException('登录尝试过多，请稍后再试', HttpStatus.TOO_MANY_REQUESTS);
    }
  }

  private async registerFailure(email: string) {
    const key = this.attemptKey(email);
    const record = await this.prisma.pilotLoginAttempt.findUnique({ where: { email: key } });
    const attempts = (record?.attempts ?? 0) + 1;
    const locked = attempts >= maxAttempts;
    const data = {
      attempts: locked ? 0 : attempts,
      lockedUntil: locked ? new Date(Date.now() + lockoutMs) : null,
      lastAttempt: new Date(),
    };
    await this.prisma.pilotLoginAttempt.upsert({
      where: { email: key },
      create: { email: key, ...data },
      update: data,
    });
  }

  private async clearFailures(email: string) {
    await this.prisma.pilotLoginAttempt.deleteMany({
      where: { email: this.attemptKey(email) },
    });
  }
}
