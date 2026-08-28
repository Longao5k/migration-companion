import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/models.dart';
import '../../core/state/app_store.dart';
import '../../shared/widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.onOpenProjects});

  final VoidCallback onOpenProjects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStoreProvider);
    final nextProject = state.projects
        .where((item) => item.status == ProjectStatus.active)
        .firstOrNull;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          sliver: SliverList.list(
            children: [
              _Header(
                isSignedIn: state.isSignedIn,
                onSearch: () => showSearch<void>(
                  context: context,
                  delegate: _NewsSearchDelegate(state.news),
                ),
                onNotifications: () =>
                    _showUpcomingReminders(context, state.projects),
              ),
              if (!state.noticeDismissed) ...[
                const SizedBox(height: 20),
                _LocalOnlyNotice(
                  onDismiss: () =>
                      ref.read(appStoreProvider.notifier).dismissNotice(),
                ),
              ],
              const SizedBox(height: 12),
              ContentRefreshStatus(
                refreshing: state.isContentRefreshing,
                error: state.contentError,
                updatedAt: state.contentUpdatedAt,
                onRefresh: () =>
                    ref.read(appStoreProvider.notifier).refreshContent(),
              ),
              const SectionHeader(title: '今天值得关注'),
              if (state.news.isEmpty)
                EmptyState(
                  icon: Icons.newspaper_outlined,
                  title: '暂时没有已发布资讯',
                  body: '内容必须经过来源核对；请稍后刷新。材料项目仍可离线使用。',
                  action: TextButton(
                    onPressed: () =>
                        ref.read(appStoreProvider.notifier).refreshContent(),
                    child: const Text('重新加载'),
                  ),
                )
              else
                _HeroUpdate(
                  item: state.news.first,
                  onTap: () => _showNews(context, ref, state.news.first),
                ),
              SectionHeader(
                title: '我的下一步',
                trailing: TextButton(
                  onPressed: onOpenProjects,
                  child: const Text('全部项目'),
                ),
              ),
              _NextStepCard(project: nextProject, onTap: onOpenProjects),
              if (state.news.length > 1) ...[
                const SectionHeader(title: '最新资讯'),
                ...state.news
                    .skip(1)
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _NewsCard(
                          item: item,
                          onTap: () => _showNews(context, ref, item),
                        ),
                      ),
                    ),
              ],
              const SizedBox(height: 12),
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
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isSignedIn,
    required this.onSearch,
    required this.onNotifications,
  });
  final bool isSignedIn;
  final VoidCallback onSearch;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isSignedIn ? '欢迎回来' : '早上好，访客',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 3),
              Text(
                '把申请这件事，理清楚',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onSearch,
          icon: const Icon(Icons.search),
          tooltip: '搜索和筛选资讯',
        ),
        IconButton.filledTonal(
          onPressed: onNotifications,
          icon: const Icon(Icons.notifications_none),
          tooltip: '通知',
        ),
      ],
    );
  }
}

class _LocalOnlyNotice extends StatelessWidget {
  const _LocalOnlyNotice({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.phonelink_lock_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前是本机模式',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text('项目只保存在这台设备。你随时可以导出备份；注册不会自动上传敏感文件。'),
                ],
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
              tooltip: '关闭',
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroUpdate extends StatelessWidget {
  const _HeroUpdate({required this.item, required this.onTap});
  final NewsItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primary,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SourceBadge(label: '南澳官方来源', verified: true),
              const SizedBox(height: 32),
              Text(
                item.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onPrimary.withValues(alpha: 0.82),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    DateFormat('yyyy年M月d日').format(item.publishedAt),
                    style: TextStyle(
                      color: scheme.onPrimary.withValues(alpha: 0.72),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward, color: scheme.onPrimary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextStepCard extends StatelessWidget {
  const _NextStepCard({required this.project, required this.onTap});
  final VisaProject? project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (project == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Icon(Icons.add_task),
              const SizedBox(width: 12),
              const Expanded(child: Text('创建第一个南澳 190/491 材料项目')),
              FilledButton.tonal(onPressed: onTap, child: const Text('开始')),
            ],
          ),
        ),
      );
    }
    final next = project!.items
        .where((item) => item.status.index < ChecklistStatus.ready.index)
        .firstOrNull;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      project!.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text('${(project!.completion * 100).round()}%'),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: project!.completion,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(height: 12),
              Text(next == null ? '清单已全部达到“已准备”' : '下一步：${next.title}'),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item, required this.onTap});
  final NewsItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          item.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${item.sourceName} · ${DateFormat('M月d日').format(item.publishedAt)}',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
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
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        MediaQuery.viewPaddingOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SourceBadge(label: '来源可核对', verified: true),
          const SizedBox(height: 16),
          Text(
            item.title,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(item.summary),
          const SizedBox(height: 18),
          const Text('本摘要用于帮助理解发生了什么，不判断任何人的签证资格。'),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(item.sourceUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('查看官方原文'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(appStoreProvider.notifier).toggleBookmark(item.id),
                icon: Icon(
                  item.bookmarked ? Icons.bookmark : Icons.bookmark_border,
                ),
                label: Text(item.bookmarked ? '已收藏' : '收藏'),
              ),
              OutlinedButton.icon(
                onPressed: () => SharePlus.instance.share(
                  ShareParams(text: '${item.title}\n${item.sourceUrl}'),
                ),
                icon: const Icon(Icons.share_outlined),
                label: const Text('分享'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
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
                child: Center(child: Text('暂无提醒。可在材料项中设置。')),
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
