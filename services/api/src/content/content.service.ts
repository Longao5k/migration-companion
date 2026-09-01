import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import {
  ChangeImportance,
  EditorialReviewStatus,
  Prisma,
  ReviewStatus,
} from '@prisma/client';
import { createHash } from 'node:crypto';
import { assertExcerptQuota } from './excerpt-quota';
import { JURISDICTIONS, isKnownTag, TOPICS, VISA_SUBCLASSES } from './taxonomy';
import { matchesPreference, NotifiableItem } from './subscriber-match';
import { PrismaService } from '../prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import {
  CreateNewsDto,
  CreateSourceDto,
  AutomatedEditorialReviewDto,
  IngestChangeDto,
  IngestNewsDto,
  ReviewChangeDto,
  SourceCheckDto,
  UpdateNewsDto,
  UpdateSourceDto,
} from './content.dto';

const AUTOMATION_HIGH_RISK_TAGS = new Set([
  '法规',
  '提名条件',
  '申请材料',
  '职业清单',
  '打分规则',
  '英语要求',
  '费用',
  '项目开关',
  '名额',
  'ROI',
  'DAMA',
  '薪资门槛',
  '职业评估',
]);

const ACTION_CHANGING_COPY =
  /(?:eligib|requirements?|must\b|deadline|applications?\s+(?:close|open)|program\s+(?:close|open)|allocation|quota|fees?|threshold|exemption|nomination criteria|visa conditions?|有资格|资格|必须|截止|申请.{0,8}(?:关闭|开放)|项目.{0,8}(?:关闭|开放)|名额|费用|门槛|豁免|提名条件)/i;
const ADVICE_COPY =
  /(?:you should|we recommend|you may be eligible|you may qualify|你应该|建议你|建议申请|可能有资格|我们建议)/i;
const MATERIAL_NUMBER = /\d{1,3}(?:,\d{3})+|\d{4,}/g;

@Injectable()
export class ContentService {
  constructor(private readonly prisma: PrismaService) {}

  news() {
    return this.prisma.newsItem.findMany({
      where: { isPublished: true, publishedAt: { lte: new Date() } },
      // 必须下发 jurisdiction：App 的州筛选原先只能靠匹配标签和来源名里的子串，
      // 「南澳」曾经匹配到全部条目（标签写死），「联邦」匹配到零条。
      include: {
        source: { select: { name: true, sourceType: true, jurisdiction: true } },
      },
      orderBy: { publishedAt: 'desc' },
      take: 100,
    });
  }

  /**
   * 监控状态。变更列表为空有两种完全不同的含义：
   * 「已在监控，确实没有变化」和「根本没在监控」。
   * 对一个移民产品，把后者显示成前者等于告诉用户「政策没变」——必须区分。
   *
   * 只下发聚合信息与官方页面名称，不下发失败细节与内部标识。
   */
  async monitoringStatus() {
    // 已发现但还压在人工复核里的改动。列表为空其实有第三种含义：
    // 「发现了，但重要变更在核实前不发布」。不说出来，用户看到的仍是「没有变化」。
    const pendingReviewCount = await this.prisma.changeLog.count({
      where: {
        reviewStatus: ReviewStatus.PENDING,
        importance: { in: [ChangeImportance.IMPORTANT, ChangeImportance.MAJOR] },
      },
    });

    const sources = await this.prisma.source.findMany({
      where: { sourceType: 'official' },
      select: {
        name: true,
        jurisdiction: true,
        enabled: true,
        lastSuccessAt: true,
        lastFailureAt: true,
      },
    });

    // 连续三个抓取周期没有成功即视为过期，默认周期 6 小时。
    const intervalSeconds = Number(process.env.CRAWLER_INTERVAL_SECONDS ?? 21_600);
    const staleBefore = new Date(Date.now() - intervalSeconds * 3 * 1000);

    const unavailable = sources.filter((source) => {
      if (!source.enabled) return true;
      if (!source.lastSuccessAt) return true;
      if (source.lastFailureAt && source.lastFailureAt > source.lastSuccessAt) return true;
      return source.lastSuccessAt < staleBefore;
    });

    const monitored = sources.filter((source) => !unavailable.includes(source));
    const lastSuccessAt = monitored
      .map((source) => source.lastSuccessAt)
      .filter((value): value is Date => value !== null)
      .sort((a, b) => b.getTime() - a.getTime())[0];

    // 按辖区分别统计。只给一个「联邦不可用」的列表会说反话：内政部的三个页面
    // 确实抓不到（边缘 403），但联邦法规（Migration Act / Regulations）一直在监控。
    // 告诉用户「联邦页面监控不到」，会让人以为法规变动我们也看不见。
    const jurisdictions = [...new Set(sources.map((source) => source.jurisdiction))]
      .sort()
      .map((jurisdiction) => ({
        jurisdiction,
        monitoredCount: monitored.filter((source) => source.jurisdiction === jurisdiction)
          .length,
        unavailableCount: unavailable.filter(
          (source) => source.jurisdiction === jurisdiction,
        ).length,
      }));

    return {
      monitoredCount: monitored.length,
      unavailableCount: unavailable.length,
      pendingReviewCount,
      jurisdictions,
      // 保留给旧版本 App：它只认这个字段。新版本读 jurisdictions。
      unavailableJurisdictions: jurisdictions
        .filter((entry) => entry.unavailableCount > 0)
        .map((entry) => entry.jurisdiction),
      unavailableSources: unavailable.map((source) => ({
        name: source.name,
        jurisdiction: source.jurisdiction,
      })),
      lastSuccessAt: lastSuccessAt ?? null,
    };
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
      // 按 updatedAt 排序会让刚保存的那一条跳到列表第一位，下面所有条目整体上移，
      // 审到第 40 条时已经不知道审到哪了。改成稳定排序：草稿在前，内部按发布日期。
      orderBy: [{ isPublished: 'asc' }, { publishedAt: 'desc' }],
      take: 500,
    });
  }

  /** Private queue consumed by the editorial worker, never by the public App. */
  editorialQueue() {
    return this.prisma.newsItem.findMany({
      where: {
        sourceExcerpt: { not: null },
        OR: [
          // 旧版种子内容中有少量条目已经发布，但从未经过新的独立复核。
          // 状态才是审核事实；不能因为它们恰好在线就永久绕过安全闸门。
          { editorialReviewStatus: EditorialReviewStatus.PENDING },
          {
            // 没有命中政策风险、只因模型分歧进入人工队列的稿子，带着上一轮
            // findings 自动重写一次。次数持久化，避免定时任务无限烧额度。
            editorialReviewStatus: EditorialReviewStatus.HUMAN_REQUIRED,
            editorialRiskReasons: { isEmpty: true },
            editorialRevisionCount: { lt: 1 },
          },
        ],
      },
      include: { source: true },
      orderBy: { publishedAt: 'desc' },
      take: 100,
    });
  }

  /**
   * Persist an independently reviewed model draft and publish it only when the
   * server's own policy classifies it as low-risk.
   */
  async applyAutomatedEditorialReview(id: string, dto: AutomatedEditorialReviewDto) {
    const current = await this.prisma.newsItem.findUnique({
      where: { id },
      include: { source: true },
    });
    if (!current) throw new NotFoundException('未找到新闻');
    if (!current.source.enabled || current.source.sourceType !== 'official') {
      throw new BadRequestException('自动审核只接受已启用的官方来源');
    }
    if (!current.sourceExcerpt?.trim()) {
      throw new BadRequestException('没有官方原文摘录，不能自动审核');
    }
    const currentDigest = createHash('sha256')
      .update(`${current.sourceTitle}\n${current.sourceExcerpt}`)
      .digest('hex');
    if (dto.sourceDigest !== currentDigest) {
      throw new BadRequestException('官方原文已在审核期间更新，请重新起草和复核');
    }
    if (dto.draftModel.trim() === dto.reviewModel.trim()) {
      throw new BadRequestException('起草和独立复核必须使用不同模型');
    }
    if (dto.blockingFindings.some((finding) => !dto.findings.includes(finding))) {
      throw new BadRequestException('阻断项必须同时保存在完整复核结果中');
    }

    this.assertChineseEditorialCopy(dto.titleZh, dto.summaryZh);
    this.assertAutomatedCopy(
      current.sourceTitle,
      current.sourceExcerpt,
      current.publishedAt,
      dto,
    );

    const referenceReasons = this.referenceOnlyReasons(current);
    const referenceOnly = referenceReasons.length > 0;
    const riskReasons = referenceOnly ? [] : this.automationRiskReasons(current, dto);
    const needsHuman = !referenceOnly &&
      (dto.blockingFindings.length > 0 || riskReasons.length > 0);
    const reviewStatus = referenceOnly
      ? EditorialReviewStatus.REFERENCE_ONLY
      : needsHuman
        ? EditorialReviewStatus.HUMAN_REQUIRED
        : EditorialReviewStatus.AUTO_APPROVED;
    const isAutomaticRevision =
      current.editorialReviewStatus === EditorialReviewStatus.HUMAN_REQUIRED &&
      current.editorialRiskReasons.length === 0 &&
      current.editorialRevisionCount < 1;
    const reviewedAt = new Date();
    const checks = [
      ...dto.checks,
      ...dto.findings.map((finding) => `⚠ 自动复核：${finding}`),
      ...(referenceOnly
        ? referenceReasons.map((reason) => `参考资料：${reason}`)
        : riskReasons.length > 0
        ? riskReasons.map((reason) => `⚠ 人工队列：${reason}`)
        : [`自动复核通过：${dto.reviewRuns} 轮独立核对未发现阻断项`]),
    ].filter((value, index, all) => all.indexOf(value) === index);

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.newsItem.update({
        where: { id },
        data: {
          titleZh: dto.titleZh.trim(),
          summaryZh: dto.summaryZh.trim(),
          titleEn: dto.titleEn.trim(),
          summaryEn: dto.summaryEn.trim(),
          draftAuthor: needsHuman ? 'model' : 'automation',
          draftModel: dto.draftModel,
          draftedAt: reviewedAt,
          draftChecks: checks,
          editorialReviewStatus: reviewStatus,
          editorialReviewModel: dto.reviewModel,
          editorialReviewedAt: reviewedAt,
          editorialReviewRuns: dto.reviewRuns,
          editorialFindings: dto.findings,
          editorialRiskReasons: referenceOnly ? referenceReasons : riskReasons,
          editorialRevisionCount: isAutomaticRevision
            ? current.editorialRevisionCount + 1
            : current.editorialRevisionCount,
          isPublished: reviewStatus === EditorialReviewStatus.AUTO_APPROVED,
        },
        include: { source: true },
      });

      await tx.auditEvent.create({
        data: {
          action: referenceOnly
            ? 'CONTENT_REFERENCE_ONLY'
            : needsHuman
              ? 'CONTENT_HUMAN_REVIEW_REQUIRED'
              : 'CONTENT_AUTO_PUBLISHED',
          targetType: 'NewsItem',
          targetId: id,
          safeMetadata: {
            reviewModel: dto.reviewModel,
            reviewRuns: dto.reviewRuns,
            findingCount: dto.findings.length,
            blockingFindingCount: dto.blockingFindings.length,
            riskReasons: referenceOnly ? referenceReasons : riskReasons,
            automaticRevision: isAutomaticRevision,
          },
        },
      });
      if (reviewStatus === EditorialReviewStatus.AUTO_APPROVED && !current.isPublished) {
        await this.fanOutNewsPublished(tx, updated);
      }
      return updated;
    });
  }

  async createNews(dto: CreateNewsDto) {
    const source = await this.requireSource(dto.sourceId);
    this.assertSourceUrl(source.url, dto.sourceUrl);
    if (dto.isPublished) this.assertChineseEditorialCopy(dto.titleZh, dto.summaryZh);

    return this.prisma.$transaction(async (tx) => {
      const created = await tx.newsItem.create({
        data: {
          sourceId: source.id,
          titleZh: dto.titleZh.trim(),
          summaryZh: dto.summaryZh.trim(),
          sourceTitle: dto.sourceTitle.trim(),
          sourceUrl: dto.sourceUrl,
          tags: this.cleanTags(dto.tags),
          publishedAt: new Date(dto.publishedAt),
          isPublished: dto.isPublished ?? false,
          draftAuthor: 'editor',
          editorialReviewStatus: EditorialReviewStatus.HUMAN_APPROVED,
          editorialReviewedAt: new Date(),
        },
        include: { source: true },
      });

      // 后台「保存后立即发布」走的是这条路径，而它原先一行通知代码都没有：
      // 同一个界面上两个发布按钮，只有「草稿→发布」那个会通知订阅者。
      if (created.isPublished) {
        await this.fanOutNewsPublished(tx, created);
      }
      return created;
    });
  }

  /** 资讯发布时按订阅扇出。两条发布路径共用，避免其中一条再次漏掉。 */
  private async fanOutNewsPublished(
    tx: Prisma.TransactionClient,
    item: { id: string; tags: string[]; source: { jurisdiction: string } },
  ) {
    const recipients = await this.matchSubscribers(tx, {
      kind: 'news',
      jurisdiction: item.source.jurisdiction,
      tags: item.tags,
    });
    if (recipients.length === 0) return;
    await tx.notificationOutbox.createMany({
      data: recipients.map((preference) => ({
        accountId: preference.accountId,
        kind: 'NEWS_PUBLISHED',
        entityId: item.id,
        payload: NotificationsService.newsPayload(item.id, item.source.jurisdiction),
        dedupeKey: `${item.id}:NEWS_PUBLISHED:${preference.accountId}`,
      })),
      skipDuplicates: true,
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
      this.assertHumanReviewed(
        dto.draftAuthor ?? current.draftAuthor,
        current.sourceExcerpt,
        dto.draftAuthor === 'editor'
          ? EditorialReviewStatus.HUMAN_APPROVED
          : current.editorialReviewStatus,
      );
    }
    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.newsItem.update({
        where: { id },
        data: {
          ...(dto.titleZh !== undefined ? { titleZh: dto.titleZh.trim() } : {}),
          ...(dto.summaryZh !== undefined ? { summaryZh: dto.summaryZh.trim() } : {}),
          ...(dto.sourceTitle !== undefined ? { sourceTitle: dto.sourceTitle.trim() } : {}),
          ...(dto.sourceUrl !== undefined ? { sourceUrl: dto.sourceUrl } : {}),
          ...(dto.tags !== undefined ? { tags: this.cleanTags(dto.tags) } : {}),
          ...(dto.publishedAt !== undefined ? { publishedAt: new Date(dto.publishedAt) } : {}),
          ...(dto.isPublished !== undefined ? { isPublished: dto.isPublished } : {}),
          ...(dto.draftAuthor !== undefined ? { draftAuthor: dto.draftAuthor } : {}),
          ...(dto.draftAuthor === 'editor'
            ? {
                editorialReviewStatus: EditorialReviewStatus.HUMAN_APPROVED,
                editorialReviewedAt: new Date(),
              }
            : {}),
          ...(dto.draftModel !== undefined ? { draftModel: dto.draftModel } : {}),
          ...(dto.draftedAt !== undefined ? { draftedAt: new Date(dto.draftedAt) } : {}),
          ...(dto.draftChecks !== undefined ? { draftChecks: dto.draftChecks } : {}),
          ...(dto.titleEn !== undefined ? { titleEn: dto.titleEn.trim() } : {}),
          ...(dto.summaryEn !== undefined ? { summaryEn: dto.summaryEn.trim() } : {}),
        },
        include: { source: true },
      });

      // 只在「草稿 → 已发布」这一次跳变时通知。改个错别字再保存不该再发一遍，
      // 撤下再重新发布也不该——dedupeKey 会挡住，但先判断跳变更省事。
      if (dto.isPublished === true && !current.isPublished) {
        await this.fanOutNewsPublished(tx, updated);

      }
      return updated;
    });
  }

  /**
   * 按订阅偏好筛出该收到这条内容的账号。
   *
   * 辖区必须命中；标签为空表示「该辖区的都要」，否则要有交集。
   *
   * `importantOnly` **只作用于政策变更的重要度**，不作用于资讯。原先资讯也走这个
   * 判断并固定传 `isImportant: false`，而这个偏好默认为 true——结果是
   * **每一个默认设置的用户都收不到任何资讯提醒**，「按兴趣订阅」在默认路径上等于没做。
   *
   * 用户勾「只要重要的」表达的是「变更里只要重要的那些」，不是「不要资讯」。
   */
  private async matchSubscribers(tx: Prisma.TransactionClient, item: NotifiableItem) {
    const preferences = await tx.notificationPreference.findMany({
      where: { policyUpdates: true },
      select: { accountId: true, jurisdictions: true, tags: true, importantOnly: true },
    });
    // 判断规则见 subscriber-match.ts：那里能脱离数据库直接测。
    return preferences.filter((preference) => matchesPreference(item, preference));
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
    // 写入端强制引用配额：DTO 只能挡住单个字段，挡不住合计，也挡不住短页面被整页引用。
    assertExcerptQuota(dto);
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
    const sourceExcerpt = dto.sourceExcerpt.trim();
    const publishedAt = new Date(dto.publishedAt);
    const referenceReasons = this.referenceOnlyReasons({ publishedAt, source });
    const existing = await this.prisma.newsItem.findUnique({
      where: { sourceUrl: dto.sourceUrl },
      select: { sourceExcerpt: true, editorialReviewStatus: true },
    });
    const evidenceChanged =
      existing !== null && (existing.sourceExcerpt ?? '').trim() !== sourceExcerpt;
    return this.prisma.newsItem.upsert({
      where: { sourceUrl: dto.sourceUrl },
      create: {
        sourceId: source.id,
        // 原文进 sourceExcerpt，中文字段留空——不再拿英文占位。
        // 占位的代价是：编辑一写中文，原文就永久消失，审核页再也无法并排比对。
        titleZh: '',
        summaryZh: '',
        sourceTitle: dto.sourceTitle.trim(),
        sourceExcerpt,
        sourceUrl: dto.sourceUrl,
        tags: this.cleanTags(dto.tags),
        publishedAt,
        isPublished: false,
        editorialReviewStatus: referenceReasons.length > 0
          ? EditorialReviewStatus.REFERENCE_ONLY
          : EditorialReviewStatus.PENDING,
        editorialRiskReasons: referenceReasons,
      },
      update: {
        publishedAt,
        // 官方原文可能被修订过，跟着更新；但绝不碰 titleZh/summaryZh——
        // 那是人写的编辑稿，采集器无权覆盖。
        sourceTitle: dto.sourceTitle.trim(),
        sourceExcerpt,
        ...(referenceReasons.length > 0 &&
        (existing?.editorialReviewStatus !== EditorialReviewStatus.HUMAN_APPROVED || evidenceChanged)
          ? {
              isPublished: false,
              editorialReviewStatus: EditorialReviewStatus.REFERENCE_ONLY,
              editorialRiskReasons: referenceReasons,
              ...(evidenceChanged
                ? {
                    editorialReviewModel: null,
                    editorialReviewedAt: null,
                    editorialReviewRuns: null,
                    editorialFindings: Prisma.JsonNull,
                    editorialRevisionCount: 0,
                    draftAuthor: null,
                    draftModel: null,
                    draftedAt: null,
                    draftChecks: [],
                  }
                : {}),
            }
          : evidenceChanged
          ? {
              // 公开原文发生变化后，之前的自动或人工结论都不再对应当前证据。
              // 先撤下并重新进入流水线，不能让过期摘要继续挂在资讯流里。
              isPublished: false,
              editorialReviewStatus: EditorialReviewStatus.PENDING,
              editorialReviewModel: null,
              editorialReviewedAt: null,
              editorialReviewRuns: null,
              editorialFindings: Prisma.JsonNull,
              editorialRiskReasons: [],
              editorialRevisionCount: 0,
              draftAuthor: null,
              draftModel: null,
              draftedAt: null,
              draftChecks: [],
            }
          : {}),
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
        const recipients = await this.matchSubscribers(tx, {
          jurisdiction: current.source.jurisdiction,
          tags: current.tags,
          // 一般变更只发给关掉「只要重要的」的人。
          kind: 'change',
          isImportant: current.importance !== ChangeImportance.GENERAL,
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

  /**
   * 只保留词表内的标签。
   *
   * 原先什么都收，于是同一个概念会有 `SA`、`南澳`、`sa` 三种写法（后台的输入框
   * placeholder 就在教人输 `SA`，而真实值是「南澳」）。用户订阅其中一种就漏掉另外两种。
   * 现在词表外的值直接丢弃——静默接受一个永远匹配不上的标签，比拒绝它更糟。
   */
  private cleanTags(tags: string[] | undefined) {
    return [...new Set((tags ?? []).map((tag) => tag.trim()).filter(isKnownTag))];
  }

  /** 公开的标签目录。App 的筛选栏与订阅选择器都从这里建，不再硬编码。 */
  async taxonomy() {
    const items = await this.prisma.newsItem.findMany({
      where: { isPublished: true, publishedAt: { lte: new Date() } },
      select: { tags: true, source: { select: { jurisdiction: true } } },
    });

    const jurisdictionCounts = new Map<string, number>();
    const tagCounts = new Map<string, number>();
    for (const item of items) {
      const code = item.source.jurisdiction;
      jurisdictionCounts.set(code, (jurisdictionCounts.get(code) ?? 0) + 1);
      for (const tag of item.tags) {
        tagCounts.set(tag, (tagCounts.get(tag) ?? 0) + 1);
      }
    }

    // 只列出实际有内容的值。列出零条的辖区会让用户订阅一个永远不会响的东西。
    return {
      jurisdictions: Object.entries(JURISDICTIONS)
        .filter(([code]) => jurisdictionCounts.has(code))
        .map(([code, label]) => ({ code, label, count: jurisdictionCounts.get(code) ?? 0 })),
      visas: VISA_SUBCLASSES.filter((code) => tagCounts.has(code)).map((code) => ({
        code,
        count: tagCounts.get(code) ?? 0,
      })),
      topics: TOPICS.filter((code) => tagCounts.has(code)).map((code) => ({
        code,
        count: tagCounts.get(code) ?? 0,
      })),
    };
  }

  /**
   * 未经有效自动复核的模型稿不能直接发布。
   *
   * 「人工核实后发布」是签核过的规则，但闸门此前只检查「有没有汉字」——
   * 而中英两份都是摘要工具一次跑出来的，全都有汉字。后台的「全选可发布」
   * 因此圈中了 73 条从没有人看过的模型稿，一次点击就能推给所有订阅者。
   * 这个模型编造过数字，也写出过带建议口吻的句子。
   *
   * 自动发布必须带 AUTO_APPROVED；高风险内容仍由编辑保存，标记成 editor。
   *
   * 同时挡住没有原文摘录的：审核靠原文与译稿左右对照，没有原文就没有
   * 可核对的基准，「审过了」无从谈起。
   */
  private assertHumanReviewed(
    draftAuthor: string | null,
    sourceExcerpt: string | null,
    reviewStatus: EditorialReviewStatus = EditorialReviewStatus.PENDING,
  ) {
    if (draftAuthor === 'model') {
      throw new BadRequestException(
        '这条还是模型起草的稿子。请在后台逐字对照官方原文核对并保存后再发布。',
      );
    }
    if (
      draftAuthor === 'automation' &&
      reviewStatus !== EditorialReviewStatus.AUTO_APPROVED
    ) {
      throw new BadRequestException('自动稿没有有效的低风险审核记录，不能发布。');
    }
    // 没有原文摘录的，要求编辑明确保存过一次。
    //
    // 不能一律拦死：手工新增的资讯本来就没有官方摘录，一旦撤下就再也发不出去，
    // 而补摘录是采集器的操作，后台里做不到——那是个死结。
    // 编辑在界面上会看到「这条的数字从未与官方页面比对过」，
    // 保存这一下就是他对此负责的记号。
    if (!sourceExcerpt?.trim() && draftAuthor !== 'editor') {
      throw new BadRequestException(
        '这条没有留存官方原文摘录。请在后台打开官方页面逐项核对并保存后再发布。',
      );
    }
  }

  private assertAutomatedCopy(
    sourceTitle: string,
    sourceExcerpt: string,
    publishedAt: Date,
    dto: AutomatedEditorialReviewDto,
  ) {
    const copy = `${dto.titleZh}\n${dto.summaryZh}\n${dto.titleEn}\n${dto.summaryEn}`;
    if (ADVICE_COPY.test(copy)) {
      throw new BadRequestException('自动稿含建议或个人资格判断');
    }
    // 官方页面常只写月日，完整年份来自采集到的发布日期；它是可信元数据，
    // 因此可以出现在任一语言稿里。年份在中文和英文中的惯用写法也可能不同，
    // 不应与名额、费用、门槛等实质数字使用同一套逐字对称规则。
    const publishedYear = publishedAt.getUTCFullYear().toString();
    const evidence = `${sourceTitle}\n${sourceExcerpt}\n${publishedYear}`.replaceAll(',', '');
    const numbers = copy.match(MATERIAL_NUMBER) ?? [];
    for (const number of numbers) {
      if (!evidence.includes(number.replaceAll(',', ''))) {
        throw new BadRequestException(`自动稿数字 ${number} 在官方摘录中找不到`);
      }
    }
    const zhNumbers = new Set(
      `${dto.titleZh}\n${dto.summaryZh}`.match(MATERIAL_NUMBER)?.map((n) => n.replaceAll(',', '')) ?? [],
    );
    const enNumbers = new Set(
      `${dto.titleEn}\n${dto.summaryEn}`.match(MATERIAL_NUMBER)?.map((n) => n.replaceAll(',', '')) ?? [],
    );
    const knownYears = new Set(evidence.match(/(?:19|20)\d{2}/g) ?? []);
    for (const year of knownYears) {
      zhNumbers.delete(year);
      enNumbers.delete(year);
    }
    if (
      zhNumbers.size !== enNumbers.size ||
      [...zhNumbers].some((number) => !enNumbers.has(number))
    ) {
      throw new BadRequestException('中英文稿的关键数字不一致');
    }
  }

  private automationRiskReasons(
    current: {
      tags: string[];
      publishedAt: Date;
      sourceTitle: string;
      sourceUrl: string;
      source: { name: string };
    },
    dto: AutomatedEditorialReviewDto,
  ) {
    const reasons: string[] = [];
    const riskyTags = current.tags.filter((tag) => AUTOMATION_HIGH_RISK_TAGS.has(tag));
    if (riskyTags.length > 0) reasons.push(`高影响主题：${riskyTags.join('、')}`);
    if (
      current.sourceUrl.includes('legislation.gov.au') ||
      /\b(?:act|regulation|instrument|determination)\b/i.test(current.source.name)
    ) {
      reasons.push('法规解释必须人工确认');
    }
    if (ACTION_CHANGING_COPY.test(`${current.sourceTitle}\n${dto.titleZh}\n${dto.summaryZh}`)) {
      reasons.push('内容可能改变申请资格、期限、费用或项目开放状态');
    }
    return [...new Set(reasons)];
  }

  /**
   * 法规原始记录和旧闻仍保留为可检索证据，但不冒充当前新闻，也不占用人工待办。
   * 人工明确核对并保存后仍可把某条参考资料提升为 HUMAN_APPROVED 再发布。
   */
  private referenceOnlyReasons(current: {
    publishedAt: Date;
    source: { name: string; url: string };
  }) {
    if (
      current.source.url.includes('legislation.gov.au') ||
      /\b(?:act|regulation|instrument|determination)\b/i.test(current.source.name)
    ) {
      return ['法规原始记录：保留用于法规监控，不作为新闻逐条审核'];
    }
    const cutoff = new Date();
    cutoff.setUTCMonth(cutoff.getUTCMonth() - 15);
    if (current.publishedAt < cutoff) {
      return ['历史资料：发布时间超过 15 个月，不进入当前资讯流'];
    }
    return [];
  }

  private assertChineseEditorialCopy(title: string, summary: string) {
    const containsChinese = /[\u3400-\u9fff]/;
    if (!containsChinese.test(title) || !containsChinese.test(summary)) {
      throw new BadRequestException('发布前必须由编辑填写中文原创标题和摘要');
    }
  }
}
