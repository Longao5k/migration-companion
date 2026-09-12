import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/app_language.dart';
import '../../core/data/processing_times.dart';
import '../../core/links/official_link.dart';
import '../../core/models/models.dart';
import '../../core/state/app_store.dart';
import '../change_log/change_log_screen.dart';
import '../projects/projects_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({required this.onOpenProjects, super.key});
  final VoidCallback onOpenProjects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStoreProvider);
    final orderedNews = [...state.news]
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    final recent = orderedNews.take(10).toList(growable: false);
    final trackedApplications =
        state.projects.where((project) => project.submittedAt != null).toList()
          ..sort((a, b) => b.submittedAt!.compareTo(a.submittedAt!));
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, '移民资讯', 'Migration updates')),
        actions: [
          IconButton(
            tooltip: tr(context, '搜索全部资讯', 'Search all updates'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NewsCatalogScreen()),
            ),
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: ref.read(appStoreProvider.notifier).refreshContent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            _WelcomeCard(onOpenProjects: onOpenProjects),
            if (trackedApplications.isNotEmpty) ...[
              const SizedBox(height: 18),
              _ApplicationTrackingSection(projects: trackedApplications),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _ShortcutCard(
                    icon: Icons.grid_view_rounded,
                    title: tr(context, '全部资讯', 'Browse all'),
                    subtitle: tr(
                      context,
                      '按州、签证和主题查找',
                      'By state, visa and topic',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NewsCatalogScreen(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ShortcutCard(
                    icon: Icons.difference_outlined,
                    title: tr(context, '政策变更', 'Policy changes'),
                    subtitle: tr(
                      context,
                      '查看核实后的前后对照',
                      'Verified before-and-after',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ChangeLogScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              tr(context, '最新资讯', 'Latest updates'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              tr(
                context,
                '按发布时间展示最近 10 条官方资讯',
                'The 10 newest official updates by publication date',
              ),
            ),
            const SizedBox(height: 12),
            if (state.isContentRefreshing && recent.isEmpty)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (recent.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      const Icon(Icons.event_available_outlined, size: 42),
                      const SizedBox(height: 12),
                      Text(
                        tr(
                          context,
                          '暂时没有可显示的资讯',
                          'No updates are available yet',
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NewsCatalogScreen(),
                          ),
                        ),
                        child: Text(
                          tr(context, '查看全部资讯', 'Browse all updates'),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              for (final item in recent) _NewsCard(item: item),
          ],
        ),
      ),
    );
  }
}

class _ApplicationTrackingSection extends StatelessWidget {
  const _ApplicationTrackingSection({required this.projects});

  final List<VisaProject> projects;

  @override
  Widget build(BuildContext context) {
    final cards = projects
        .map((project) => _ApplicationTrackingCard(project: project))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, '申请进度', 'Application progress'),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (cards.length == 1)
          cards.single
        else
          SizedBox(
            height: 318,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, index) =>
                  SizedBox(width: 290, child: cards[index]),
            ),
          ),
      ],
    );
  }
}

class _ApplicationTrackingCard extends StatelessWidget {
  const _ApplicationTrackingCard({required this.project});

  final VisaProject project;

  @override
  Widget build(BuildContext context) {
    final submittedAt = project.submittedAt!;
    final granted = project.grantedAt != null;
    final end = project.grantedAt ?? DateTime.now();
    final days = end.difference(submittedAt).inDays.clamp(0, 99999);
    final estimate = ProcessingTimes.forVisaType(project.visaType);
    final ratio = estimate?.approximateDays == null
        ? null
        : (days / estimate!.approximateDays!).clamp(0.0, 1.0);
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: granted ? colors.tertiaryContainer : colors.primaryContainer,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProjectDetailScreen(projectId: project.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Icon(granted ? Icons.celebration : Icons.hourglass_top),
                ],
              ),
              const SizedBox(height: 14),
              if (granted) ...[
                Text(
                  tr(context, '已下签', 'Visa granted'),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    context,
                    '从递交到下签共 $days 天',
                    '$days days from lodgement to grant',
                  ),
                ),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$days',
                      style: Theme.of(context).textTheme.displaySmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(width: 7),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(tr(context, '已递交天数', 'days since lodgement')),
                    ),
                  ],
                ),
                if (estimate != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    tr(
                      context,
                      '官方同类中位数：${estimate.displayValue}',
                      'Official category median: ${estimate.displayValue}',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tr(
                      context,
                      '官方更新于 ${estimate.asOf.year} 年 ${estimate.asOf.month} 月',
                      'Official update: ${estimate.asOf.month}/${estimate.asOf.year}',
                    ),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  if (ratio != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: ratio),
                  ],
                  if (estimate.note != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      estimate.note!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ] else
                  Text(
                    tr(
                      context,
                      '查看官方审理时间指南',
                      'Check the official processing guide',
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                tr(
                  context,
                  '审理时间为全球参考，不是个案承诺',
                  'Published times are a guide, not a decision deadline',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (!granted && estimate != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        openOfficialSource(context, estimate.sourceUrl),
                    child: Text(tr(context, '查看官方数据', 'View official data')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.onOpenProjects});
  final VoidCallback onOpenProjects;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        colors: [
          Theme.of(context).colorScheme.primary,
          Theme.of(context).colorScheme.tertiary,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, '重要信息，更容易找到', 'Important updates, easier to find'),
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            context,
            '追踪政策，整理材料，把每个申请放在清晰的路线里。',
            'Follow policy, organise documents and keep each application clear.',
          ),
          style: const TextStyle(color: Colors.white, height: 1.4),
        ),
        const SizedBox(height: 18),
        FilledButton.tonalIcon(
          onPressed: onOpenProjects,
          icon: const Icon(Icons.route),
          label: Text(tr(context, '查看我的申请', 'View my applications')),
        ),
      ],
    ),
  );
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 2,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class NewsCatalogScreen extends ConsumerStatefulWidget {
  const NewsCatalogScreen({super.key});
  @override
  ConsumerState<NewsCatalogScreen> createState() => _NewsCatalogScreenState();
}

class _NewsCatalogScreenState extends ConsumerState<NewsCatalogScreen> {
  final _search = TextEditingController();
  String? _visa;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStoreProvider);
    final zh = isChineseUi(context);
    final query = _search.text.trim().toLowerCase();
    final visaTags = <String>{
      for (final item in state.news)
        for (final tag in item.tags)
          if (RegExp(r'^(?:\d{3})(?:/\d{3})?$').hasMatch(tag)) tag,
    }.toList()..sort();
    final filtered = state.news.where((item) {
      final text =
          '${item.title} ${item.titleEn ?? ''} ${item.summary} ${item.summaryEn ?? ''} ${item.tags.join(' ')}'
              .toLowerCase();
      return (query.isEmpty || text.contains(query)) &&
          (_visa == null || item.tags.contains(_visa));
    }).toList()..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    final grouped = <String, List<NewsItem>>{};
    for (final item in filtered) {
      grouped.putIfAbsent(item.jurisdiction, () => []).add(item);
    }
    const order = [
      'AU-FED',
      'AU-ACT',
      'AU-NSW',
      'AU-NT',
      'AU-QLD',
      'AU-SA',
      'AU-TAS',
      'AU-VIC',
      'AU-WA',
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, '全部资讯', 'All updates'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          SearchBar(
            controller: _search,
            hintText: tr(
              context,
              '搜索政策、签证或关键词',
              'Search policy, visa or keywords',
            ),
            leading: const Icon(Icons.search),
            onChanged: (_) => setState(() {}),
          ),
          if (visaTags.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ChoiceChip(
                    label: Text(tr(context, '全部签证', 'All visas')),
                    selected: _visa == null,
                    onSelected: (_) => setState(() => _visa = null),
                  ),
                  const SizedBox(width: 8),
                  for (final tag in visaTags) ...[
                    ChoiceChip(
                      label: Text(localizedTagLabel(context, tag)),
                      selected: _visa == tag,
                      onSelected: (_) => setState(() => _visa = tag),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          for (final jurisdiction in order)
            if (grouped[jurisdiction]?.isNotEmpty == true)
              ExpansionTile(
                initiallyExpanded:
                    jurisdiction == 'AU-FED' || jurisdiction == 'AU-SA',
                title: Text(
                  jurisdictionLabel(jurisdiction, zh: zh),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  zh
                      ? '${grouped[jurisdiction]!.length} 条资讯'
                      : '${grouped[jurisdiction]!.length} updates',
                ),
                children: [
                  for (final item in grouped[jurisdiction]!)
                    _NewsCard(item: item),
                ],
              ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(tr(context, '没有找到匹配的资讯', 'No matching updates')),
              ),
            ),
        ],
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item});
  final NewsItem item;
  @override
  Widget build(BuildContext context) {
    final zh = isChineseUi(context);
    final title = zh
        ? item.title
        : (item.titleEn ?? item.sourceTitle ?? 'Official migration update');
    final summary = zh
        ? item.summary
        : (item.summaryEn ??
              'Open the official source to read the full update.');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => NewsDetailScreen(item: item))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    jurisdictionLabel(item.jurisdiction, zh: zh),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('d MMM').format(item.publishedAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(summary, maxLines: 3, overflow: TextOverflow.ellipsis),
              if (item.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: item.tags
                      .take(4)
                      .map(
                        (tag) => Chip(
                          label: Text(localizedTagLabel(context, tag)),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class NewsDetailScreen extends StatelessWidget {
  const NewsDetailScreen({required this.item, super.key});
  final NewsItem item;
  @override
  Widget build(BuildContext context) {
    final zh = isChineseUi(context);
    final enTitle =
        item.titleEn ?? item.sourceTitle ?? 'Official migration update';
    final enSummary =
        item.summaryEn ?? 'Open the official source to read the full update.';
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, '资讯详情', 'Update'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(
            zh ? item.title : enTitle,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            '${item.sourceName} · ${DateFormat.yMMMd().format(item.publishedAt)}',
          ),
          const SizedBox(height: 22),
          if (zh) ...[
            Text('中文摘要', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(item.summary),
            const SizedBox(height: 24),
            Text(
              'English summary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(enSummary),
          ] else ...[
            Text('Summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(enSummary),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: item.tags
                .map(
                  (tag) => Chip(label: Text(localizedTagLabel(context, tag))),
                )
                .toList(),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => openOfficialSource(context, item.sourceUrl),
            icon: const Icon(Icons.open_in_new),
            label: Text(tr(context, '查看官方原文', 'View official source')),
          ),
        ],
      ),
    );
  }
}
