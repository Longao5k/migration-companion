import {
  ForbiddenException,
  GoneException,
  HttpException,
  HttpStatus,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { GetObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { promisify } from 'node:util';
import { createHash, randomBytes, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { AccessShareDto, CreateShareDto } from './shares.dto';

const scrypt = promisify(scryptCallback);
const codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function hashToken(value: string) {
  return createHash('sha256').update(value).digest('hex');
}

function randomCode() {
  const bytes = randomBytes(12);
  return Array.from(bytes, (byte) => codeAlphabet[byte % codeAlphabet.length]).join('');
}

async function hashCode(value: string) {
  const salt = randomBytes(16);
  const digest = (await scrypt(value, salt, 32)) as Buffer;
  return `${salt.toString('hex')}:${digest.toString('hex')}`;
}

async function verifyCode(value: string, stored: string) {
  const [saltHex, digestHex] = stored.split(':');
  if (!saltHex || !digestHex) return false;
  const actual = (await scrypt(value, Buffer.from(saltHex, 'hex'), 32)) as Buffer;
  const expected = Buffer.from(digestHex, 'hex');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

@Injectable()
export class SharesService {
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

  async list(accountId: string, projectId: string) {
    const project = await this.prisma.project.findFirst({
      where: { id: projectId, ownerId: accountId },
      select: { id: true },
    });
    if (!project) throw new ForbiddenException('只有项目所有者可以查看安全分享');
    const now = new Date();
    const shares = await this.prisma.shareLink.findMany({
      where: { projectId },
      select: {
        id: true,
        scope: true,
        allowDownload: true,
        expiresAt: true,
        revokedAt: true,
        lastAccessedAt: true,
        createdAt: true,
      },
      orderBy: { createdAt: 'desc' },
    });
    return shares.map((share) => ({
      ...share,
      status: share.revokedAt ? 'REVOKED' : share.expiresAt <= now ? 'EXPIRED' : 'ACTIVE',
    }));
  }

  async create(accountId: string, projectId: string, dto: CreateShareDto) {
    const project = await this.prisma.project.findFirst({
      where: { id: projectId, ownerId: accountId },
      select: { id: true, name: true },
    });
    if (!project) throw new ForbiddenException('只有项目所有者可以创建安全分享');
    if (dto.checklistItemIds.length === 0 && dto.fileIds.length === 0) {
      throw new ForbiddenException('请明确选择至少一项分享内容');
    }

    const validItems = await this.prisma.checklistItem.count({
      where: { projectId, id: { in: dto.checklistItemIds } },
    });
    const validFiles = await this.prisma.fileRecord.count({
      where: { projectId, id: { in: dto.fileIds }, scanStatus: 'CLEAN' },
    });
    if (validItems !== dto.checklistItemIds.length || validFiles !== dto.fileIds.length) {
      throw new ForbiddenException('分享范围包含不属于该项目的内容');
    }

    const secret = randomBytes(32).toString('base64url');
    const accessCode = dto.accessCode ?? randomCode();
    const share = await this.prisma.shareLink.create({
      data: {
        projectId,
        createdById: accountId,
        tokenHash: hashToken(secret),
        accessCodeHash: await hashCode(accessCode),
        allowDownload: dto.allowDownload,
        scope: {
          checklistItemIds: dto.checklistItemIds,
          fileIds: dto.fileIds,
          includeNotes: dto.includeNotes,
        },
        expiresAt: new Date(Date.now() + dto.expiresInDays * 86_400_000),
      },
      select: { id: true, expiresAt: true, allowDownload: true },
    });

    await this.prisma.auditEvent.create({
      data: {
        accountId,
        projectId,
        action: 'share.created',
        targetType: 'share',
        targetId: share.id,
        safeMetadata: { expiresInDays: dto.expiresInDays, allowDownload: dto.allowDownload },
      },
    });

    const origin = process.env.SHARE_ORIGIN ?? 'http://localhost:3001';
    return {
      ...share,
      url: `${origin}/s/${share.id}#${secret}`,
      accessCode,
      warning: '访问码请与链接分开发送；已下载或截屏的副本无法远程收回。',
    };
  }

  async access(shareId: string, dto: AccessShareDto) {
    const share = await this.prisma.shareLink.findUnique({
      where: { id: shareId },
      include: { project: { select: { name: true } } },
    });
    if (!share || !timingSafeEqual(Buffer.from(hashToken(dto.secret)), Buffer.from(share.tokenHash))) {
      throw new NotFoundException('分享不存在');
    }
    if (share.revokedAt) throw new GoneException('分享已撤销');
    if (share.expiresAt <= new Date()) throw new GoneException('分享已过期');
    if (share.lockedUntil && share.lockedUntil > new Date()) {
      throw new HttpException('尝试次数过多，请稍后再试', HttpStatus.TOO_MANY_REQUESTS);
    }

    if (!(await verifyCode(dto.accessCode, share.accessCodeHash))) {
      const nextAttempts = share.attempts + 1;
      await this.prisma.shareLink.update({
        where: { id: share.id },
        data: {
          attempts: nextAttempts,
          ...(nextAttempts >= 5
            ? { lockedUntil: new Date(Date.now() + 15 * 60_000), attempts: 0 }
            : {}),
        },
      });
      throw new ForbiddenException('访问码错误');
    }

    await this.prisma.shareLink.update({
      where: { id: share.id },
      data: { attempts: 0, lockedUntil: null, lastAccessedAt: new Date() },
    });
    const scope = share.scope as {
      checklistItemIds?: string[];
      fileIds?: string[];
      includeNotes?: boolean;
    };
    const [items, files] = await Promise.all([
      this.prisma.checklistItem.findMany({
        where: { projectId: share.projectId, id: { in: scope.checklistItemIds ?? [] } },
        select: { id: true, title: true, category: true, status: true, note: true },
        orderBy: { position: 'asc' },
      }),
      this.prisma.fileRecord.findMany({
        where: {
          projectId: share.projectId,
          id: { in: scope.fileIds ?? [] },
          scanStatus: 'CLEAN',
        },
        select: {
          id: true,
          originalName: true,
          contentType: true,
          byteSize: true,
          storageKey: true,
        },
      }),
    ]);
    return {
      id: share.id,
      projectName: share.project.name,
      scope: share.scope,
      allowDownload: share.allowDownload,
      expiresAt: share.expiresAt,
      items: items.map((item) => ({
        ...item,
        ...(!scope.includeNotes ? { note: undefined } : {}),
      })),
      files: await Promise.all(
        files.map(async (file) => ({
          id: file.id,
          displayName: file.originalName,
          contentType: file.contentType,
          byteSize: file.byteSize.toString(),
          downloadUrl:
            share.allowDownload && this.bucket
              ? await getSignedUrl(
                  this.s3,
                  new GetObjectCommand({
                    Bucket: this.bucket,
                    Key: file.storageKey,
                    ResponseContentDisposition: `attachment; filename*=UTF-8''${encodeURIComponent(file.originalName)}`,
                  }),
                  { expiresIn: 60 },
                )
              : null,
        })),
      ),
      warning: '分享者可以撤销未来访问，但无法收回已经保存或截屏的副本。',
    };
  }

  async revoke(accountId: string, shareId: string) {
    const share = await this.prisma.shareLink.findFirst({
      where: { id: shareId, createdById: accountId },
      select: { id: true, projectId: true },
    });
    if (!share) throw new NotFoundException('未找到分享');
    await this.prisma.$transaction([
      this.prisma.shareLink.update({ where: { id: shareId }, data: { revokedAt: new Date() } }),
      this.prisma.auditEvent.create({
        data: {
          accountId,
          projectId: share.projectId,
          action: 'share.revoked',
          targetType: 'share',
          targetId: shareId,
        },
      }),
    ]);
    return { revoked: true };
  }
}
