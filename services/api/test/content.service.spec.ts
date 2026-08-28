import { BadRequestException } from '@nestjs/common';
import { ChangeImportance, ReviewStatus } from '@prisma/client';
import { ContentService } from '../src/content/content.service';

describe('ContentService publication guardrails', () => {
  const source = { id: 'source-1' };
  const prisma = {
    source: {
      upsert: jest.fn().mockResolvedValue(source),
    },
    changeLog: {
      upsert: jest.fn().mockImplementation(({ create }) => Promise.resolve(create)),
      update: jest.fn().mockImplementation(({ data }) => Promise.resolve(data)),
      findMany: jest.fn(),
    },
  } as any;
  const service = new ContentService(prisma);

  beforeEach(() => jest.clearAllMocks());

  it('keeps important changes unpublished until a reviewer verifies them', async () => {
    const result = await service.ingest({
      sourceUrl: 'https://migration.sa.gov.au/news',
      sourceName: 'South Australia Migration',
      titleZh: '发现重要变化',
      importance: ChangeImportance.IMPORTANT,
      discoveredAt: '2026-08-27T00:00:00.000Z',
    });

    expect(result.publishedAt).toBeUndefined();
    expect(prisma.changeLog.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ create: expect.objectContaining({ importance: ChangeImportance.IMPORTANT }) }),
    );
  });

  it('allows general changes to appear as pending review', async () => {
    const result = await service.ingest({
      sourceUrl: 'https://migration.sa.gov.au/news',
      sourceName: 'South Australia Migration',
      titleZh: '一般页面变化',
      importance: ChangeImportance.GENERAL,
      discoveredAt: '2026-08-27T00:00:00.000Z',
    });

    expect(result.publishedAt).toBeInstanceOf(Date);
  });

  it('requires an explicit note before publishing a correction', async () => {
    await expect(
      service.review('change-1', { status: ReviewStatus.CORRECTED }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
