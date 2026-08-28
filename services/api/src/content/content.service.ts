import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { ChangeImportance, ReviewStatus } from '@prisma/client';
import { createHash } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import {
  CreateNewsDto,
  CreateSourceDto,
  IngestChangeDto,
  IngestNewsDto,
  ReviewChangeDto,
  SourceCheckDto,
  UpdateNewsDto,
  UpdateSourceDto,
} from './content.dto';

@Injectable()
export class ContentService {
  constructor(private readonly prisma: PrismaService) {}

  news() {
    return this.prisma.newsItem.findMany({
      where: { isPublished: true, publishedAt: { lte: new Date() } },
      include: { source: { select: { name: true, sourceType: true } } },
      orderBy: { publishedAt: 'desc' },
      take: 100,
    });
  }

  changes() {
    return this.prisma.changeLog.findMany({
      where: {
        publishedAt: { not: null },
        OR: [
          { reviewStatus: ReviewStatus.VERIFIED },
          { reviewStatus: ReviewStatus.CORRECTED },
          { importance: ChangeImportance.GENERAL, reviewStatus: ReviewStatus.PENDING },
        ],
      },
      include: { source: { select: { name: true, url: true, sourceType: true } } },
      orderBy: { publishedAt: 'desc' },
      take: 100,
    });
  }

  reviewQueue() {
    return this.prisma.changeLog.findMany({
      where: { reviewStatus: ReviewStatus.PENDING },
      include: { source: true },
      orderBy: [{ importance: 'desc' }, { discoveredAt: 'asc' }],
    });
  }

  adminChanges() {
    return this.prisma.changeLog.findMany({
      include: { source: true },
      orderBy: { discoveredAt: 'desc' },
      take: 500,
    });
  }

  corrections() {
    return this.prisma.changeLog.findMany({
      where: { reviewStatus: ReviewStatus.CORRECTED, correctionNote: { not: null } },
      include: { source: true },
      orderBy: { verifiedAt: 'desc' },
      take: 200,
    });
  }

  sources() {
    return this.prisma.source.findMany({ orderBy: [{ enabled: 'desc' }, { name: 'asc' }] });
  }

  async createSource(dto: CreateSourceDto) {
    return this.prisma.source.create({
      data: {
        name: dto.name.trim(),
        url: dto.url,
        jurisdiction: dto.jurisdiction,
        sourceType: dto.sourceType,
        licenseNote: dto.licenseNote?.trim(),
        enabled: dto.enabled ?? false,
      },
    });
  }

  async updateSource(id: string, dto: UpdateSourceDto) {
    await this.requireSource(id);
    return this.prisma.source.update({
      where: { id },
      data: {
        ...(dto.name !== undefined ? { name: dto.name.trim() } : {}),
        ...(dto.jurisdiction !== undefined ? { jurisdiction: dto.jurisdiction } : {}),
        ...(dto.sourceType !== undefined ? { sourceType: dto.sourceType } : {}),
        ...(dto.licenseNote !== undefined ? { licenseNote: dto.licenseNote.trim() } : {}),
        ...(dto.enabled !== undefined ? { enabled: dto.enabled } : {}),
      },
    });
  }

  adminNews() {
    return this.prisma.newsItem.findMany({
      include: { source: true },
      orderBy: { updatedAt: 'desc' },
      take: 500,
    });
  }

  async createNews(dto: CreateNewsDto) {
    const source = await this.requireSource(dto.sourceId);
    this.assertSourceUrl(source.url, dto.sourceUrl);
    if (dto.isPublished) this.assertChineseEditorialCopy(dto.titleZh, dto.summaryZh);
    return this.prisma.newsItem.create({
      data: {
        sourceId: source.id,
        titleZh: dto.titleZh.trim(),
        summaryZh: dto.summaryZh.trim(),
        sourceTitle: dto.sourceTitle.trim(),
        sourceUrl: dto.sourceUrl,
        tags: this.cleanTags(dto.tags),
        publishedAt: new Date(dto.publishedAt),
        isPublished: dto.isPublished ?? false,
      },
      include: { source: true },
    });
  }

  async updateNews(id: string, dto: UpdateNewsDto) {
    const current = await this.prisma.newsItem.findUnique({
      where: { id },
      include: { source: true },
    });
    if (!current) throw new NotFoundException('未找到新闻');
    if (dto.sourceUrl !== undefined) this.assertSourceUrl(current.source.url, dto.sourceUrl);
    if (dto.isPublished === true) {
      this.assertChineseEditorialCopy(
        dto.titleZh ?? current.titleZh,
        dto.summaryZh ?? current.summaryZh,
      );
    }
    return this.prisma.newsItem.update({
      where: { id },
      data: {
        ...(dto.titleZh !== undefined ? { titleZh: dto.titleZh.trim() } : {}),
        ...(dto.summaryZh !== undefined ? { summaryZh: dto.summaryZh.trim() } : {}),
        ...(dto.sourceTitle !== undefined ? { sourceTitle: dto.sourceTitle.trim() } : {}),
        ...(dto.sourceUrl !== undefined ? { sourceUrl: dto.sourceUrl } : {}),
        ...(dto.tags !== undefined ? { tags: this.cleanTags(dto.tags) } : {}),
        ...(dto.publishedAt !== undefined ? { publishedAt: new Date(dto.publishedAt) } : {}),
        ...(dto.isPublished !== undefined ? { isPublished: dto.isPublished } : {}),
      },
      include: { source: true },
    });
  }

  async tags() {
    const [news, changes] = await Promise.all([
      this.prisma.newsItem.findMany({ select: { tags: true } }),
      this.prisma.changeLog.findMany({ select: { tags: true } }),
    ]);
    return [...new Set([...news, ...changes].flatMap((item) => item.tags))].sort((a, b) =>
      a.localeCompare(b, 'zh-CN'),
    );
  }

  sourceHealth() {
    return this.prisma.source.findMany({
      include: {
        snapshots: {
          orderBy: { fetchedAt: 'desc' },
          take: 1,
          select: {
            contentHash: true,
            httpStatus: true,
            fetchedAt: true,
            etag: true,
            lastModified: true,
          },
        },
        _count: { select: { snapshots: true, changes: true, news: true } },
      },
      orderBy: [{ enabled: 'desc' }, { name: 'asc' }],
    });
  }

  async ingest(dto: IngestChangeDto) {
    const source = await this.prisma.source.upsert({
      where: { url: dto.sourceUrl },
      create: {
        url: dto.sourceUrl,
        name: dto.sourceName,
        jurisdiction: dto.sourceUrl.includes('migration.sa.gov.au') ? 'AU-SA' : 'AU-FED',
        licenseNote: dto.sourceUrl.includes('migration.sa.gov.au')
          ? 'SA Government content: verify page-level exclusions and retain attribution.'
          : 'Internal evidence only; publish links and short original summaries.',
      },
      update: { name: dto.sourceName, lastCheckedAt: new Date() },
    });
    const candidateHash = createHash('sha256')
      .update(
        JSON.stringify({
          sourceId: source.id,
          oldExcerpt: dto.oldExcerpt ?? '',
          newExcerpt: dto.newExcerpt ?? '',
          context: dto.context ?? '',
        }),
      )
      .digest('hex');
    return this.prisma.changeLog.upsert({
      where: { id: `change-${candidateHash}` },
      create: {
        id: `change-${candidateHash}`,
        candidateHash,
        sourceId: source.id,
        titleZh: dto.titleZh,
        oldExcerpt: dto.oldExcerpt,
        newExcerpt: dto.newExcerpt,
        context: dto.context,
        importance: dto.importance,
        tags: this.cleanTags(dto.tags ?? []),
        discoveredAt: new Date(dto.discoveredAt),
        ...(dto.importance === ChangeImportance.GENERAL ? { publishedAt: new Date() } : {}),
      },
      update: {},
    });
  }

  async ingestNews(dto: IngestNewsDto) {
    const source = await this.prisma.source.findUnique({
      where: { url: dto.sourceRegistryUrl },
    });
    if (!source?.enabled) {
      throw new BadRequestException('新闻发现任务只能使用已启用的来源注册表');
    }
    this.assertSourceUrl(source.url, dto.sourceUrl);
    return this.prisma.newsItem.upsert({
      where: { sourceUrl: dto.sourceUrl },
      create: {
        sourceId: source.id,
        // Worker only creates a private editorial draft. English source text
        // may temporarily occupy these fields, but cannot reach the public API
        // until an editor rewrites and publishes it.
        titleZh: dto.sourceTitle.trim(),
        summaryZh: dto.sourceExcerpt.trim(),
        sourceTitle: dto.sourceTitle.trim(),
        sourceUrl: dto.sourceUrl,
        tags: this.cleanTags(dto.tags),
        publishedAt: new Date(dto.publishedAt),
        isPublished: false,
      },
      update: {
        publishedAt: new Date(dto.publishedAt),
      },
      include: { source: true },
    });
  }

  async reportSourceCheck(dto: SourceCheckDto) {
    const checkedAt = new Date(dto.checkedAt);
    const source = await this.prisma.source.upsert({
      where: { url: dto.sourceUrl },
      create: {
        url: dto.sourceUrl,
        name: dto.sourceName,
        jurisdiction: dto.jurisdiction,
        sourceType: 'official',
        enabled: true,
        licenseNote: 'Created from the approved worker registry; complete page-level review before publishing.',
      },
      update: { name: dto.sourceName, jurisdiction: dto.jurisdiction },
    });

    if (dto.status === 'SUCCESS' && (!dto.contentHash || !dto.snapshotKey)) {
      throw new BadRequestException('成功抓取必须提供证据指纹与快照键');
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.source.update({
        where: { id: source.id },
        data: {
          lastCheckedAt: checkedAt,
          ...(dto.status === 'ERROR'
            ? { lastFailureAt: checkedAt, lastFailureCode: dto.errorCode ?? 'UNKNOWN' }
            : { lastSuccessAt: checkedAt, lastFailureCode: null }),
        },
      });
      if (dto.status === 'SUCCESS') {
        await tx.pageSnapshot.upsert({
          where: {
            sourceId_contentHash: { sourceId: source.id, contentHash: dto.contentHash! },
          },
          create: {
            sourceId: source.id,
            contentHash: dto.contentHash!,
            snapshotKey: dto.snapshotKey!,
            httpStatus: dto.httpStatus ?? 200,
            etag: dto.etag,
            lastModified: dto.lastModified,
            fetchedAt: checkedAt,
          },
          update: {
            httpStatus: dto.httpStatus ?? 200,
            etag: dto.etag,
            lastModified: dto.lastModified,
            fetchedAt: checkedAt,
          },
        });
      }
    });
    return { accepted: true, sourceId: source.id, status: dto.status };
  }

  async review(id: string, dto: ReviewChangeDto) {
    if (dto.status === ReviewStatus.PENDING) {
      throw new BadRequestException('审核操作不能把条目退回自动待审核状态');
    }
    if (
      (dto.status === ReviewStatus.VERIFIED || dto.status === ReviewStatus.CORRECTED) &&
      !dto.editorSummaryZh?.trim()
    ) {
      throw new BadRequestException('发布前必须填写中文编辑摘要');
    }
    if (dto.status === ReviewStatus.CORRECTED && !dto.correctionNote?.trim()) {
      throw new BadRequestException('更正必须填写更正说明');
    }
    const current = await this.prisma.changeLog.findUnique({
      where: { id },
      include: { source: { select: { jurisdiction: true } } },
    });
    if (!current) throw new NotFoundException('未找到变化记录');
    return this.prisma.$transaction(async (tx) => {
      const reviewed = await tx.changeLog.update({
        where: { id },
        data: {
          reviewStatus: dto.status,
          editorSummaryZh: dto.editorSummaryZh?.trim(),
          correctionNote: dto.correctionNote?.trim(),
          verifiedAt: new Date(),
          publishedAt:
            dto.status === ReviewStatus.VERIFIED || dto.status === ReviewStatus.CORRECTED
              ? new Date()
              : null,
        },
      });
      const publishStatus =
        dto.status === ReviewStatus.CORRECTED
          ? 'CHANGE_CORRECTED'
          : dto.status === ReviewStatus.VERIFIED
            ? 'CHANGE_VERIFIED'
            : null;
      if (publishStatus && current.reviewStatus !== dto.status) {
        const preferences = await tx.notificationPreference.findMany({
          where: { policyUpdates: true },
          select: {
            accountId: true,
            jurisdictions: true,
            tags: true,
            importantOnly: true,
          },
        });
        const recipients = preferences.filter((preference) => {
          if (
            preference.importantOnly &&
            current.importance === ChangeImportance.GENERAL
          ) {
            return false;
          }
          const jurisdictionMatches = preference.jurisdictions.includes(
            current.source.jurisdiction,
          );
          const tagMatches =
            preference.tags.length === 0 ||
            preference.tags.some((tag) => current.tags.includes(tag));
          return jurisdictionMatches && tagMatches;
        });
        if (recipients.length > 0) {
          await tx.notificationOutbox.createMany({
            data: recipients.map((preference) => ({
              accountId: preference.accountId,
              kind: publishStatus,
              entityId: current.id,
              payload: NotificationsService.notificationPayload(current.id),
              dedupeKey: `${current.id}:${publishStatus}:${preference.accountId}`,
            })),
            skipDuplicates: true,
          });
        }
      }
      return reviewed;
    });
  }

  private async requireSource(id: string) {
    const source = await this.prisma.source.findUnique({ where: { id } });
    if (!source) throw new NotFoundException('未找到来源');
    return source;
  }

  private assertSourceUrl(sourceUrl: string, articleUrl: string) {
    if (new URL(sourceUrl).hostname.toLowerCase() !== new URL(articleUrl).hostname.toLowerCase()) {
      throw new BadRequestException('新闻原文必须与已批准来源使用同一主机');
    }
  }

  private cleanTags(tags: string[]) {
    return [...new Set(tags.map((tag) => tag.trim()).filter(Boolean))].slice(0, 20);
  }

  private assertChineseEditorialCopy(title: string, summary: string) {
    const containsChinese = /[\u3400-\u9fff]/;
    if (!containsChinese.test(title) || !containsChinese.test(summary)) {
      throw new BadRequestException('发布前必须由编辑填写中文原创标题和摘要');
    }
  }
}
