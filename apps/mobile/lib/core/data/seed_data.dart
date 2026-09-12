import '../models/models.dart';

abstract final class SeedData {
  static final news = <NewsItem>[
    NewsItem(
      id: 'sa-tsmit-2026',
      title: '南澳更新临时技术移民收入门槛说明',
      summary: '南澳官方页面说明，自 2026 年 7 月 1 日起，相关收入门槛调整为 A\$79,423。请按个人签证类别回到联邦与南澳官方页面核对。',
      sourceName: 'Move to South Australia',
      jurisdiction: 'AU-SA',
      summaryEn: null,
      sourceTitle: 'Temporary Skilled Migration Income Threshold increase',
      sourceUrl: 'https://migration.sa.gov.au/news/tsmit-increase',
      publishedAt: DateTime(2026, 7, 2),
      sourceType: NewsSourceType.official,
      tags: const ['SA', '482', 'DAMA'],
    ),
    NewsItem(
      id: 'sa-allocations-2025',
      title: '2025–26 南澳州担保名额公布',
      summary: '南澳官方公布 190 与 491 的州担保名额，并说明境内申请人与境外申请人的不同表达意向流程。',
      sourceName: 'Move to South Australia',
      jurisdiction: 'AU-SA',
      summaryEn: null,
      sourceTitle: "More than 2,000 places available for South Australia's 2025-2026 allocations",
      sourceUrl: 'https://migration.sa.gov.au/news/more-than-2000-places-available-for-south-australias-2025-2026-allocations',
      publishedAt: DateTime(2025, 11, 24),
      sourceType: NewsSourceType.official,
      tags: const ['SA', '190', '491'],
    ),
    NewsItem(
      id: 'sa-documents',
      title: '准备州担保材料前，先核对官方文件清单',
      summary: '材料要求会因申请路径而不同。应用内清单只是整理起点，不替代邀请函、官方页面或注册移民代理的个案意见。',
      sourceName: '产品编辑',
      jurisdiction: 'AU-SA',
      summaryEn: null,
      sourceUrl: 'https://migration.sa.gov.au/how-to-apply/documents-required',
      publishedAt: DateTime(2026, 8, 26),
      sourceType: NewsSourceType.editorial,
      tags: const ['SA', '材料', '190', '491'],
    ),
  ];

  static final changes = <PolicyChange>[
    PolicyChange(
      id: 'change-income-threshold',
      pageTitle: 'Temporary Skilled Migration Income Threshold',
      pageTitleEn: 'Temporary Skilled Migration Income Threshold',
      sourceUrl: 'https://migration.sa.gov.au/news/tsmit-increase',
      discoveredAt: DateTime(2026, 7, 2, 9, 42),
      summary: '官方页面新增了 2026 年 7 月 1 日起适用的收入门槛说明。此记录展示页面证据，不判断个人是否满足要求。',
      summaryEn: 'The official page added the income threshold that applies from 1 July 2026. This record presents page evidence and does not assess individual eligibility.',
      beforeText: '页面未包含 2026–27 财年的最新门槛数值。',
      afterText: 'From 1 July 2026, the TSMIT and CSIT increased to \$79,423.',
      severity: ChangeSeverity.important,
      verification: VerificationStatus.verified,
      tags: const ['SA', '482', 'DAMA'],
    ),
    PolicyChange(
      id: 'change-doc-checklist',
      pageTitle: 'Documents required',
      sourceUrl: 'https://migration.sa.gov.au/how-to-apply/documents-required',
      discoveredAt: DateTime(2026, 8, 26, 14, 10),
      summary: '这条示例记录尚未通过内容核对，因此不会出现在面向用户的政策变更中。',
      beforeText:
          'The previous official wording was not captured with enough context.',
      afterText:
          'The updated wording is awaiting a complete, contextual comparison.',
      severity: ChangeSeverity.general,
      verification: VerificationStatus.pendingReview,
      tags: const ['SA', '190', '491', '材料'],
    ),
  ];

  static List<ChecklistItem> templateFor(String visaType) {
    if (visaType == '空白项目') return [];
    return const [
      ChecklistItem(
        id: 'identity-passport',
        title: 'Passport & identity',
        owner: '主申请人',
        category: '身份',
        status: ChecklistStatus.notStarted,
      ),
      ChecklistItem(
        id: 'employment-evidence',
        title: 'Employment & income evidence',
        owner: '主申请人',
        category: '工作',
        status: ChecklistStatus.notStarted,
      ),
    ];
  }
}
