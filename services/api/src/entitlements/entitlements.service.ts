import { BadRequestException, ConflictException, Injectable } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { SubmitPurchaseDto, VerifiedStoreEventDto } from './entitlements.dto';

const freeBytes = 1024 ** 3;
const premiumBytes = 10 * 1024 ** 3;

@Injectable()
export class EntitlementsService {
  constructor(private readonly prisma: PrismaService) {}

  async get(accountId: string, email: string) {
    const account = await this.ensureAccount(accountId, email);
    const ownedProjects = await this.prisma.project.findMany({
      where: { ownerId: accountId },
      select: { id: true },
    });
    const projectIds = ownedProjects.map((project) => project.id);
    const [storage, reserved] = await Promise.all([
      this.prisma.fileRecord.aggregate({
        where: { project: { ownerId: accountId } },
        _sum: { byteSize: true },
      }),
      this.prisma.uploadSession.aggregate({
        where: {
          projectId: { in: projectIds },
          completedAt: null,
          expiresAt: { gt: new Date() },
        },
        _sum: { byteSize: true },
      }),
    ]);
    const now = new Date();
    const subscriptionActive =
      account.subscription !== null &&
      ['ACTIVE', 'GRACE'].includes(account.subscription.status) &&
      (!account.subscription.currentPeriodEndsAt || account.subscription.currentPeriodEndsAt > now);
    const trialActive = Boolean(account.trialEndsAt && account.trialEndsAt > now);
    const tier = subscriptionActive ? 'PREMIUM' : trialActive ? 'TRIAL' : 'FREE';
    const storedBytes = storage._sum.byteSize ?? 0n;
    const reservedBytes = reserved._sum.byteSize ?? 0n;
    return {
      tier,
      advancedEditing: tier !== 'FREE',
      cloudStorageBytes: tier === 'FREE' ? freeBytes : premiumBytes,
      cloudStorageUsedBytes: storedBytes.toString(),
      cloudStorageReservedBytes: reservedBytes.toString(),
      cloudStorageAllocatedBytes: (storedBytes + reservedBytes).toString(),
      trialStartedAt: account.trialStartedAt,
      trialEndsAt: account.trialEndsAt,
      subscription: account.subscription,
      products: {
        monthly: process.env.STORE_MONTHLY_PRODUCT_ID ?? 'migration_companion_premium_monthly',
        yearly: process.env.STORE_YEARLY_PRODUCT_ID ?? 'migration_companion_premium_yearly',
      },
      trialDisclosure: '7 天高级试用不会自动转为付费，也不会创建商店订阅。',
    };
  }

  async startTrial(accountId: string, email: string) {
    const account = await this.ensureAccount(accountId, email);
    if (account.trialStartedAt) throw new ConflictException('此账号已使用过高级试用');
    if (
      account.subscription &&
      ['ACTIVE', 'GRACE'].includes(account.subscription.status)
    ) {
      throw new ConflictException('当前账号已有 Premium 权益');
    }
    const startedAt = new Date();
    const endsAt = new Date(startedAt.getTime() + 7 * 86_400_000);
    await this.prisma.$transaction([
      this.prisma.account.update({
        where: { id: accountId },
        data: { trialStartedAt: startedAt, trialEndsAt: endsAt },
      }),
      this.prisma.auditEvent.create({
        data: {
          accountId,
          action: 'entitlement.trial_started',
          targetType: 'account',
          targetId: accountId,
          safeMetadata: { durationDays: 7 },
        },
      }),
    ]);
    return this.get(accountId, email);
  }

  restore(accountId: string, email: string) {
    // Store verification is server-authoritative. This returns the latest state
    // already written by the Apple/Google verifier rather than trusting a client receipt.
    return this.get(accountId, email);
  }

  async submitPurchase(accountId: string, email: string, dto: SubmitPurchaseDto) {
    const allowedProducts = new Set([
      process.env.STORE_MONTHLY_PRODUCT_ID ?? 'migration_companion_premium_monthly',
      process.env.STORE_YEARLY_PRODUCT_ID ?? 'migration_companion_premium_yearly',
    ]);
    if (!allowedProducts.has(dto.productId)) throw new BadRequestException('未知商店商品');
    await this.ensureAccount(accountId, email);

    if (
      dto.provider === 'LOCAL_SANDBOX' &&
      process.env.NODE_ENV !== 'production' &&
      process.env.DEV_STORE === 'true'
    ) {
      const periodDays = dto.productId.includes('yearly') ? 365 : 30;
      const transaction = `local-${createHash('sha256')
        .update(`${accountId}:${dto.productId}:${dto.verificationData}`)
        .digest('hex')}`;
      await this.applyVerifiedStoreEvent({
        provider: 'GOOGLE',
        productId: dto.productId,
        status: 'ACTIVE',
        originalTransaction: transaction,
        accountEmail: email,
        currentPeriodEndsAt: new Date(Date.now() + periodDays * 86_400_000).toISOString(),
      });
      return { accepted: true, sandbox: true, entitlement: await this.get(accountId, email) };
    }

    if (dto.provider === 'LOCAL_SANDBOX') {
      throw new BadRequestException('本地商店沙盒仅能在非生产环境明确开启');
    }

    // The client receipt is never sufficient to grant access. Production sends
    // this fingerprint to the dedicated Apple/Google verifier and waits for a
    // verified store event before changing entitlement state.
    await this.prisma.auditEvent.create({
      data: {
        accountId,
        action: 'entitlement.purchase_submitted',
        targetType: 'subscription',
        safeMetadata: {
          provider: dto.provider,
          productId: dto.productId,
          receiptFingerprint: createHash('sha256')
            .update(dto.verificationData)
            .digest('hex')
            .slice(0, 16),
        },
      },
    });
    return {
      accepted: true,
      pendingVerification: true,
      message: '购买凭证已提交；权益将在服务端向商店核验成功后生效。',
    };
  }

  async applyVerifiedStoreEvent(dto: VerifiedStoreEventDto) {
    const allowedProducts = new Set([
      process.env.STORE_MONTHLY_PRODUCT_ID ?? 'migration_companion_premium_monthly',
      process.env.STORE_YEARLY_PRODUCT_ID ?? 'migration_companion_premium_yearly',
    ]);
    if (!allowedProducts.has(dto.productId)) throw new BadRequestException('未知商店商品');
    const email = dto.accountEmail.toLowerCase();
    const account = await this.prisma.account.findUnique({ where: { email } });
    if (!account) throw new BadRequestException('找不到对应账号');
    const existing = await this.prisma.subscription.findUnique({
      where: { originalTransaction: dto.originalTransaction },
    });
    if (existing && existing.accountId !== account.id) {
      throw new BadRequestException('交易已关联到其他账号');
    }
    const subscription = await this.prisma.subscription.upsert({
      where: { accountId: account.id },
      create: {
        accountId: account.id,
        provider: dto.provider,
        productId: dto.productId,
        status: dto.status,
        originalTransaction: dto.originalTransaction,
        currentPeriodEndsAt: dto.currentPeriodEndsAt
          ? new Date(dto.currentPeriodEndsAt)
          : undefined,
      },
      update: {
        provider: dto.provider,
        productId: dto.productId,
        status: dto.status,
        originalTransaction: dto.originalTransaction,
        currentPeriodEndsAt: dto.currentPeriodEndsAt
          ? new Date(dto.currentPeriodEndsAt)
          : null,
      },
    });
    await this.prisma.auditEvent.create({
      data: {
        accountId: account.id,
        action: 'entitlement.store_event_applied',
        targetType: 'subscription',
        targetId: subscription.id,
        safeMetadata: {
          provider: dto.provider,
          productId: dto.productId,
          status: dto.status,
          transactionFingerprint: createHash('sha256')
            .update(dto.originalTransaction)
            .digest('hex')
            .slice(0, 16),
        },
      },
    });
    return { applied: true, accountId: account.id, status: subscription.status };
  }

  private ensureAccount(accountId: string, email: string) {
    return this.prisma.account.upsert({
      where: { id: accountId },
      create: { id: accountId, email },
      update: { email },
      include: {
        subscription: {
          select: {
            provider: true,
            productId: true,
            status: true,
            currentPeriodEndsAt: true,
          },
        },
      },
    });
  }
}
