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

describe('ContentService monitoring coverage', () => {
  const now = Date.now();
  const recent = new Date(now - 60_000);

  function serviceWith(sources: any[], pendingReview = 0) {
    const prisma = {
      source: { findMany: jest.fn().mockResolvedValue(sources) },
      changeLog: { count: jest.fn().mockResolvedValue(pendingReview) },
    } as any;
    return new ContentService(prisma);
  }

  it('reports a partly-down jurisdiction as partly down, not as unmonitored', async () => {
    // 内政部三个页面在边缘被 403 拦下，联邦法规两个页面正常。如果只回一句
    // 「联邦不可用」，App 会告诉用户我们看不见联邦法规的变动——正好说反。
    const service = serviceWith([
      { name: 'SA news', jurisdiction: 'AU-SA', enabled: true, lastSuccessAt: recent, lastFailureAt: null },
      { name: 'Home Affairs 190', jurisdiction: 'AU-FED', enabled: false, lastSuccessAt: null, lastFailureAt: null },
      { name: 'Migration Act 1958', jurisdiction: 'AU-FED', enabled: true, lastSuccessAt: recent, lastFailureAt: null },
    ]);

    const status = await service.monitoringStatus();
    const federal = status.jurisdictions.find((entry) => entry.jurisdiction === 'AU-FED');

    expect(federal).toEqual({ jurisdiction: 'AU-FED', monitoredCount: 1, unavailableCount: 1 });
    expect(status.monitoredCount).toBe(2);
    expect(status.unavailableCount).toBe(1);
  });

  it('treats a source whose last run failed as unavailable', async () => {
    const service = serviceWith([
      {
        name: 'SA news',
        jurisdiction: 'AU-SA',
        enabled: true,
        lastSuccessAt: new Date(now - 120_000),
        lastFailureAt: new Date(now - 60_000),
      },
    ]);

    const status = await service.monitoringStatus();
    expect(status.monitoredCount).toBe(0);
    expect(status.jurisdictions).toEqual([
      { jurisdiction: 'AU-SA', monitoredCount: 0, unavailableCount: 1 },
    ]);
  });

  it('treats a stale success as unavailable so silence is never read as "no change"', async () => {
    const intervalSeconds = Number(process.env.CRAWLER_INTERVAL_SECONDS ?? 21_600);
    const service = serviceWith([
      {
        name: 'SA news',
        jurisdiction: 'AU-SA',
        enabled: true,
        lastSuccessAt: new Date(now - intervalSeconds * 4 * 1000),
        lastFailureAt: null,
      },
    ]);

    const status = await service.monitoringStatus();
    expect(status.unavailableCount).toBe(1);
    expect(status.unavailableJurisdictions).toEqual(['AU-SA']);
  });

  it('reports no gap when every source is fresh', async () => {
    const service = serviceWith([
      { name: 'SA news', jurisdiction: 'AU-SA', enabled: true, lastSuccessAt: recent, lastFailureAt: null },
      { name: 'Migration Act 1958', jurisdiction: 'AU-FED', enabled: true, lastSuccessAt: recent, lastFailureAt: null },
    ]);

    const status = await service.monitoringStatus();
    expect(status.unavailableCount).toBe(0);
    expect(status.unavailableJurisdictions).toEqual([]);
    expect(status.lastSuccessAt).toEqual(recent);
  });

  it('surfaces changes held behind human review so an empty list is not read as "nothing changed"', async () => {
    const service = serviceWith(
      [{ name: 'SA news', jurisdiction: 'AU-SA', enabled: true, lastSuccessAt: recent, lastFailureAt: null }],
      6,
    );

    const status = await service.monitoringStatus();
    expect(status.unavailableCount).toBe(0);
    expect(status.pendingReviewCount).toBe(6);
  });
});
