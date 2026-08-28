import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/links/official_link.dart';

import '../../core/models/models.dart';
import '../../core/state/app_store.dart';
import '../../shared/widgets/common.dart';

class ChangeLogScreen extends ConsumerWidget {
  const ChangeLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStoreProvider);
    final changes = state.changes;
    final children = <Widget>[
      const _EvidenceIntro(),
      ContentRefreshStatus(
        refreshing: state.isContentRefreshing,
        error: state.contentError,
        updatedAt: state.contentUpdatedAt,
        onRefresh: () => ref.read(appStoreProvider.notifier).refreshContent(),
      ),
      // 空列表有两种完全不同的含义。把「没在监控」显示成「没有变化」，
      // 在移民产品上等于告诉用户政策没变——必须按真实监控状态分别措辞。
      if (changes.isEmpty)
        _ChangesEmptyState(monitoring: state.monitoring)
      else if (state.monitoring?.hasGap ?? false)
        _MonitoringGapNotice(monitoring: state.monitoring!),
      if (changes.isNotEmpty)
        ...changes.map((change) => _ChangeCard(change: change)),
    ];
    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(title: Text('政策变更证据')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: SliverList.separated(
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => children[index],
          ),
        ),
      ],
    );
  }
}

class _EvidenceIntro extends StatelessWidget {
  const _EvidenceIntro();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      '官方页面一改动就记录下来，改前改后都在，你可以自己对照。',
      style: Theme.of(context).textTheme.bodyLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.change});
  final PolicyChange change;

  @override
  Widget build(BuildContext context) {
    final verified = change.verification.isHumanReviewed;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChangeDetailScreen(change: change)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SourceBadge(
                    label: verified ? '已人工核实' : '待人工核实',
                    verified: verified,
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('M月d日 HH:mm').format(change.discoveredAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                change.pageTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                change.summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                children: change.tags
                    .map(
                      (tag) => Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChangeDetailScreen extends StatelessWidget {
  const ChangeDetailScreen({super.key, required this.change});
  final PolicyChange change;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('变更详情')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            children: [
              SourceBadge(
                label: change.verification.label,
                verified: change.verification.isHumanReviewed,
              ),
              const Spacer(),
              Text(DateFormat('yyyy-MM-dd HH:mm').format(change.discoveredAt)),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            change.pageTitle,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(change.summary),
          if (!change.verification.isHumanReviewed) ...[
            const SizedBox(height: 12),
            Text(
              '系统发现这个页面变了，我们的编辑还在核对。在核对完成前，请直接看官方原文。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SectionHeader(title: '官方页面改了什么'),
          _DiffBlock(title: '改之前', text: change.beforeText, added: false),
          const SizedBox(height: 10),
          _DiffBlock(title: '改之后', text: change.afterText, added: true),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => openOfficialSource(context, change.sourceUrl),
            icon: const Icon(Icons.article_outlined),
            label: const Text('读官方原文'),
          ),
          const SizedBox(height: 14),
          Text(
            '上面是官方页面改动前后的原文摘录。是否影响你的申请，请以官方原文为准。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DiffBlock extends StatelessWidget {
  const _DiffBlock({
    required this.title,
    required this.text,
    required this.added,
  });
  final String title;
  final String text;
  final bool added;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = added ? scheme.primaryContainer : scheme.errorContainer;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(text),
        ],
      ),
    );
  }
}

/// 变更列表为空时的措辞，按真实监控状态区分。
class _ChangesEmptyState extends ConsumerWidget {
  const _ChangesEmptyState({required this.monitoring});

  final MonitoringStatus? monitoring;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reload = TextButton(
      onPressed: () => ref.read(appStoreProvider.notifier).refreshContent(),
      child: const Text('重新加载'),
    );

    // 还没拿到监控状态：不能断言任何一种情况。
    if (monitoring == null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: '还没有取到变更记录',
        body: '检查一下网络，或者稍后再看。',
        action: reload,
      );
    }

    final gap = monitoring!.gapSentence;
    if (gap != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: '有一部分页面监控不到',
        body:
            '正在监控 ${monitoring!.monitoredCount} 个官方页面，$gap，'
            '这部分的变化请直接去官网看。',
        action: reload,
      );
    }

    // 「有改动正在核实」和「没有改动」是两件事，不能都显示成后者。
    if (monitoring!.pendingReviewCount > 0) {
      return EmptyState(
        icon: Icons.hourglass_bottom_outlined,
        title: '有 ${monitoring!.pendingReviewCount} 条改动正在核对',
        body: '我们发现官方页面有改动，编辑核对完就会出现在这里。急的话可以先去官网看。',
        action: reload,
      );
    }

    return EmptyState(
      icon: Icons.check_circle_outline,
      title: '这些页面暂时没有变化',
      body:
          '正在监控 ${monitoring!.monitoredCount} 个官方页面。'
          '有改动会出现在这里，重要的改动我们会先人工核实。',
      action: reload,
    );
  }
}

/// 有变更、但同时存在监控缺口时的提示：列表不完整这件事要说出来。
class _MonitoringGapNotice extends StatelessWidget {
  const _MonitoringGapNotice({required this.monitoring});

  final MonitoringStatus monitoring;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${monitoring.gapSentence ?? '有一部分页面监控不到'}，下面只包含能监控到的部分。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
