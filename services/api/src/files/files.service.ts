import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  CopyObjectCommand,
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { CollaboratorRole, FileScanStatus } from '@prisma/client';
import { createHash, randomUUID } from 'node:crypto';
import { extname } from 'node:path';
import { PrismaService } from '../prisma.service';
import { CompleteUploadDto, CreateUploadDto, ScanResultDto } from './files.dto';
import { cloudFileUploadsEnabled, cloudFilesDisabledMessage } from './cloud-files';

const allowedTypes = new Set([
  'application/pdf',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/msword',
  'image/jpeg',
  'image/png',
  'image/heic',
]);

@Injectable()
export class FilesService {
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
  private readonly signedUrlS3 = process.env.S3_PUBLIC_ENDPOINT
    ? new S3Client({
        region: process.env.S3_REGION ?? 'ap-southeast-2',
        endpoint: process.env.S3_PUBLIC_ENDPOINT,
        forcePathStyle: process.env.S3_FORCE_PATH_STYLE === 'true',
      })
    : this.s3;

  constructor(private readonly prisma: PrismaService) {}

  async createUpload(accountId: string, projectId: string, dto: CreateUploadDto) {
    if (!cloudFileUploadsEnabled()) {
      throw new ServiceUnavailableException(cloudFilesDisabledMessage);
    }
    if (!this.bucket) throw new ServiceUnavailableException('文件存储尚未配置');
    if (!allowedTypes.has(dto.contentType)) throw new BadRequestException('不支持此文件类型');
    const ownerId = await this.assertCanUpload(accountId, projectId);
    await this.assertChecklistScope(projectId, dto.checklistItemId);
    await this.assertStorageQuota(ownerId, dto.byteSize);

    const id = randomUUID();
    const storageKey = `quarantine/${projectId}/${id}`;
    const session = await this.prisma.uploadSession.create({
      data: {
        id,
        projectId,
        accountId,
        storageKey,
        originalName: dto.originalName,
        contentType: dto.contentType,
        byteSize: BigInt(dto.byteSize),
        sha256: dto.sha256,
        expiresAt: new Date(Date.now() + 10 * 60_000),
      },
    });
    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: storageKey,
      ContentType: dto.contentType,
      ContentLength: dto.byteSize,
      Metadata: { sha256: dto.sha256, upload: id },
      ServerSideEncryption: process.env.S3_ENDPOINT ? undefined : 'aws:kms',
      ...(process.env.S3_KMS_KEY_ID ? { SSEKMSKeyId: process.env.S3_KMS_KEY_ID } : {}),
    });
    const uploadUrl = await getSignedUrl(this.signedUrlS3, command, { expiresIn: 600 });
    return {
      uploadId: session.id,
      uploadUrl,
      expiresAt: session.expiresAt,
      requiredHeaders: {
        'content-type': dto.contentType,
      },
    };
  }

  async complete(accountId: string, uploadId: string, dto: CompleteUploadDto) {
    if (!cloudFileUploadsEnabled()) {
      throw new ServiceUnavailableException(cloudFilesDisabledMessage);
    }

    const session = await this.prisma.uploadSession.findFirst({
      where: { id: uploadId, accountId },
    });
    if (!session) throw new NotFoundException('未找到上传会话');
    if (session.completedAt && session.fileId) {
      const existing = await this.prisma.fileRecord.findUnique({ where: { id: session.fileId } });
      if (!existing) throw new NotFoundException('已完成上传对应的文件已不存在');
      return { ...existing, byteSize: existing.byteSize.toString(), idempotent: true };
    }
    if (session.expiresAt <= new Date()) throw new BadRequestException('上传会话已过期');
    await this.assertCanUpload(accountId, session.projectId);
    await this.assertChecklistScope(session.projectId, dto.checklistItemId);

    let head;
    try {
      head = await this.s3.send(new HeadObjectCommand({ Bucket: this.bucket, Key: session.storageKey }));
    } catch {
      throw new BadRequestException('尚未找到已上传的对象');
    }
    if (head.ContentLength !== Number(session.byteSize)) throw new BadRequestException('文件大小校验失败');
    if (head.ContentType !== session.contentType) throw new BadRequestException('文件类型校验失败');
    if (head.Metadata?.sha256 !== session.sha256 || head.Metadata?.upload !== session.id) {
      throw new BadRequestException('文件校验信息不一致');
    }
    await this.assertMagicBytes(session.storageKey, session.contentType);

    const extension = extname(session.originalName).toLowerCase();
    const compatibility =
      extension === '.pdf' ? 'PDF_SUPPORTED' : extension === '.docx' ? 'DOCX_REQUIRES_PREFLIGHT' : 'READ_ONLY';
    const result = await this.prisma.$transaction(async (tx) => {
      const record = await tx.fileRecord.create({
        data: {
          projectId: session.projectId,
          checklistItemId: dto.checklistItemId,
          uploadedById: accountId,
          originalName: session.originalName,
          storageKey: session.storageKey,
          contentType: session.contentType,
          byteSize: session.byteSize,
          sha256: session.sha256,
          compatibility,
        },
      });
      await tx.uploadSession.update({
        where: { id: session.id },
        data: { completedAt: new Date(), fileId: record.id },
      });
      await tx.auditEvent.create({
        data: {
          accountId,
          projectId: session.projectId,
          action: 'file.upload_completed',
          targetType: 'file',
          targetId: record.id,
          safeMetadata: { contentType: record.contentType, byteSize: Number(record.byteSize) },
        },
      });
      return record;
    });
    if (process.env.NODE_ENV !== 'production' && process.env.DEV_AUTO_SCAN === 'true') {
      const scanned = await this.applyScanResult(result.id, {
        status: FileScanStatus.CLEAN,
        scannerVersion: 'local-development-simulation',
      });
      return {
        ...result,
        byteSize: result.byteSize.toString(),
        scanStatus: 'scanStatus' in scanned ? scanned.scanStatus : scanned.status,
        localDevelopmentScan: true,
      };
    }
    return { ...result, byteSize: result.byteSize.toString() };
  }

  async directUpload(
    accountId: string,
    projectId: string,
    file: Express.Multer.File | undefined,
    checklistItemId?: string,
  ) {
    if (!cloudFileUploadsEnabled()) {
      throw new ServiceUnavailableException(cloudFilesDisabledMessage);
    }
    if (!this.bucket) throw new ServiceUnavailableException('文件存储尚未配置');
    if (!file) throw new BadRequestException('请选择文件');
    if (!allowedTypes.has(file.mimetype)) throw new BadRequestException('不支持此文件类型');
    if (file.size < 1 || file.size > 50 * 1024 * 1024) {
      throw new BadRequestException('文件必须介于 1 B 和 50 MB 之间');
    }
    const ownerId = await this.assertCanUpload(accountId, projectId);
    await this.assertChecklistScope(projectId, checklistItemId);
    await this.assertStorageQuota(ownerId, file.size);
    this.assertMagicByteBuffer(file.buffer, file.mimetype);

    const fileId = randomUUID();
    const storageKey = `quarantine/${projectId}/${fileId}`;
    const digest = createHash('sha256').update(file.buffer).digest('hex');
    await this.s3.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: storageKey,
        Body: file.buffer,
        ContentType: file.mimetype,
        ContentLength: file.size,
        Metadata: { sha256: digest, direct: 'true' },
        ServerSideEncryption: process.env.S3_ENDPOINT ? undefined : 'aws:kms',
        ...(process.env.S3_KMS_KEY_ID ? { SSEKMSKeyId: process.env.S3_KMS_KEY_ID } : {}),
      }),
    );
    const extension = extname(file.originalname).toLowerCase();
    const compatibility =
      extension === '.pdf' ? 'PDF_SUPPORTED' : extension === '.docx' ? 'DOCX_REQUIRES_PREFLIGHT' : 'READ_ONLY';
    const record = await this.prisma.$transaction(async (tx) => {
      const created = await tx.fileRecord.create({
        data: {
          id: fileId,
          projectId,
          checklistItemId,
          uploadedById: accountId,
          originalName: file.originalname,
          storageKey,
          contentType: file.mimetype,
          byteSize: BigInt(file.size),
          sha256: digest,
          compatibility,
        },
      });
      await tx.auditEvent.create({
        data: {
          accountId,
          projectId,
          action: 'file.direct_upload_completed',
          targetType: 'file',
          targetId: created.id,
          safeMetadata: { contentType: created.contentType, byteSize: file.size },
        },
      });
      return created;
    });
    if (process.env.NODE_ENV !== 'production' && process.env.DEV_AUTO_SCAN === 'true') {
      const scanned = await this.applyScanResult(record.id, {
        status: FileScanStatus.CLEAN,
        scannerVersion: 'local-development-simulation',
      });
      return {
        ...record,
        byteSize: record.byteSize.toString(),
        scanStatus: 'scanStatus' in scanned ? scanned.scanStatus : scanned.status,
        localDevelopmentScan: true,
      };
    }
    return { ...record, byteSize: record.byteSize.toString() };
  }

  async createDownload(accountId: string, fileId: string) {
    if (!this.bucket) throw new ServiceUnavailableException('文件存储尚未配置');
    const file = await this.prisma.fileRecord.findUnique({
      where: { id: fileId },
      select: {
        id: true,
        projectId: true,
        originalName: true,
        contentType: true,
        byteSize: true,
        storageKey: true,
        scanStatus: true,
        project: {
          select: {
            ownerId: true,
            allowViewerDownload: true,
            collaborators: {
              where: { accountId, acceptedAt: { not: null } },
              select: { role: true },
            },
          },
        },
      },
    });
    if (!file) throw new NotFoundException('未找到文件');
    const membership = file.project.collaborators[0];
    const isOwner = file.project.ownerId === accountId;
    if (!isOwner && !membership) throw new ForbiddenException('无权访问此文件');
    if (
      !isOwner &&
      membership.role === CollaboratorRole.VIEWER &&
      !file.project.allowViewerDownload
    ) {
      throw new ForbiddenException('项目所有者未允许查看者下载文件');
    }
    if (file.scanStatus !== FileScanStatus.CLEAN) {
      throw new ForbiddenException('文件尚未通过安全扫描，不能下载');
    }
    const downloadUrl = await getSignedUrl(
      this.signedUrlS3,
      new GetObjectCommand({
        Bucket: this.bucket,
        Key: file.storageKey,
        ResponseContentDisposition: `attachment; filename*=UTF-8''${encodeURIComponent(file.originalName)}`,
      }),
      { expiresIn: 60 },
    );
    await this.prisma.auditEvent.create({
      data: {
        accountId,
        projectId: file.projectId,
        action: 'file.download_link_created',
        targetType: 'file',
        targetId: file.id,
      },
    });
    return {
      id: file.id,
      displayName: file.originalName,
      contentType: file.contentType,
      byteSize: file.byteSize.toString(),
      downloadUrl,
      expiresInSeconds: 60,
    };
  }

  /**
   * 冻结的角色规则：所有者可以删除项目内任何文件；可协作成员只能删除自己上传的文件；
   * 仅查看成员不能删除。删除同时移除对象存储中的字节，并让引用该文件的安全分享失效。
   */
  async deleteFile(accountId: string, fileId: string) {
    if (!this.bucket) throw new ServiceUnavailableException('文件存储尚未配置');
    const file = await this.prisma.fileRecord.findUnique({
      where: { id: fileId },
      select: {
        id: true,
        projectId: true,
        storageKey: true,
        contentType: true,
        byteSize: true,
        uploadedById: true,
        scanStatus: true,
        project: {
          select: {
            ownerId: true,
            collaborators: {
              where: { accountId, acceptedAt: { not: null } },
              select: { role: true },
            },
          },
        },
      },
    });
    if (!file) throw new NotFoundException('未找到文件');

    const isOwner = file.project.ownerId === accountId;
    const membership = file.project.collaborators[0];
    if (!isOwner) {
      if (!membership) throw new ForbiddenException('无权访问此文件');
      if (membership.role !== CollaboratorRole.COLLABORATOR) {
        throw new ForbiddenException('当前角色不能删除文件');
      }
      if (file.uploadedById !== accountId) {
        throw new ForbiddenException('只能删除自己上传的文件');
      }
    }

    // 先删对象再删记录。反过来的话，对象清理失败会留下用户看不见、也无法重试的残留字节，
    // 而用户已经被告知文件已删除。DeleteObject 对不存在的 key 是幂等的，重试安全。
    try {
      await this.s3.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: file.storageKey }));
    } catch {
      await this.prisma.auditEvent.create({
        data: {
          accountId,
          projectId: file.projectId,
          action: 'file.object_delete_failed',
          targetType: 'file',
          targetId: file.id,
        },
      });
      throw new ServiceUnavailableException('云端对象清理失败，文件未删除，请稍后重试');
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.fileRecord.delete({ where: { id: file.id } });
      await tx.auditEvent.create({
        data: {
          accountId,
          projectId: file.projectId,
          action: 'file.deleted',
          targetType: 'file',
          targetId: file.id,
          safeMetadata: {
            contentType: file.contentType,
            byteSize: Number(file.byteSize),
            scanStatus: file.scanStatus,
            deletedByOwner: isOwner,
          },
        },
      });
    });

    return { deleted: true, id: file.id };
  }

  async applyScanResult(fileId: string, dto: ScanResultDto) {
    if (dto.status === FileScanStatus.PENDING) {
      throw new BadRequestException('扫描结果不能仍为待处理');
    }
    const file = await this.prisma.fileRecord.findUnique({ where: { id: fileId } });
    if (!file) throw new NotFoundException('未找到文件');
    if (file.scanStatus !== FileScanStatus.PENDING && file.scanStatus !== FileScanStatus.ERROR) {
      return { id: file.id, status: file.scanStatus, idempotent: true };
    }

    let storageKey = file.storageKey;
    if (dto.status === FileScanStatus.CLEAN) {
      storageKey = `clean/${file.projectId}/${randomUUID()}`;
      await this.s3.send(
        new CopyObjectCommand({
          Bucket: this.bucket,
          Key: storageKey,
          CopySource: `${this.bucket}/${file.storageKey}`,
          MetadataDirective: 'COPY',
          ServerSideEncryption: process.env.S3_ENDPOINT ? undefined : 'aws:kms',
          ...(process.env.S3_KMS_KEY_ID ? { SSEKMSKeyId: process.env.S3_KMS_KEY_ID } : {}),
        }),
      );
      await this.s3.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: file.storageKey }));
    } else if (dto.status === FileScanStatus.REJECTED) {
      await this.s3.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: file.storageKey }));
    }

    const updated = await this.prisma.fileRecord.update({
      where: { id: file.id },
      data: {
        scanStatus: dto.status,
        scannerVersion: dto.scannerVersion,
        scannedAt: new Date(),
        storageKey,
      },
      select: { id: true, scanStatus: true, scannedAt: true },
    });
    await this.prisma.auditEvent.create({
      data: {
        projectId: file.projectId,
        action: `file.scan_${dto.status.toLowerCase()}`,
        targetType: 'file',
        targetId: file.id,
        safeMetadata: { scannerVersion: dto.scannerVersion },
      },
    });
    return updated;
  }

  async cleanupExpiredUploads() {
    const sessions = await this.prisma.uploadSession.findMany({
      where: { completedAt: null, expiresAt: { lt: new Date() } },
      select: { id: true, storageKey: true },
      orderBy: { expiresAt: 'asc' },
      take: 100,
    });
    let deleted = 0;
    let failed = 0;
    for (const session of sessions) {
      try {
        if (!this.bucket) {
          throw new ServiceUnavailableException('文件存储尚未配置');
        }
        // S3 DeleteObject is idempotent, so a retry is safe when the client
        // never uploaded bytes or another worker already removed the object.
        await this.s3.send(
          new DeleteObjectCommand({ Bucket: this.bucket, Key: session.storageKey }),
        );
        const removed = await this.prisma.uploadSession.deleteMany({
          where: { id: session.id, completedAt: null },
        });
        deleted += removed.count;
      } catch {
        failed++;
      }
    }
    return { examined: sessions.length, deleted, failed };
  }

  private async assertCanUpload(accountId: string, projectId: string) {
    const project = await this.prisma.project.findUnique({
      where: { id: projectId },
      select: {
        ownerId: true,
        cloudFilesEnabled: true,
        collaborators: {
          where: {
            accountId,
            acceptedAt: { not: null },
            role: { in: [CollaboratorRole.OWNER, CollaboratorRole.COLLABORATOR] },
          },
          select: { id: true },
        },
      },
    });
    if (!project) throw new NotFoundException('未找到项目');
    if (project.ownerId !== accountId && project.collaborators.length === 0) {
      throw new ForbiddenException('当前角色不能上传文件');
    }
    if (!project.cloudFilesEnabled) {
      throw new ForbiddenException('必须先明确开启此项目的云文件同步');
    }
    return project.ownerId;
  }

  private async assertStorageQuota(ownerId: string, additionalBytes: number) {
    const ownedProjectIds = await this.ownedProjectIds(ownerId);
    const [account, stored, pending] = await Promise.all([
      this.prisma.account.findUnique({
        where: { id: ownerId },
        select: {
          trialEndsAt: true,
          subscription: { select: { status: true, currentPeriodEndsAt: true } },
        },
      }),
      this.prisma.fileRecord.aggregate({
        where: { project: { ownerId } },
        _sum: { byteSize: true },
      }),
      this.prisma.uploadSession.aggregate({
        where: {
          projectId: { in: ownedProjectIds },
          completedAt: null,
          expiresAt: { gt: new Date() },
        },
        _sum: { byteSize: true },
      }),
    ]);
    const now = new Date();
    const subscriptionActive = Boolean(
      account?.subscription &&
        ['ACTIVE', 'GRACE'].includes(account.subscription.status) &&
        (!account.subscription.currentPeriodEndsAt || account.subscription.currentPeriodEndsAt > now),
    );
    const trialActive = Boolean(account?.trialEndsAt && account.trialEndsAt > now);
    const limit = BigInt(subscriptionActive || trialActive ? 10 * 1024 ** 3 : 1024 ** 3);
    const used = (stored._sum.byteSize ?? 0n) + (pending._sum.byteSize ?? 0n);
    if (used + BigInt(additionalBytes) > limit) {
      throw new ForbiddenException('云存储空间不足，请清理文件或升级订阅');
    }
  }

  private async ownedProjectIds(ownerId: string) {
    const projects = await this.prisma.project.findMany({ where: { ownerId }, select: { id: true } });
    return projects.map((project) => project.id);
  }

  private async assertMagicBytes(storageKey: string, contentType: string) {
    let bytes: Uint8Array;
    try {
      const object = await this.s3.send(
        new GetObjectCommand({ Bucket: this.bucket, Key: storageKey, Range: 'bytes=0-511' }),
      );
      bytes = (await object.Body?.transformToByteArray()) ?? new Uint8Array();
    } catch {
      throw new BadRequestException('无法读取文件内容进行安全校验');
    }
    this.assertMagicByteBuffer(bytes, contentType);
  }

  private assertMagicByteBuffer(bytes: Uint8Array, contentType: string) {
    const startsWith = (...signature: number[]) =>
      bytes.length >= signature.length && signature.every((value, index) => bytes[index] === value);
    const ascii = new TextDecoder('ascii').decode(bytes);
    const valid =
      (contentType === 'application/pdf' && ascii.startsWith('%PDF-')) ||
      (contentType === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' &&
        startsWith(0x50, 0x4b)) ||
      (contentType === 'application/msword' &&
        startsWith(0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1)) ||
      (contentType === 'image/jpeg' && startsWith(0xff, 0xd8, 0xff)) ||
      (contentType === 'image/png' && startsWith(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)) ||
      (contentType === 'image/heic' &&
        bytes.length >= 12 &&
        ascii.slice(4, 8) === 'ftyp' &&
        ['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].includes(ascii.slice(8, 12)));
    if (!valid) throw new BadRequestException('文件内容与声明类型不一致');
  }

  private async assertChecklistScope(projectId: string, checklistItemId?: string) {
    if (!checklistItemId) return;
    const count = await this.prisma.checklistItem.count({ where: { id: checklistItemId, projectId } });
    if (count !== 1) throw new ForbiddenException('材料项不属于此项目');
  }
}
