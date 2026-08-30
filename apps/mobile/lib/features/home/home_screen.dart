import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/links/official_link.dart';
import '../../core/models/models.dart';
import '../../core/state/app_store.dart';
import '../../shared/widgets/common.dart';
import '../projects/project_cloud_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenProjects,
    required this.onOpenChanges,
  });

  final VoidCallback onOpenProjects;
  final VoidCallback onOpenChanges;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _selectedTopic = '全部';
  String? _selectedVisa;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStoreProvider);
    // 筛选值来自服务端目录（只列实际有内容的），目录取不到时退回本地数据推导。
    final jurisdictionChips = state.taxonomy.jurisdictions.isNotEmpty
        ? ['全部', ...state.taxonomy.jurisdictions.map((e) => e.display)]
        : topicsFor(state.news);
    final visaChips = state.taxonomy.visas.map((e) => e.code).toList();

    // 数据变化后原先选中的值可能已经不存在了。
    final activeTopic = jurisdictionChips.contains(_selectedTopic)
        ? _selectedTopic
        : '全部';
    final activeVisa = visaChips.contains(_selectedVisa) ? _selectedVisa : null;

    final visibleNews = state.news
        .where((item) => _matchesTopic(item, activeTopic))
        .where((item) => activeVisa == null || item.tags.contains(activeVisa))
        .toList();
    final nextProject = state.projects
        .where((item) => item.status == ProjectStatus.active)
        .firstOrNull;

    return RefreshIndicator(
      onRefresh: () => ref.read(appStoreProvider.notifier).refreshContent(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
            sliver: SliverList.list(
              children: [
                _EditorialHeader(
                  onSearch: () => showSearch<void>(
                    context: context,
                    delegate: _NewsSearchDelegate(state.news),
                  ),
                  alertCount: state.policyAlerts.length,
                  onNotifications: () => _showNotifications(
                    context,
                    ref,
                    state.policyAlerts,
                    state.projects,
                    state.news,
                    widget.onOpenChanges,
                  ),
                ),
                const SizedBox(height: 18),
                _ContentSignal(
                  refreshing: state.isContentRefreshing,
                  error: state.contentError,
                  updatedAt: state.contentUpdatedAt,
                  onRefresh: () =>
                      ref.read(appStoreProvider.notifier).refreshContent(),
                ),
                const SizedBox(height: 22),
                _TopicRail(
                  topics: jurisdictionChips,
                  selected: activeTopic,
                  onSelected: (topic) => setState(() => _selectedTopic = topic),
                ),
                // 第二行：签证类别。用户先看「关我的州吗」，再看「关我的签证吗」。
                if (visaChips.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _VisaRail(
                    visas: visaChips,
                    selected: activeVisa,
                    onSelected: (visa) => setState(
                      () => _selectedVisa = _selectedVisa == visa ? null : visa,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (visibleNews.isEmpty)
                  EmptyState(
                    icon: Icons.auto_stories_outlined,
                    title: '这个分类还没有内容',
                    body: '换一个分类看看，或者下拉刷新。',
                    action: TextButton(
                      onPressed: () =>
                          ref.read(appStoreProvider.notifier).refreshContent(),
                      child: const Text('重新加载'),
                    ),
                  )
                else ...[
                  _LeadStory(
                    item: visibleNews.first,
                    onTap: () => _showNews(context, ref, visibleNews.first),
                    onBookmark: () => ref
                        .read(appStoreProvider.notifier)
                        .toggleBookmark(visibleNews.first.id),
                  ),
                  const SizedBox(height: 26),
                  _BriefingMetrics(
                    newsCount: state.news.length,
                    changeCount: state.changes.length,
                  ),
                  SectionHeader(
                    title: '更多',
                    trailing: Text(
                      '${visibleNews.length} 条',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ...visibleNews
                      .skip(1)
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _EditorialStoryCard(
                            item: item,
                            onTap: () => _showNews(context, ref, item),
                            onBookmark: () => ref
                                .read(appStoreProvider.notifier)
                                .toggleBookmark(item.id),
                          ),
                        ),
                      ),
                ],
                if (state.changes.isNotEmpty) ...[
                  SectionHeader(
                    title: '政策变化',
                    trailing: TextButton(
                      onPressed: widget.onOpenChanges,
                      child: const Text('查看全部'),
                    ),
                  ),
                  _PolicyRadar(
                    change: state.changes.first,
                    onTap: widget.onOpenChanges,
                  ),
                ],
                const SectionHeader(title: '你的申请'),
                _JourneyCard(
                  project: nextProject,
                  onTap: widget.onOpenProjects,
                ),
                const _DiscussionCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 辖区代码到中文名。与采集器的 `jurisdictions.py` 是同一张表。
const jurisdictionLabels = {
  'AU-SA': '南澳',
  'AU-QLD': '昆士兰',
  'AU-NSW': '新南威尔士',
  'AU-VIC': '维州',
  'AU-WA': '西澳',
  'AU-TAS': '塔州',
  'AU-NT': '北领地',
  'AU-ACT': '首都领地',
  'AU-FED': '联邦',
};

/// 分类胶囊由**实际拿到的数据**决定，不是写死的五个。
///
/// 原先写死 `['全部','南澳','联邦','190','491']`，再靠匹配标签和来源名里的子串来筛。
/// 采集器把所有条目的标签写死成「南澳」之后，「南澳」筛出全部、「联邦」筛出零条，
/// 而且用户看不到昆士兰、西澳、NSW 这三个已经在库里的辖区。
List<String> topicsFor(List<NewsItem> items) {
  final present = <String>{};
  for (final item in items) {
    final label = jurisdictionLabels[item.jurisdiction];
    if (label != null) present.add(label);
  }
  final ordered = jurisdictionLabels.values.where(present.contains);
  return ['全部', ...ordered];
}

bool _matchesTopic(NewsItem item, String topic) {
  if (topic == '全部') return true;
  // 按辖区代码比对，不做子串匹配——`contains('sa')` 在 `visas` 里也会命中。
  return jurisdictionLabels[item.jurisdiction] == topic;
}

class _EditorialHeader extends StatelessWidget {
  const _EditorialHeader({
    required this.onSearch,
    required this.onNotifications,
    this.alertCount = 0,
  });

  final VoidCallback onSearch;
  final VoidCallback onNotifications;
  final int alertCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MIGRATION BRIEF · SOUTH AUSTRALIA',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '移民资讯',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.1,
                  height: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${DateFormat('M月d日').format(DateTime.now())} · 来自官方页面',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        _RoundAction(
          icon: Icons.search_rounded,
          tooltip: '搜索资讯',
          onTap: onSearch,
        ),
        const SizedBox(width: 8),
        Badge.count(
          count: alertCount,
          isLabelVisible: alertCount > 0,
          child: _RoundAction(
            icon: alertCount > 0
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            tooltip: alertCount > 0 ? '$alertCount 条更新' : '提醒',
            onTap: onNotifications,
          ),
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: tooltip,
    style: IconButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      minimumSize: const Size.square(46),
    ),
    icon: Icon(icon),
  );
}

class _ContentSignal extends StatelessWidget {
  const _ContentSignal({
    required this.refreshing,
    required this.onRefresh,
    this.error,
    this.updatedAt,
  });

  final bool refreshing;
  final String? error;
  final DateTime? updatedAt;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasError = error != null;
    final label = refreshing
        ? '正在更新'
        : hasError
        ? '现在看的是上次存下来的内容'
        : updatedAt == null
        ? '还没更新过'
        : '${DateFormat('HH:mm').format(updatedAt!.toLocal())} 更新';
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: hasError ? scheme.tertiary : const Color(0xFF26B58A),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (hasError ? scheme.tertiary : const Color(0xFF26B58A))
                    .withValues(alpha: 0.25),
                blurRadius: 0,
                spreadRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (refreshing)
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 1.8),
          )
        else
          IconButton(
            onPressed: onRefresh,
            tooltip: '刷新',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
      ],
    );
  }
}

class _TopicRail extends StatelessWidget {
  const _TopicRail({
    required this.selected,
    required this.onSelected,
    required this.topics,
  });

  final List<String> topics;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: topics.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final topic = topics[index];
        final active = topic == selected;
        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: active ? scheme.onSurface : scheme.surfaceContainerLowest,
          shape: StadiumBorder(
            side: BorderSide(
              color: active ? scheme.onSurface : scheme.outlineVariant,
            ),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => onSelected(topic),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 17),
              child: Center(
                child: Text(
                  topic,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: active ? scheme.surface : scheme.onSurface,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _LeadStory extends StatelessWidget {
  const _LeadStory({
    required this.item,
    required this.onTap,
    required this.onBookmark,
  });

  final NewsItem item;
  final VoidCallback onTap;
  final VoidCallback onBookmark;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF102536), Color(0xFF174B49), Color(0xFF147B66)],
        stops: [0, 0.58, 1],
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26102536),
          blurRadius: 28,
          offset: Offset(0, 14),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        children: [
          const Positioned(
            right: -54,
            top: -70,
            child: _DecorativeOrb(size: 180, color: Color(0x1FFFFFFF)),
          ),
          const Positioned(
            left: -60,
            bottom: -88,
            child: _DecorativeOrb(size: 160, color: Color(0x1267E8C4)),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bolt_rounded,
                                size: 15,
                                color: Color(0xFF77E3C4),
                              ),
                              SizedBox(width: 5),
                              Text(
                                '今日焦点',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: onBookmark,
                          tooltip: item.bookmarked ? '取消收藏' : '收藏',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.1,
                            ),
                            foregroundColor: Colors.white,
                          ),
                          icon: Icon(
                            item.bookmarked
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 42),
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.18,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item.summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.76),
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          size: 16,
                          color: Color(0xFF77E3C4),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          DateFormat('M月d日').format(item.publishedAt),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.62),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_outward_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DecorativeOrb extends StatelessWidget {
  const _DecorativeOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    ),
  );
}

class _BriefingMetrics extends StatelessWidget {
  const _BriefingMetrics({required this.newsCount, required this.changeCount});

  final int newsCount;
  final int changeCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          const _MetricIcon(icon: Icons.fact_check_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: _Metric(label: '资讯', value: '$newsCount'),
          ),
          Container(width: 1, height: 32, color: scheme.outlineVariant),
          const SizedBox(width: 16),
          Expanded(
            child: _Metric(label: '页面变化', value: '$changeCount'),
          ),
          const SizedBox(width: 4),
          Icon(Icons.trending_up_rounded, color: scheme.primary, size: 20),
        ],
      ),
    );
  }
}

class _MetricIcon extends StatelessWidget {
  const _MetricIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w800, height: 1),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}

class _EditorialStoryCard extends StatelessWidget {
  const _EditorialStoryCard({
    required this.item,
    required this.onTap,
    required this.onBookmark,
  });

  final NewsItem item;
  final VoidCallback onTap;
  final VoidCallback onBookmark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = item.tags.isEmpty ? '官方动态' : item.tags.first;
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _SourceMark(sourceName: item.sourceName),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.sourceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '$category · ${DateFormat('M月d日').format(item.publishedAt)}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onBookmark,
                    tooltip: item.bookmarked ? '取消收藏' : '收藏',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      item.bookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      size: 21,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                item.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.28,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                item.summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
              ),
              if (item.tags.length > 1) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: item.tags
                      .skip(1)
                      .take(3)
                      .map((tag) => _StoryTag(label: tag))
                      .toList(),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.verified_rounded, size: 15, color: scheme.primary),
                  const SizedBox(width: 5),
                  Text(
                    '来源可核对',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '阅读全文',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, size: 17),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceMark extends StatelessWidget {
  const _SourceMark({required this.sourceName});

  final String sourceName;

  @override
  Widget build(BuildContext context) {
    final federal = sourceName.toLowerCase().contains('home affairs');
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: federal ? const Color(0xFFE8EEF8) : const Color(0xFFE1F5EE),
        borderRadius: BorderRadius.circular(13),
      ),
      alignment: Alignment.center,
      child: Text(
        federal ? 'AU' : 'SA',
        style: TextStyle(
          color: federal ? const Color(0xFF315A91) : const Color(0xFF147B66),
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _StoryTag extends StatelessWidget {
  const _StoryTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
}

class _PolicyRadar extends StatelessWidget {
  const _PolicyRadar({required this.change, required this.onTap});

  final PolicyChange change;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final important = change.severity != ChangeSeverity.general;
    return Material(
      color: important
          ? const Color(0xFFFFF3DD)
          : scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: important
                      ? const Color(0xFFFFDFA8)
                      : scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.radar_rounded,
                  color: important ? const Color(0xFF8A5B00) : scheme.primary,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // 核实状态只能来自 verification 字段。用 severity 推导会把
                      // “自动发现、待核实”的变化说成已经过人工核实。
                      important
                          ? '重要变化 · ${change.verification.label}'
                          : change.verification.label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: important
                            ? const Color(0xFF8A5B00)
                            : scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      change.pageTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      change.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_outward_rounded, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.project, required this.onTap});

  final VisaProject? project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final completion = project?.completion ?? 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF172330),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: project == null ? 0 : completion,
                  strokeWidth: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  color: const Color(0xFF67D8B9),
                ),
                Icon(
                  project == null ? Icons.route_outlined : Icons.flag_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project?.name ?? '建立你的申请路线',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  project == null
                      ? '从南澳 190 / 491 开始，逐步整理关键节点'
                      : '${(completion * 100).round()}% 已准备 · 继续处理下一项',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onTap,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }
}

Future<void> _showNews(
  BuildContext context,
  WidgetRef ref,
  NewsItem item,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.94,
      child: _StorySheet(item: item, ref: ref),
    ),
  );
}

class _StorySheet extends StatelessWidget {
  const _StorySheet({required this.item, required this.ref});

  final NewsItem item;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 8,
            width: 54,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
              children: [
                Row(
                  children: [
                    _SourceMark(sourceName: item.sourceName),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${DateFormat('yyyy年M月d日').format(item.publishedAt)} · 官方原文可核对',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: '关闭',
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    const SourceBadge(label: '来源已核对', verified: true),
                    ...item.tags.take(4).map((tag) => _StoryTag(label: tag)),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.22,
                    letterSpacing: -0.6,
                  ),
                ),
                // 我们自己写的英文版。申请人常要把政策转述给雇主、律师或职业评估
                // 机构——那些场合要能直接复制英文，不是让人现译。
                if (item.summaryEn != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'In English',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        if (item.titleEn != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            item.titleEn!,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        SelectableText(
                          item.summaryEn!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(height: 1.6),
                        ),
                      ],
                    ),
                  ),
                ],
                // 中文标题是我们写的，官方标题是官方写的。两个都给，用户才知道
                // 自己在官网上该找哪一篇。
                if (item.sourceTitle != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    item.sourceTitle!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '官方原标题（英文）',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 18,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            '编辑摘要',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.summary,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(height: 1.65),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '内容摘自官方页面。是否适用于你的情况，请以官方原文为准——'
                  '我们不是移民代理，不能替你判断个案。',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.6),
                ),
                const SizedBox(height: 24),
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => openOfficialSource(context, item.sourceUrl),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.language_rounded, color: scheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '官方来源',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                item.sourceName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.open_in_new_rounded, size: 19),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          openOfficialSource(context, item.sourceUrl),
                      icon: const Icon(Icons.article_outlined),
                      label: const Text('读官方原文'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.outlined(
                    onPressed: () => ref
                        .read(appStoreProvider.notifier)
                        .toggleBookmark(item.id),
                    tooltip: item.bookmarked ? '取消收藏' : '收藏',
                    icon: Icon(
                      item.bookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.outlined(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(text: '${item.title}\n${item.sourceUrl}'),
                    ),
                    tooltip: '分享',
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showNotifications(
  BuildContext context,
  WidgetRef ref,
  List<PolicyAlert> alerts,
  List<VisaProject> projects,
  List<NewsItem> news,
  VoidCallback onOpenChanges,
) async {
  final reminders = [
    for (final project in projects)
      for (final item in project.items)
        if (item.reminderAt != null) (project: project, item: item),
  ]..sort((a, b) => a.item.reminderAt!.compareTo(b.item.reminderAt!));

  if (!context.mounted) return;
  // 让面板带着「点了哪一条」关闭，回到这里之后再打开目标。
  // 在 onTap 里 pop 完立刻 showModalBottomSheet，会撞上导航器还在处理
  // 关闭动画的那一瞬间。
  final tapped = await showModalBottomSheet<PolicyAlert>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (alerts.isNotEmpty) ...[
              Text(
                alerts.length > 1 ? '政策更新（${alerts.length}）' : '政策更新',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              // 全部列出并可滚动，不再 take(8)。
              //
              // 之前这里只渲染前 8 条，关闭时却把**全部** id 报成已读——
              // 攒了 50 条提醒的用户，有 42 条从没在屏幕上出现过就永久消失了，
              // 而这些提醒正是这个产品存在的理由。要么让人看得到，要么别标已读。
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.38,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: alerts.length,
                  itemBuilder: (listContext, index) {
                    final alert = alerts[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        alert.isNews
                            ? Icons.article_outlined
                            : Icons.campaign_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(alert.title),
                      subtitle: Text(
                        DateFormat('M月d日 HH:mm').format(alert.createdAt),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      // 提醒一直点不开：服务端早就下发了 route 和 entityId，
                      // App 侧也解析进了模型，只是没有人接上去。收到「南澳
                      // 公布名额」却打不开那一条，提醒就只剩一个感叹号。
                      onTap: () =>
                          Navigator.of(sheetContext).pop(alert),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text('材料提醒', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (reminders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('还没有设置提醒。可以在申请里给某一项加一个。'),
              )
            else
              ...reminders
                  .take(12)
                  .map(
                    (entry) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text(entry.item.title),
                      subtitle: Text(
                        '${entry.project.name} · '
                        '${DateFormat('yyyy-MM-dd HH:mm').format(entry.item.reminderAt!)}',
                      ),
                    ),
                  ),
          ],
        ),
      ),
    ),
  );

  // 关闭之后才标已读，而且此时列表里每一条都已经可滚动地呈现过。
  // 原先是「打开就全部标已读」，配上只渲染 8 条的列表，等于把没看过的丢掉。
  if (alerts.isNotEmpty) {
    unawaited(ref.read(appStoreProvider.notifier).acknowledgePolicyAlerts());
  }
  if (tapped != null && context.mounted) {
    _openAlert(context, ref, tapped, news, onOpenChanges);
  }
}

/// 打开一条提醒指向的内容。
///
/// 资讯类在本地已加载的列表里按 entityId 找；找不到（比如本地还没刷到那一条）
/// 就退回变更列表，而不是什么都不做——点了没反应比跳错地方更让人以为是坏的。
void _openAlert(
  BuildContext context,
  WidgetRef ref,
  PolicyAlert alert,
  List<NewsItem> news,
  VoidCallback onOpenChanges,
) {
  if (alert.isNews) {
    for (final item in news) {
      if (item.id == alert.entityId) {
        unawaited(_showNews(context, ref, item));
        return;
      }
    }
  }
  onOpenChanges();
}

class _NewsSearchDelegate extends SearchDelegate<void> {
  _NewsSearchDelegate(this.items);

  final List<NewsItem> items;

  @override
  String get searchFieldLabel => '搜索标题、摘要、来源或标签';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final results = items.where((item) {
      final haystack = [
        item.title,
        item.summary,
        item.sourceName,
        ...item.tags,
      ].join(' ').toLowerCase();
      return normalized.isEmpty || haystack.contains(normalized);
    }).toList();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = results[index];
        return Card(
          child: ListTile(
            leading: _SourceMark(sourceName: item.sourceName),
            title: Text(item.title),
            subtitle: Text('${item.sourceName} · ${item.tags.join(' / ')}'),
            onTap: () => openOfficialSource(context, item.sourceUrl),
          ),
        );
      },
    );
  }
}

/// 主界面上的讨论入口。
///
/// 讨论此前只存在于「云端与协作」的第三个页签里，用户基本找不到。这一版唯一允许的
/// 用户内容就是项目内的私密讨论——它只在被邀请的协作者之间可见，不是公开社区，
/// 所以可以放到主界面而不需要一套公开内容审核体系。
///
/// 没有云项目、没有登录、或者一条留言都没有时整块不显示：主界面不该出现一个
/// 永远是空的入口。
class _DiscussionCard extends ConsumerStatefulWidget {
  const _DiscussionCard();

  @override
  ConsumerState<_DiscussionCard> createState() => _DiscussionCardState();
}

class _DiscussionCardState extends ConsumerState<_DiscussionCard> {
  Future<ProjectDiscussionPreview?>? _pending;
  int _cloudProjectSignature = -1;
  DateTime? _lastContentRefresh;

  void _reload() => setState(() {
    _pending = ref.read(appStoreProvider.notifier).latestDiscussion();
  });

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStoreProvider);
    final cloudProjects = state.projects
        .where((project) => project.isCloudSyncEnabled)
        .toList();
    if (!state.isSignedIn || cloudProjects.isEmpty) {
      return const SizedBox.shrink();
    }

    // 云项目集合或登录账号变了才重新拉，不然每次 build 都会发一轮请求。
    // 账号必须进签名：登出不会清空 state.projects，而 AppShell 用 IndexedStack
    // 保活这个 State，只按项目 id 判断的话，换人登录会直接看到上一个人的留言。
    final signature = Object.hashAll([
      state.accountEmail,
      ...cloudProjects.map((project) => project.id),
    ]);
    if (signature != _cloudProjectSignature) {
      _cloudProjectSignature = signature;
      _pending = ref.read(appStoreProvider.notifier).latestDiscussion();
    }
    // 内容刷新时把讨论也重新拉一次，否则卡片会永远停在第一次拉到的那条留言，
    // 用户没有任何办法刷新它。
    if (state.contentUpdatedAt != _lastContentRefresh) {
      _lastContentRefresh = state.contentUpdatedAt;
      _pending = ref.read(appStoreProvider.notifier).latestDiscussion();
    }

    return FutureBuilder<ProjectDiscussionPreview?>(
      future: _pending,
      builder: (context, snapshot) {
        // 加载中、全部失败、真的没留言——三种情况以前长得一模一样。
        // 「取不到」显示成「没有留言」是同一类错误：把不知道说成没发生。
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError) {
          return _DiscussionUnavailable(onRetry: _reload);
        }
        final preview = snapshot.data;
        if (preview == null || preview.body.isEmpty) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProjectCloudScreen(
                    projectId: preview.projectId,
                    initialTab: 2,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.forum_outlined,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            preview.projectName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '${preview.totalCount} 条留言',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      preview.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      preview.createdAt == null
                          ? preview.authorLabel
                          : '${preview.authorLabel} · '
                                '${DateFormat('M月d日 HH:mm').format(preview.createdAt!)}',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 讨论拉不到时的样子。空着会被读成「没有人留言」。
class _DiscussionUnavailable extends StatelessWidget {
  const _DiscussionUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined, size: 18, color: scheme.outline),
              const SizedBox(width: 10),
              const Expanded(child: Text('讨论暂时取不到')),
              TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }
}

/// 签证类别筛选。值由服务端目录给出，只列实际有内容的类别。
class _VisaRail extends StatelessWidget {
  const _VisaRail({
    required this.visas,
    required this.selected,
    required this.onSelected,
  });

  final List<String> visas;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: visas.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final visa = visas[index];
        final active = visa == selected;
        final scheme = Theme.of(context).colorScheme;
        return GestureDetector(
          onTap: () => onSelected(visa),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? scheme.primary : scheme.surfaceContainerLowest,
              border: Border.all(
                color: active ? scheme.primary : scheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Text(
              visa,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    ),
  );
}
