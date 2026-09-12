import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/app_language.dart';
import '../../core/links/official_link.dart';
import '../../core/models/models.dart';
import '../../core/state/app_store.dart';

class ChangeLogScreen extends ConsumerStatefulWidget {
  const ChangeLogScreen({super.key});
  @override
  ConsumerState<ChangeLogScreen> createState() => _ChangeLogScreenState();
}

class _ChangeLogScreenState extends ConsumerState<ChangeLogScreen> {
  final _search = TextEditingController();
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
    final changes = state.changes.where((item) {
      if (item.verification != VerificationStatus.verified &&
          item.verification != VerificationStatus.corrected) {
        return false;
      }
      if (!zh && (item.summaryEn?.trim().isEmpty ?? true)) {
        return false;
      }
      return query.isEmpty ||
          '${item.pageTitle} ${item.pageTitleEn ?? ''} ${item.summary} ${item.summaryEn ?? ''} ${item.tags.join(' ')}'
              .toLowerCase()
              .contains(query);
    }).toList()..sort((a, b) => b.discoveredAt.compareTo(a.discoveredAt));
    return Scaffold(
      appBar: AppBar(title: Text(zh ? '政策变更' : 'Policy changes')),
      body: RefreshIndicator(
        onRefresh: ref.read(appStoreProvider.notifier).refreshContent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            Text(
              zh ? '看清哪些内容变了，以及改动前后的完整语境。这里只显示已经核实的更新。' : 'See what changed in context. Only verified updates appear here.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            SearchBar(
              controller: _search,
              leading: const Icon(Icons.search),
              hintText: zh ? '搜索页面、签证或关键词' : 'Search page, visa or keyword',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            if (changes.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      const Icon(Icons.verified_outlined, size: 46),
                      const SizedBox(height: 12),
                      Text(
                        zh ? '暂无已核实的政策变更' : 'No verified policy changes yet',
                      ),
                      const SizedBox(height: 5),
                      Text(
                        zh ? '我们不会把时间戳、菜单或维护公告当作政策更新。' : 'Timestamps, menus and maintenance notices are not treated as policy changes.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              for (final item in changes) _ChangeCard(change: item),
          ],
        ),
      ),
    );
  }
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.change});
  final PolicyChange change;
  @override
  Widget build(BuildContext context) {
    final zh = isChineseUi(context);
    final title = zh
        ? change.pageTitle
        : (change.pageTitleEn ?? change.pageTitle);
    final summary = zh ? change.summary : change.summaryEn!;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChangeDetailScreen(change: change)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.verified_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    zh ? '已核实' : 'Verified',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat.yMMMd().format(change.discoveredAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(summary, maxLines: 3, overflow: TextOverflow.ellipsis),
              if (change.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: change.tags
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

class ChangeDetailScreen extends StatelessWidget {
  const ChangeDetailScreen({required this.change, super.key});
  final PolicyChange change;
  @override
  Widget build(BuildContext context) {
    final zh = isChineseUi(context);
    final title = zh
        ? change.pageTitle
        : (change.pageTitleEn ?? change.pageTitle);
    final summary = zh ? change.summary : (change.summaryEn ?? '');
    return Scaffold(
      appBar: AppBar(title: Text(zh ? '变更详情' : 'Change details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                zh ? '已核实' : 'Verified',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(summary, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 26),
          _DiffBlock(
            title: zh ? '改动前' : 'Before',
            text: change.beforeText,
            color: Theme.of(context).colorScheme.errorContainer,
          ),
          const SizedBox(height: 14),
          _DiffBlock(
            title: zh ? '改动后' : 'After',
            text: change.afterText,
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => openOfficialSource(context, change.sourceUrl),
            icon: const Icon(Icons.open_in_new),
            label: Text(zh ? '打开当前官方页面' : 'Open current official page'),
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
    required this.color,
  });
  final String title;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        SelectableText(
          text.isEmpty ? '—' : text,
          style: const TextStyle(fontFamily: 'monospace', height: 1.5),
        ),
      ],
    ),
  );
}
