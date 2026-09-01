import { BadRequestException } from '@nestjs/common';
import { ChangeImportance, EditorialReviewStatus, ReviewStatus } from '@prisma/client';
import { createHash } from 'node:crypto';
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

describe('ContentService subscriber matching', () => {
  const service = new ContentService({} as never);
  const match = (service as never as {
    matchSubscribers: (tx: unknown, item: unknown) => Promise<{ accountId: string }[]>;
  }).matchSubscribers.bind(service);

  function tx(preferences: unknown[]) {
    return { notificationPreference: { findMany: jest.fn().mockResolvedValue(preferences) } };
  }

  const defaultPreference = {
    accountId: 'a1',
    jurisdictions: ['AU-SA'],
    tags: [],
    // schema 的默认值就是 true——绝大多数用户从不改这一项。
    importantOnly: true,
  };

  it('delivers news to a default subscriber', async () => {
    // 回归用例：资讯原先也走 importantOnly 判断且固定传 isImportant:false，
    // 于是每一个默认设置的用户都收不到任何资讯。整个功能在默认路径上等于没做。
    const recipients = await match(tx([defaultPreference]), {
      kind: 'news',
      jurisdiction: 'AU-SA',
      tags: ['南澳'],
    });
    expect(recipients).toHaveLength(1);
  });

  it('still holds back unimportant changes from important-only subscribers', async () => {
    // importantOnly 的语义没有被取消，只是限定在变更上。
    const recipients = await match(tx([defaultPreference]), {
      kind: 'change',
      jurisdiction: 'AU-SA',
      tags: ['南澳'],
      isImportant: false,
    });
    expect(recipients).toHaveLength(0);
  });

  it('delivers important changes to important-only subscribers', async () => {
    const recipients = await match(tx([defaultPreference]), {
      kind: 'change',
      jurisdiction: 'AU-SA',
      tags: ['南澳'],
      isImportant: true,
    });
    expect(recipients).toHaveLength(1);
  });

  it('never crosses jurisdictions', async () => {
    // 昆士兰的内容不该发给只订阅了南澳的人。
    const recipients = await match(tx([defaultPreference]), {
      kind: 'news',
      jurisdiction: 'AU-QLD',
      tags: ['昆士兰'],
    });
    expect(recipients).toHaveLength(0);
  });

  it('an empty tag list means everything in that jurisdiction', async () => {
    const recipients = await match(tx([defaultPreference]), {
      kind: 'news',
      jurisdiction: 'AU-SA',
      tags: ['职业清单'],
    });
    expect(recipients).toHaveLength(1);
  });

  it('a tag list filters within the jurisdiction', async () => {
    const picky = { ...defaultPreference, tags: ['491'] };
    expect(
      await match(tx([picky]), { kind: 'news', jurisdiction: 'AU-SA', tags: ['190'] }),
    ).toHaveLength(0);
    expect(
      await match(tx([picky]), { kind: 'news', jurisdiction: 'AU-SA', tags: ['491'] }),
    ).toHaveLength(1);
  });
});

describe('ContentService tag vocabulary', () => {
  const service = new ContentService({} as never);
  const clean = (service as never as {
    cleanTags: (tags?: string[]) => string[];
  }).cleanTags.bind(service);

  it('keeps vocabulary values and drops everything else', () => {
    // 原先什么都收，于是同一个概念有 SA / 南澳 / sa 三种写法，
    // 用户订阅其中一种就漏掉另外两种。
    expect(clean(['190', '职业清单', 'SA', '南澳', '随便写的'])).toEqual(['190', '职业清单']);
  });

  it('drops jurisdiction labels — those are a field, not a tag', () => {
    expect(clean(['南澳', '昆士兰', '联邦'])).toEqual([]);
  });

  it('deduplicates and trims', () => {
    expect(clean([' 190 ', '190', '190'])).toEqual(['190']);
  });

  it('handles no tags at all', () => {
    expect(clean(undefined)).toEqual([]);
  });
});

describe('ContentService automated editorial policy', () => {
  const current = {
    id: 'news-1',
    sourceId: 'source-1',
    sourceTitle: 'Community citizenship ceremony celebrates new Australians',
    sourceExcerpt: 'The ceremony welcomed 120 new Australian citizens in Adelaide.',
    sourceUrl: 'https://minister.homeaffairs.gov.au/news/ceremony',
    tags: ['社区活动'],
    publishedAt: new Date(),
    isPublished: false,
    source: {
      name: 'Minister for Home Affairs media releases',
      enabled: true,
      sourceType: 'official',
      jurisdiction: 'AU-FED',
    },
  };

  function dto(overrides: Record<string, unknown> = {}) {
    return {
      sourceDigest: createHash('sha256')
        .update(`${current.sourceTitle}\n${current.sourceExcerpt}`)
        .digest('hex'),
      titleZh: '阿德莱德举行公民入籍庆祝活动',
      summaryZh: '活动欢迎新加入澳大利亚的公民。',
      titleEn: 'Adelaide hosts citizenship celebration',
      summaryEn: 'The event welcomed new Australian citizens.',
      draftModel: 'qwen-draft',
      reviewModel: 'kimi-review',
      reviewRuns: 3,
      checks: ['数字与官方原文一致'],
      findings: [],
      blockingFindings: [],
      ...overrides,
    };
  }

  function createService(item = current) {
    const tx = {
      newsItem: {
        update: jest.fn().mockImplementation(({ data }) =>
          Promise.resolve({ ...item, ...data }),
        ),
      },
      auditEvent: { create: jest.fn().mockResolvedValue({}) },
      notificationPreference: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const prisma = {
      newsItem: { findUnique: jest.fn().mockResolvedValue(item) },
      $transaction: jest.fn().mockImplementation((callback) => callback(tx)),
    } as any;
    return { service: new ContentService(prisma), tx };
  }

  it('auto-publishes low-risk official news after independent review', async () => {
    const { service, tx } = createService();
    const result = await service.applyAutomatedEditorialReview('news-1', dto());

    expect(result.isPublished).toBe(true);
    expect(result.draftAuthor).toBe('automation');
    expect(result.editorialReviewStatus).toBe(EditorialReviewStatus.AUTO_APPROVED);
    expect(tx.auditEvent.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ action: 'CONTENT_AUTO_PUBLISHED' }),
      }),
    );
  });

  it('routes high-impact subjects to humans without publishing', async () => {
    const { service } = createService({ ...current, tags: ['费用'] });
    const result = await service.applyAutomatedEditorialReview('news-1', dto());

    expect(result.isPublished).toBe(false);
    expect(result.draftAuthor).toBe('model');
    expect(result.editorialReviewStatus).toBe(EditorialReviewStatus.HUMAN_REQUIRED);
    expect(result.editorialRiskReasons).toContain('高影响主题：费用');
  });

  it('routes repeated model disagreements to humans', async () => {
    const { service } = createService();
    const result = await service.applyAutomatedEditorialReview(
      'news-1',
      dto({
        findings: ['[2/3轮][低风险]措辞偏强'],
        blockingFindings: ['[2/3轮][低风险]措辞偏强'],
      }),
    );
    expect(result.editorialReviewStatus).toBe(EditorialReviewStatus.HUMAN_REQUIRED);
    expect(result.isPublished).toBe(false);
  });

  it('rejects blocking findings that are omitted from the audit trail', async () => {
    const { service } = createService();
    await expect(
      service.applyAutomatedEditorialReview(
        'news-1',
        dto({ blockingFindings: ['[3/3轮][高风险]官方原文无法支持结论'] }),
      ),
    ).rejects.toThrow('阻断项必须同时保存在完整复核结果中');
  });

  it('rejects a result created from stale evidence', async () => {
    const { service } = createService();
    await expect(
      service.applyAutomatedEditorialReview('news-1', dto({ sourceDigest: '0'.repeat(64) })),
    ).rejects.toThrow('官方原文已在审核期间更新');
  });

  it('rejects numbers invented by either language draft', async () => {
    const { service } = createService();
    await expect(
      service.applyAutomatedEditorialReview(
        'news-1',
        dto({
          summaryZh: '活动欢迎 9,999 名新公民。',
          summaryEn: 'The event welcomed 9,999 new citizens.',
        }),
      ),
    ).rejects.toThrow('自动稿数字 9,999 在官方摘录中找不到');
  });

  it('allows a trusted publication year to appear in only one language', async () => {
    const publishedAt = new Date('2026-08-20T00:00:00.000Z');
    const { service } = createService({ ...current, publishedAt });
    const result = await service.applyAutomatedEditorialReview(
      'news-1',
      dto({
        titleZh: '2026 年昆士兰举行移民欢迎活动',
        summaryZh: '活动欢迎来自东南亚的商业移民。',
        titleEn: 'Queensland welcomes business migrants',
        summaryEn: 'The event welcomed business migrants from Southeast Asia.',
      }),
    );

    expect(result.editorialReviewStatus).toBe(EditorialReviewStatus.AUTO_APPROVED);
  });

  it('still rejects non-year numbers missing from either language', async () => {
    const item = {
      ...current,
      sourceExcerpt: 'The ceremony welcomed 1,550 new Australian citizens in Adelaide.',
    };
    const { service } = createService(item);
    await expect(
      service.applyAutomatedEditorialReview(
        'news-1',
        dto({
          sourceDigest: createHash('sha256')
            .update(`${item.sourceTitle}\n${item.sourceExcerpt}`)
            .digest('hex'),
          summaryZh: '活动欢迎 1,550 名新公民。',
          summaryEn: 'The event welcomed new citizens.',
        }),
      ),
    ).rejects.toThrow('中英文稿的关键数字不一致');
  });
});
