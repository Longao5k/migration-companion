import {
  BadRequestException,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { DeleteObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { createHmac } from 'node:crypto';
import { PrismaService } from '../prisma.service';

const deletionDelayMs = 7 * 24 * 60 * 60 * 1000;

@Injectable()
export class AccountDeletionService {
  private readonly bucket = process.env.S3_USER_BUCKET ?? '';
  private readonly s3 = new S3Client({
    region: process.env.S3_REGION ?? 'ap-southeast-2',
    ...(process.env.S3_ENDPOINT
      ? {
          endpoint: process.env.S3_ENDPOINT,
          forcePathStyle: process.env.S3_FORCE_PATH_STYLE === 'true',
        }
      : {}),
  });

  constructor(private readonly prisma: PrismaService) {}

  async request(accountId: string) {
    const requestedAt = new Date();
    await this.prisma.account.update({
      where: { id: accountId },
      data: { deletionRequestedAt: requestedAt },
    });
    return {
      accepted: true,
      requestedAt,
      scheduledFor: new Date(requestedAt.getTime() + deletionDelayMs),
      targetDeletionDays: 7,
      backupRemovalDays: 35,
    };
  }

  async cancel(accountId: string) {
    const account = await this.prisma.account.findUnique({
      where: { id: accountId },
      select: { deletionRequestedAt: true },
    });
    if (!account?.deletionRequestedAt) {
      throw new BadRequestException('当前账号没有待处理的删除申请');
    }
    await this.prisma.account.update({
      where: { id: accountId },
      data: { deletionRequestedAt: null },
    });
    return { cancelled: true };
  }

  async runDueDeletions() {
    const cutoff = new Date(Date.now() - deletionDelayMs);
    const accounts = await this.prisma.account.findMany({
      where: { deletionRequestedAt: { lte: cutoff } },
      select: { id: true, deletionRequestedAt: true },
      orderBy: { deletionRequestedAt: 'asc' },
      take: 25,
    });
    let deleted = 0;
    let failed = 0;
    for (const account of accounts) {
      try {
        await this.deleteAccount(account.id, account.deletionRequestedAt!);
        deleted++;
      } catch {
        failed++;
        try {
          await this.prisma.auditEvent.create({
            data: {
              accountId: account.id,
              action: 'account.deletion_failed',
              targetType: 'account',
            },
          });
        } catch {
          // A concurrent worker may already have deleted the account. Do not
          // abort the remainder of this batch solely because its audit parent
          // no longer exists.
        }
      }
    }
    return { examined: accounts.length, deleted, failed };
  }

  private async deleteAccount(accountId: string, requestedAt: Date) {
    const salt = process.env.DELETION_LEDGER_SALT;
    if (process.env.NODE_ENV === 'production' && !salt) {
      // Validate every prerequisite before deleting an object. A deployment
      // misconfiguration must not leave live database records pointing at
      // bytes that have already been removed.
      throw new ServiceUnavailableException('删除证明散列密钥未配置');
    }
    const accountHash = createHmac(
      'sha256',
      salt ?? 'local-development-deletion-ledger-only',
    )
      .update(accountId)
      .digest('hex');

    const ownedProjects = await this.prisma.project.findMany({
      where: { ownerId: accountId },
      select: { id: true },
    });
    const ownedProjectIds = ownedProjects.map((project) => project.id);
    const [files, sessions] = await Promise.all([
      this.prisma.fileRecord.findMany({
        where: {
          OR: [{ projectId: { in: ownedProjectIds } }, { uploadedById: accountId }],
        },
        select: { id: true, storageKey: true, projectId: true },
      }),
      this.prisma.uploadSession.findMany({
        where: {
          OR: [{ projectId: { in: ownedProjectIds } }, { accountId }],
        },
        select: { id: true, storageKey: true },
      }),
    ]);
    const objectKeys = [...new Set([...files, ...sessions].map((item) => item.storageKey))];
    if (objectKeys.length > 0 && !this.bucket) {
      throw new ServiceUnavailableException('对象存储未配置，不能确认删除完成');
    }
    for (const storageKey of objectKeys) {
      await this.s3.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: storageKey }));
    }

    await this.prisma.$transaction(async (tx) => {
      // 删除账号在其他人项目中上传的文件记录；相关对象已在事务前幂等清理。
      await tx.fileRecord.deleteMany({
        where: { uploadedById: accountId, projectId: { notIn: ownedProjectIds } },
      });
      await tx.uploadSession.deleteMany({
        where: { OR: [{ projectId: { in: ownedProjectIds } }, { accountId }] },
      });
      await tx.accountDeletionLedger.create({
        data: {
          accountHash,
          requestedAt,
          objectCount: objectKeys.length,
        },
      });
      await tx.account.delete({ where: { id: accountId } });
    });
  }
}
