import { BadRequestException, Injectable } from '@nestjs/common';
import { ChangeImportance, ReviewStatus } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { IngestChangeDto, ReviewChangeDto } from './content.dto';

@Injectable()
export class ContentService {
  constructor(private readonly prisma: PrismaService) {}

  news() {
    return this.prisma.newsItem.findMany({
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

    return this.prisma.changeLog.create({
      data: {
        sourceId: source.id,
        titleZh: dto.titleZh,
        oldExcerpt: dto.oldExcerpt,
        newExcerpt: dto.newExcerpt,
        context: dto.context,
        importance: dto.importance,
        discoveredAt: new Date(dto.discoveredAt),
        ...(dto.importance === ChangeImportance.GENERAL
          ? { publishedAt: new Date() }
          : {}),
      },
    });
  }

  async review(id: string, dto: ReviewChangeDto) {
    if (dto.status === ReviewStatus.PENDING) {
      throw new BadRequestException('审核操作不能把条目退回自动待审核状态');
    }
    if (dto.status === ReviewStatus.CORRECTED && !dto.correctionNote) {
      throw new BadRequestException('更正必须填写更正说明');
    }
    return this.prisma.changeLog.update({
      where: { id },
      data: {
        reviewStatus: dto.status,
        editorSummaryZh: dto.editorSummaryZh,
        correctionNote: dto.correctionNote,
        verifiedAt: new Date(),
        publishedAt:
          dto.status === ReviewStatus.VERIFIED || dto.status === ReviewStatus.CORRECTED
            ? new Date()
            : null,
      },
    });
  }
}

