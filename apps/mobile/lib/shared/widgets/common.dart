import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.label, this.verified = false});

  final String label;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: verified
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (verified) ...[
            Icon(
              Icons.verified_outlined,
              size: 14,
              color: scheme.onPrimaryContainer,
            ),
            const SizedBox(width: 4),
          ],
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            action,
          ],
        ),
      ),
    );
  }
}

class ContentRefreshStatus extends StatelessWidget {
  const ContentRefreshStatus({
    super.key,
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
    final hasError = error != null;
    return Card(
      color: hasError
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListTile(
        leading: refreshing
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                hasError ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
              ),
        title: Text(
          refreshing
              ? '正在更新官方内容'
              : hasError
              ? '当前显示本机缓存'
              : '官方内容已同步',
        ),
        subtitle: Text(
          error ??
              (updatedAt == null
                  ? '首次联网后会保存离线缓存。'
                  : '最近更新 ${DateFormat('yyyy-MM-dd HH:mm').format(updatedAt!.toLocal())}'),
        ),
        trailing: IconButton(
          onPressed: refreshing ? null : onRefresh,
          icon: const Icon(Icons.refresh),
          tooltip: '刷新官方内容',
        ),
      ),
    );
  }
}

/// 文件大小显示。上传、云文件和分享界面必须用同一套口径，避免同一文件在不同界面
/// 显示成不同大小。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
