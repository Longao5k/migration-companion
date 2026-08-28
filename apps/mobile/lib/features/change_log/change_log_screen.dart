import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
      if (changes.isEmpty)
        EmptyState(
          icon: Icons.change_circle_outlined,
          title: '暂时没有可公开的变更证据',
          body: '重大与重要变化必须人工核实；页面故障不会作为政策变化发布。',
          action: TextButton(
            onPressed: () =>
                ref.read(appStoreProvider.notifier).refreshContent(),
            child: const Text('重新加载'),
          ),
        )
      else
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
      '不是“听说政策改了”，而是保留来源、时间、修改前后和人工核实状态。',
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
          const SectionHeader(title: '页面差异'),
          _DiffBlock(title: '修改前', text: change.beforeText, added: false),
          const SizedBox(height: 10),
          _DiffBlock(title: '修改后', text: change.afterText, added: true),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(change.sourceUrl),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('打开官方页面核对'),
          ),
          const SizedBox(height: 14),
          Text(
            '此记录展示页面证据，不构成对个人资格或申请结果的判断。',
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
