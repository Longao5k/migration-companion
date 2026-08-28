import {
  HttpException,
  HttpStatus,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { createHash, randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { PilotLoginDto } from './pilot-auth.dto';

const issuer = 'migration-companion-pilot';
const audience = 'migration-companion-app';

/**
 * 内测身份是过渡方案，最终形态是冻结决策里的邮箱一次性验证码/登录链接（需要邮件服务商与正式域名）。
 * 在那之前，访问码必须**逐邮箱绑定**：共享同一个码会让任何持码人登录成其他内测用户的邮箱，
 * 读取对方的护照、银行和健康材料。绑定之后，暴力猜测只能针对单个邮箱，再配合失败锁定即可阻断。
 */
const tokenLifetimeSeconds = 7 * 24 * 60 * 60;
const maxAttempts = 5;
const lockoutMs = 15 * 60_000;
// 未配置邮箱时也执行一次等价的 scrypt，避免用响应时间区分“邮箱不在内测名单”和“访问码错误”。
const decoySalt = randomBytes(16);

@Injectable()
export class PilotAuthService {
  constructor(
    private readonly jwt: JwtService,
    private readonly prisma: PrismaService,
  ) {}

  async login(dto: PilotLoginDto) {
    if (process.env.PILOT_AUTH_ENABLED !== 'true') {
      throw new NotFoundException('内测登录未启用');
    }
    const jwtSecret = process.env.PILOT_JWT_SECRET;
    if (!jwtSecret || jwtSecret.length < 32) {
      throw new ServiceUnavailableException('内测身份服务配置不完整');
    }
    const codes = this.configuredCodes();
    const email = dto.email.trim().toLowerCase();

    await this.assertNotLocked(email);
    const storedHash = codes.get(email);
    // 无论邮箱是否在名单内都做一次等长校验，响应与耗时保持一致。
    const accepted = this.verifyCode(dto.accessCode, storedHash);
    if (!accepted) {
      await this.registerFailure(email);
      throw new UnauthorizedException('邮箱或内测访问码无效');
    }
    await this.clearFailures(email);

    const accountId = `pilot-${createHash('sha256').update(email).digest('hex').slice(0, 24)}`;
    const accessToken = await this.jwt.signAsync(
      { email, kind: 'pilot' },
      {
        secret: jwtSecret,
        subject: accountId,
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

  /**
   * `PILOT_ACCESS_CODES` 形如 `alice@example.com=<salt>:<hash>,bob@example.com=<salt>:<hash>`，
   * 也接受换行分隔。用 `pnpm --filter @migration-companion/api pilot:hash-code -- <邮箱> <访问码>` 生成。
   */
  private configuredCodes() {
    const raw = process.env.PILOT_ACCESS_CODES;
    if (!raw?.trim()) {
      if (process.env.PILOT_ACCESS_CODE_SCRYPT) {
        // 旧的单一共享码允许任何人登录成任何邮箱，不接受静默沿用。
        throw new ServiceUnavailableException(
          '内测访问码配置已失效：PILOT_ACCESS_CODE_SCRYPT 是所有人共用的单一访问码，' +
            '会让持码人登录成其他人的邮箱。请改用逐邮箱绑定的 PILOT_ACCESS_CODES。',
        );
      }
      throw new ServiceUnavailableException('内测身份服务配置不完整');
    }
    const codes = new Map<string, string>();
    for (const entry of raw.split(/[\n,]/)) {
      const trimmed = entry.trim();
      if (!trimmed) continue;
      const separator = trimmed.indexOf('=');
      if (separator <= 0) {
        throw new ServiceUnavailableException('内测访问码配置格式无效');
      }
      const email = trimmed.slice(0, separator).trim().toLowerCase();
      const hash = trimmed.slice(separator + 1).trim();
      if (!email.includes('@') || !/^[a-f0-9]{32}:[a-f0-9]{64}$/i.test(hash)) {
        throw new ServiceUnavailableException('内测访问码配置格式无效');
      }
      codes.set(email, hash);
    }
    if (codes.size === 0) {
      throw new ServiceUnavailableException('内测身份服务配置不完整');
    }
    return codes;
  }

  private verifyCode(code: string, encoded: string | undefined) {
    if (!encoded) {
      scryptSync(code, decoySalt, 32);
      return false;
    }
    const [saltHex, digestHex] = encoded.split(':');
    const expected = Buffer.from(digestHex, 'hex');
    const actual = scryptSync(code, Buffer.from(saltHex, 'hex'), expected.length);
    return timingSafeEqual(actual, expected);
  }

  private async assertNotLocked(email: string) {
    const record = await this.prisma.pilotLoginAttempt.findUnique({ where: { email } });
    if (record?.lockedUntil && record.lockedUntil > new Date()) {
      throw new HttpException('登录尝试过多，请稍后再试', HttpStatus.TOO_MANY_REQUESTS);
    }
  }

  private async registerFailure(email: string) {
    const record = await this.prisma.pilotLoginAttempt.findUnique({ where: { email } });
    const attempts = (record?.attempts ?? 0) + 1;
    const locked = attempts >= maxAttempts;
    await this.prisma.pilotLoginAttempt.upsert({
      where: { email },
      create: {
        email,
        attempts: locked ? 0 : attempts,
        lockedUntil: locked ? new Date(Date.now() + lockoutMs) : null,
        lastAttempt: new Date(),
      },
      update: {
        attempts: locked ? 0 : attempts,
        lockedUntil: locked ? new Date(Date.now() + lockoutMs) : null,
        lastAttempt: new Date(),
      },
    });
  }

  private async clearFailures(email: string) {
    await this.prisma.pilotLoginAttempt.deleteMany({ where: { email } });
  }

  static verificationOptions(secret: string) {
    return { secret, issuer, audience };
  }
}
