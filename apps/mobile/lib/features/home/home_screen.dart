import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/models.dart';
import '../../core/state/app_store.dart';
import '../../shared/widgets/common.dart';

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStoreProvider);
    final visibleNews = state.news
        .where((item) => _matchesTopic(item, _selectedTopic))
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
                  onNotifications: () =>
                      _showUpcomingReminders(context, state.projects),
                ),
                const SizedBox(height: 18),
                _ContentSignal(
                  refreshing: state.isContentRefreshing,
                  error: state.contentError,
                  updatedAt: state.contentUpdatedAt,
                  onRefresh: () =>
                      ref.read(appStoreProvider.notifier).refreshContent(),
                ),
                if (!state.noticeDismissed) ...[
                  const SizedBox(height: 12),
                  _PrivacyNote(
                    onDismiss: () =>
                        ref.read(appStoreProvider.notifier).dismissNotice(),
                  ),
                ],
                const SizedBox(height: 22),
                _TopicRail(
                  selected: _selectedTopic,
                  onSelected: (topic) => setState(() => _selectedTopic = topic),
                ),
                const SizedBox(height: 18),
                if (visibleNews.isEmpty)
                  EmptyState(
                    icon: Icons.auto_stories_outlined,
                    title: '这个主题还没有已发布资讯',
                    body: '我们只展示能回到官方原文的内容。可以切换主题或稍后刷新。',
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
                    title: '最新解读',
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
                    title: '政策雷达',
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
                const SizedBox(height: 26),
                Text(
                  '内容仅作信息整理，不构成移民法律意见。请始终核对官方原文。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

bool _matchesTopic(NewsItem item, String topic) {
  if (topic == '全部') return true;
  final search = [item.sourceName, ...item.tags].join(' ').toLowerCase();
  return switch (topic) {
    '南澳' => search.contains('南澳') || search.contains('sa'),
    '联邦' => search.contains('联邦') || search.contains('home affairs'),
    _ => search.contains(topic.toLowerCase()),
  };
}

class _EditorialHeader extends StatelessWidget {
  const _EditorialHeader({
    required this.onSearch,
    required this.onNotifications,
  });

  final VoidCallback onSearch;
  final VoidCallback onNotifications;

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
                '${DateFormat('M月d日').format(DateTime.now())} · 只读经过来源核对的变化',
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
        _RoundAction(
          icon: Icons.notifications_none_rounded,
          tooltip: '提醒',
          onTap: onNotifications,
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
        ? '正在同步官方来源'
        : hasError
        ? '离线阅读 · 当前为最近缓存'
        : updatedAt == null
        ? '等待首次同步'
        : '已于 ${DateFormat('HH:mm').format(updatedAt!.toLocal())} 核对来源';
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
            tooltip: '刷新官方内容',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
      ],
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: 9),
          const Expanded(child: Text('访客项目仍只保存在本机，注册不会自动上传。')),
          IconButton(
            onPressed: onDismiss,
            tooltip: '关闭',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _TopicRail extends StatelessWidget {
  const _TopicRail({required this.selected, required this.onSelected});

  static const topics = ['全部', '南澳', '联邦', '190', '491'];
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
            child: _Metric(label: '已发布解读', value: '$newsCount'),
          ),
          Container(width: 1, height: 32, color: scheme.outlineVariant),
          const SizedBox(width: 16),
          Expanded(
            child: _Metric(label: '核实变更', value: '$changeCount'),
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
                const SizedBox(height: 24),
                Text('如何使用这条资讯', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Text(
                  '先阅读官方页面确认日期、适用范围和例外情况，再决定是否更新自己的申请计划。本摘要不会判断个人资格，也不会替代注册移民代理或律师意见。',
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.65),
                ),
                const SizedBox(height: 24),
                Container(
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
                      onPressed: () => launchUrl(
                        Uri.parse(item.sourceUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('查看官方原文'),
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

Future<void> _showUpcomingReminders(
  BuildContext context,
  List<VisaProject> projects,
) async {
  final reminders = [
    for (final project in projects)
      for (final item in project.items)
        if (item.reminderAt != null) (project: project, item: item),
  ]..sort((a, b) => a.item.reminderAt!.compareTo(b.item.reminderAt!));
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已设置的提醒', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (reminders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('暂无提醒。可在申请路线中设置。')),
              )
            else
              ...reminders
                  .take(12)
                  .map(
                    (entry) => ListTile(
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text(entry.item.title),
                      subtitle: Text(
                        '${entry.project.name} · ${DateFormat('yyyy-MM-dd HH:mm').format(entry.item.reminderAt!)}',
                      ),
                    ),
                  ),
          ],
        ),
      ),
    ),
  );
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
            onTap: () => launchUrl(
              Uri.parse(item.sourceUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        );
      },
    );
  }
}
