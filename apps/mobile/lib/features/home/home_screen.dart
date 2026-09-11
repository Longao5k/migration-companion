import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/app_language.dart';
import '../../core/links/official_link.dart';
import '../../core/models/models.dart';
import '../../core/state/app_store.dart';
import '../change_log/change_log_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({required this.onOpenProjects, super.key});
  final VoidCallback onOpenProjects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStoreProvider);
    final zh = isChineseUi(context);
    final orderedNews = [...state.news]
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    final recent = orderedNews.take(10).toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text(zh ? '移民资讯' : 'Migration updates'),
        actions: [
          IconButton(
            tooltip: zh ? '搜索全部资讯' : 'Search all updates',
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
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _ShortcutCard(
                    icon: Icons.grid_view_rounded,
                    title: zh ? '全部资讯' : 'Browse all',
                    subtitle: zh ? '按州、签证和主题查找' : 'By state, visa and topic',
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
                    title: zh ? '政策变更' : 'Policy changes',
                    subtitle: zh ? '查看核实后的前后对照' : 'Verified before-and-after',
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
              zh ? '最新资讯' : 'Latest updates',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              zh
                  ? '按发布时间展示最近 10 条官方资讯'
                  : 'The 10 newest official updates by publication date',
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
                      Text(zh ? '暂时没有可显示的资讯' : 'No updates are available yet'),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NewsCatalogScreen(),
                          ),
                        ),
                        child: Text(zh ? '查看全部资讯' : 'Browse all updates'),
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
      appBar: AppBar(title: Text(zh ? '全部资讯' : 'All updates')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          SearchBar(
            controller: _search,
            hintText: zh ? '搜索政策、签证或关键词' : 'Search policy, visa or keywords',
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
                    label: Text(zh ? '全部签证' : 'All visas'),
                    selected: _visa == null,
                    onSelected: (_) => setState(() => _visa = null),
                  ),
                  const SizedBox(width: 8),
                  for (final tag in visaTags) ...[
                    ChoiceChip(
                      label: Text(tag),
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
                child: Text(zh ? '没有找到匹配的资讯' : 'No matching updates'),
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
        : (item.titleEn ?? item.sourceTitle ?? item.title);
    final summary = zh ? item.summary : (item.summaryEn ?? item.summary);
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
                          label: Text(tag),
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
    final enTitle = item.titleEn ?? item.sourceTitle ?? item.title;
    final enSummary = item.summaryEn ?? item.summary;
    return Scaffold(
      appBar: AppBar(title: Text(zh ? '资讯详情' : 'Update')),
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
            children: item.tags.map((tag) => Chip(label: Text(tag))).toList(),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => openOfficialSource(context, item.sourceUrl),
            icon: const Icon(Icons.open_in_new),
            label: Text(zh ? '查看官方原文' : 'View official source'),
          ),
        ],
      ),
    );
  }
}
