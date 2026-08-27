import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { CollaboratorRole, ProjectTemplate } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { CreateChecklistItemDto, CreateProjectDto, UpdateChecklistDto } from './projects.dto';

const SA_SOURCE_URL = 'https://migration.sa.gov.au/how-to-apply/documents-required';

const templateItems: Record<ProjectTemplate, Array<{ title: string; category: string }>> = {
  SA_190: [
    { title: '护照身份页', category: '身份' },
    { title: '职业评估材料', category: '职业' },
    { title: '工作经历证明', category: '工作' },
    { title: '英语能力证明', category: '语言' },
  ],
  SA_491: [
    { title: '护照身份页', category: '身份' },
    { title: '职业评估材料', category: '职业' },
    { title: '工作经历证明', category: '工作' },
    { title: '英语能力证明', category: '语言' },
    { title: '南澳地区居住或工作材料', category: '南澳' },
  ],
  BLANK: [],
};

@Injectable()
export class ProjectsService {
  constructor(private readonly prisma: PrismaService) {}

  private async ensureAccount(accountId: string, email: string) {
    await this.prisma.account.upsert({
      where: { id: accountId },
      create: { id: accountId, email: email || `${accountId}@cognito.invalid` },
      update: {},
    });
  }

  async list(accountId: string) {
    return this.prisma.project.findMany({
      where: {
        OR: [
          { ownerId: accountId },
          { collaborators: { some: { accountId, acceptedAt: { not: null } } } },
        ],
      },
      select: {
        id: true,
        name: true,
        template: true,
        applicantName: true,
        targetDate: true,
        version: true,
        cloudFilesEnabled: true,
        allowViewerDownload: true,
        updatedAt: true,
        _count: { select: { checklist: true, files: true, collaborators: true } },
      },
      orderBy: { updatedAt: 'desc' },
    });
  }

  async create(accountId: string, email: string, dto: CreateProjectDto) {
    await this.ensureAccount(accountId, email);
    const items = templateItems[dto.template];
    return this.prisma.project.create({
      data: {
        ownerId: accountId,
        name: dto.name,
        template: dto.template,
        applicantName: dto.applicantName,
        targetDate: dto.targetDate ? new Date(dto.targetDate) : undefined,
        collaborators: {
          create: { accountId, role: CollaboratorRole.OWNER, acceptedAt: new Date() },
        },
        checklist: {
          create: items.map((item, index) => ({
            ...item,
            person: dto.applicantName,
            position: index,
            sourceUrl: SA_SOURCE_URL,
            sourceAsOf: new Date('2026-08-27T00:00:00+09:30'),
            reviewAsOf: new Date('2026-08-27T00:00:00+09:30'),
          })),
        },
        auditEvents: {
          create: {
            accountId,
            action: 'project.created',
            targetType: 'project',
            safeMetadata: { template: dto.template },
          },
        },
      },
      include: { checklist: { orderBy: { position: 'asc' } } },
    });
  }

  async get(accountId: string, projectId: string) {
    await this.assertReadable(accountId, projectId);
    const project = await this.prisma.project.findUniqueOrThrow({
      where: { id: projectId },
      include: {
        checklist: { orderBy: { position: 'asc' } },
        files: {
          orderBy: { createdAt: 'desc' },
          select: {
            id: true,
            checklistItemId: true,
            originalName: true,
            contentType: true,
            byteSize: true,
            sha256: true,
            compatibility: true,
            isOriginal: true,
            parentFileId: true,
            scanStatus: true,
            scannedAt: true,
            createdAt: true,
          },
        },
        collaborators: {
          select: { accountId: true, role: true, acceptedAt: true, createdAt: true },
        },
        auditEvents: { orderBy: { createdAt: 'desc' }, take: 50 },
      },
    });
    // byteSize is a BigInt column; JSON responses always carry it as a string.
    // The storage key never leaves the server: it is an internal locator, not an authorisation.
    return {
      ...project,
      files: project.files.map((file) => ({ ...file, byteSize: file.byteSize.toString() })),
    };
  }

  async updateChecklist(
    accountId: string,
    projectId: string,
    itemId: string,
    dto: UpdateChecklistDto,
  ) {
    await this.assertWritable(accountId, projectId);
    return this.prisma.$transaction(async (tx) => {
      const changed = await tx.project.updateMany({
        where: { id: projectId, version: dto.expectedProjectVersion },
        data: { version: { increment: 1 } },
      });
      if (changed.count !== 1) throw new ConflictException('项目已有新版本，请先同步');

      const item = await tx.checklistItem.updateMany({
        where: { id: itemId, projectId },
        data: {
          status: dto.status,
          ...(dto.note !== undefined ? { note: dto.note } : {}),
          ...(dto.clearDueAt
            ? { dueAt: null }
            : dto.dueAt !== undefined
              ? { dueAt: new Date(dto.dueAt) }
              : {}),
          ...(dto.clearReminderAt
            ? { reminderAt: null }
            : dto.reminderAt !== undefined
              ? { reminderAt: new Date(dto.reminderAt) }
              : {}),
        },
      });
      if (item.count !== 1) throw new NotFoundException('未找到材料项');

      await tx.auditEvent.create({
        data: {
          accountId,
          projectId,
          action: 'checklist.updated',
          targetType: 'checklist_item',
          targetId: itemId,
          safeMetadata: {
            status: dto.status,
            dueDateChanged: dto.dueAt !== undefined || dto.clearDueAt === true,
            reminderChanged: dto.reminderAt !== undefined || dto.clearReminderAt === true,
          },
        },
      });
      return { ok: true, projectVersion: dto.expectedProjectVersion + 1 };
    });
  }

  async setCloudFiles(accountId: string, projectId: string, enabled: boolean) {
    await this.assertOwner(accountId, projectId);
    return this.prisma.project.update({
      where: { id: projectId },
      data: {
        cloudFilesEnabled: enabled,
        version: { increment: 1 },
        auditEvents: {
          create: {
            accountId,
            action: enabled ? 'cloud_files.consent_granted' : 'cloud_files.consent_revoked',
            targetType: 'project',
          },
        },
      },
      select: { id: true, cloudFilesEnabled: true, version: true },
    });
  }

  async setViewerDownload(accountId: string, projectId: string, enabled: boolean) {
    await this.assertOwner(accountId, projectId);
    return this.prisma.project.update({
      where: { id: projectId },
      data: {
        allowViewerDownload: enabled,
        version: { increment: 1 },
        auditEvents: {
          create: {
            accountId,
            action: enabled ? 'viewer_download.enabled' : 'viewer_download.disabled',
            targetType: 'project',
          },
        },
      },
      select: { id: true, allowViewerDownload: true, version: true },
    });
  }

  async addChecklistItem(accountId: string, projectId: string, dto: CreateChecklistItemDto) {
    await this.assertWritable(accountId, projectId);
    return this.prisma.$transaction(async (tx) => {
      const project = await tx.project.update({
        where: { id: projectId },
        data: { version: { increment: 1 } },
        select: { version: true, applicantName: true },
      });
      const last = await tx.checklistItem.aggregate({
        where: { projectId },
        _max: { position: true },
      });
      const item = await tx.checklistItem.create({
        data: {
          projectId,
          title: dto.title,
          category: dto.category ?? '自定义',
          person: project.applicantName,
          position: (last._max.position ?? -1) + 1,
        },
      });
      await tx.auditEvent.create({
        data: {
          accountId,
          projectId,
          action: 'checklist.created',
          targetType: 'checklist_item',
          targetId: item.id,
        },
      });
      return { item, projectVersion: project.version };
    });
  }

  private async membership(accountId: string, projectId: string) {
    const project = await this.prisma.project.findUnique({
      where: { id: projectId },
      select: {
        ownerId: true,
        collaborators: {
          where: { accountId, acceptedAt: { not: null } },
          select: { role: true },
        },
      },
    });
    if (!project) throw new NotFoundException('未找到项目');
    if (project.ownerId === accountId) return CollaboratorRole.OWNER;
    return project.collaborators[0]?.role;
  }

  private async assertReadable(accountId: string, projectId: string) {
    if (!(await this.membership(accountId, projectId))) throw new ForbiddenException('无权查看项目');
  }

  private async assertWritable(accountId: string, projectId: string) {
    const role = await this.membership(accountId, projectId);
    if (role !== CollaboratorRole.OWNER && role !== CollaboratorRole.COLLABORATOR) {
      throw new ForbiddenException('当前角色不能修改项目');
    }
  }

  private async assertOwner(accountId: string, projectId: string) {
    if ((await this.membership(accountId, projectId)) !== CollaboratorRole.OWNER) {
      throw new ForbiddenException('只有所有者可以执行此操作');
    }
  }
}
