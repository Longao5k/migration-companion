import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/backup/backup_codec.dart';
import '../../core/documents/document_engines.dart';
import '../../core/models/models.dart';
import '../../core/state/app_store.dart';
import '../../shared/widgets/common.dart';
import 'project_cloud_screen.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStoreProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('申请路线'),
        actions: [
          IconButton(
            onPressed: () => showSearch<void>(
              context: context,
              delegate: _MaterialSearchDelegate(state.projects),
            ),
            icon: const Icon(Icons.search),
            tooltip: '搜索和筛选材料',
          ),
          IconButton(
            onPressed: () => _importBackup(context, ref),
            icon: const Icon(Icons.settings_backup_restore),
            tooltip: '恢复加密备份',
          ),
          IconButton(
            onPressed: () => _createProject(context, ref),
            icon: const Icon(Icons.add),
            tooltip: '新建项目',
          ),
        ],
      ),
      body: !state.isHydrated
          ? const Center(child: CircularProgressIndicator())
          : state.projects.isEmpty
          ? EmptyState(
              icon: Icons.route_outlined,
              title: '规划你的第一条申请路线',
              body: '从南澳 190/491 基础路线开始，把关键节点、材料和提醒放在同一个时间线上。',
              action: FilledButton.icon(
                onPressed: () => _createProject(context, ref),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('开始规划'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              itemCount: state.projects.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) =>
                  _ProjectCard(project: state.projects[index]),
            ),
    );
  }
}

class _MaterialSearchDelegate extends SearchDelegate<void> {
  _MaterialSearchDelegate(this.projects);
  final List<VisaProject> projects;
  ChecklistStatus? statusFilter;

  @override
  String get searchFieldLabel => '搜索项目、材料、分类或申请人';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    PopupMenuButton<ChecklistStatus?>(
      tooltip: '按状态筛选',
      initialValue: statusFilter,
      onSelected: (value) {
        statusFilter = value;
        showSuggestions(context);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: null, child: Text('全部状态')),
        ...ChecklistStatus.values.map(
          (status) => PopupMenuItem(value: status, child: Text(status.label)),
        ),
      ],
      icon: Icon(statusFilter == null ? Icons.filter_list : Icons.filter_alt),
    ),
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
    final results = [
      for (final project in projects)
        for (final item in project.items)
          if ((statusFilter == null || item.status == statusFilter) &&
              (normalized.isEmpty ||
                  [
                    project.name,
                    project.visaType,
                    project.applicant,
                    item.title,
                    item.category,
                    item.owner,
                  ].join(' ').toLowerCase().contains(normalized)))
            (project: project, item: item),
    ];
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final result = results[index];
        return Card(
          child: ListTile(
            leading: Icon(_statusIconForSearch(result.item.status)),
            title: Text(result.item.title),
            subtitle: Text(
              '${result.project.name} · ${result.item.category} · ${result.item.status.label}',
            ),
            onTap: () {
              close(context, null);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ProjectDetailScreen(projectId: result.project.id),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

IconData _statusIconForSearch(ChecklistStatus status) => switch (status) {
  ChecklistStatus.notStarted => Icons.radio_button_unchecked,
  ChecklistStatus.preparing => Icons.pending_outlined,
  ChecklistStatus.ready => Icons.check_circle_outline,
  ChecklistStatus.sent => Icons.send_outlined,
  ChecklistStatus.confirmed => Icons.verified_outlined,
};

Future<void> _createProject(BuildContext context, WidgetRef ref) async {
  final nameController = TextEditingController(text: '我的南澳申请');
  final applicantController = TextEditingController(text: '主申请人');
  var visaType = 'SA 190';
  final created = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('创建申请路线'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '项目名称'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: visaType,
              decoration: const InputDecoration(labelText: '模板'),
              items: const ['SA 190', 'SA 491', '空白项目']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => visaType = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: applicantController,
              decoration: const InputDecoration(labelText: '申请人'),
            ),
            const SizedBox(height: 12),
            const Text(
              '模板仅用于整理材料，不代表完整、适用或满足签证要求。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('创建'),
          ),
        ],
      ),
    ),
  );
  if (created == true && context.mounted) {
    final project = await ref
        .read(appStoreProvider.notifier)
        .addProject(
          name: nameController.text.trim().isEmpty
              ? '未命名项目'
              : nameController.text.trim(),
          visaType: visaType,
          applicant: applicantController.text.trim().isEmpty
              ? '主申请人'
              : applicantController.text.trim(),
        );
    if (context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProjectDetailScreen(projectId: project.id),
        ),
      );
    }
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});
  final VisaProject project;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
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
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.route_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${project.visaType} · ${project.items.length} 个关键节点',
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: project.completion,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 8),
            Text('${(project.completion * 100).round()}% 达到“已准备”或之后状态'),
          ],
        ),
      ),
    ),
  );
}

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({super.key, required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref
        .watch(appStoreProvider)
        .projects
        .where((item) => item.id == projectId)
        .firstOrNull;
    if (project == null) {
      return const Scaffold(body: Center(child: Text('项目不存在')));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        actions: [
          IconButton(
            onPressed: () => _showShareOptions(context, ref, project),
            icon: const Icon(Icons.ios_share),
            tooltip: '分享',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'backup') _exportBackup(context, ref, project);
              if (value == 'activity') _showActivityLog(context, project);
              if (value == 'cloud') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProjectCloudScreen(projectId: project.id),
                  ),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'cloud', child: Text('云端与协作管理')),
              PopupMenuItem(value: 'activity', child: Text('查看操作记录')),
              PopupMenuItem(value: 'backup', child: Text('导出完整备份')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _ProjectSummary(project: project),
          if (project.isCloudSyncEnabled) _ProjectSyncCard(project: project),
          SectionHeader(
            title: '材料清单',
            trailing: IconButton(
              onPressed: () => _addItem(context, ref, project.id),
              icon: const Icon(Icons.add_circle_outline),
              tooltip: '添加清单项',
            ),
          ),
          if (project.items.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('这是空白项目。添加第一项你需要准备的材料。'),
              ),
            )
          else
            ...project.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ChecklistTile(projectId: project.id, item: item),
              ),
            ),
          const SectionHeader(title: '隐私与备份'),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: const Icon(Icons.phonelink_lock_outlined),
              title: Text(project.isCloudSyncEnabled ? '已开启项目云同步' : '仅保存在本机'),
              subtitle: Text(
                project.isCloudSyncEnabled
                    ? '项目元数据和你明确选择的云文件受账号保护。'
                    : '注册或登录不会自动上传。云同步必须按项目单独开启。',
              ),
              trailing: project.isCloudSyncEnabled
                  ? const Icon(Icons.cloud_done_outlined)
                  : const Icon(Icons.chevron_right),
              onTap: project.isCloudSyncEnabled
                  ? null
                  : () => _enableCloudSync(context, ref, project),
            ),
          ),
          if (project.isCloudSyncEnabled)
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.download_for_offline_outlined),
                title: const Text('允许“仅查看”成员下载文件'),
                subtitle: const Text('默认关闭；协作者仍可下载。下载后的副本无法撤回。'),
                value: project.allowViewerDownload,
                onChanged: (value) =>
                    _setViewerDownload(context, ref, project.id, value),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProjectSyncCard extends ConsumerWidget {
  const _ProjectSyncCard({required this.project});

  final VisaProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, title, fallback, color) = switch (project.syncStatus) {
      ProjectSyncStatus.synced => (
        Icons.cloud_done_outlined,
        '云端已同步',
        project.lastSyncedAt == null
            ? '项目元数据已连接账号'
            : '上次同步 ${DateFormat('MM-dd HH:mm').format(project.lastSyncedAt!)}',
        scheme.primary,
      ),
      ProjectSyncStatus.pending => (
        Icons.cloud_upload_outlined,
        '${project.pendingSyncCount} 项修改等待同步',
        '本机修改已保存，联网后会按顺序重试。',
        scheme.tertiary,
      ),
      ProjectSyncStatus.conflict => (
        Icons.sync_problem_outlined,
        '发现版本冲突',
        '先比较字段差异，再选择云端或本机版本。',
        scheme.error,
      ),
      ProjectSyncStatus.error => (
        Icons.cloud_off_outlined,
        '同步需要处理',
        '本机数据仍然安全，可手动重试。',
        scheme.error,
      ),
      ProjectSyncStatus.localOnly => (
        Icons.cloud_queue_outlined,
        '等待建立云端连接',
        '本机数据不会被自动覆盖。',
        scheme.outline,
      ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(project.syncMessage ?? fallback),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (project.syncStatus == ProjectSyncStatus.conflict)
              FilledButton.tonal(
                onPressed: () => _showSyncConflict(context, ref, project),
                child: const Text('比较'),
              )
            else
              IconButton(
                tooltip: '立即同步',
                onPressed: () => _syncNow(context, ref, project.id),
                icon: const Icon(Icons.sync),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _syncNow(
  BuildContext context,
  WidgetRef ref,
  String projectId,
) async {
  try {
    await ref.read(appStoreProvider.notifier).syncProject(projectId);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('同步完成')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('暂时无法同步：$error')));
    }
  }
}

Future<void> _showSyncConflict(
  BuildContext context,
  WidgetRef ref,
  VisaProject project,
) async {
  List<String> differences;
  try {
    differences = await ref
        .read(appStoreProvider.notifier)
        .compareCloudProject(project.id);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法读取云端差异：$error')));
    }
    return;
  }
  if (!context.mounted) return;
  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('比较本机与云端'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('只列出发生变化的字段，不展示备注等敏感内容。'),
              const SizedBox(height: 12),
              ...differences.map(
                (difference) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $difference'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('稍后处理'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'cloud'),
          child: const Text('使用云端版本'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, 'local'),
          child: const Text('保留本机修改'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'cloud') {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认使用云端版本？'),
        content: const Text('此项目等待同步的清单修改会被放弃；已经保存在设备上的附件字节不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认使用云端'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
  }
  try {
    final store = ref.read(appStoreProvider.notifier);
    if (choice == 'cloud') {
      await store.useCloudProjectVersion(project.id);
    } else {
      await store.keepLocalProjectVersion(project.id);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('冲突已处理')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('冲突尚未处理：$error')));
    }
  }
}

Future<void> _setViewerDownload(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  bool enabled,
) async {
  try {
    await ref
        .read(appStoreProvider.notifier)
        .setViewerDownload(projectId, enabled);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('权限未更新：$error')));
    }
  }
}

class _ProjectSummary extends StatelessWidget {
  const _ProjectSummary({required this.project});
  final VisaProject project;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SourceBadge(label: project.visaType),
              const Spacer(),
              Text(
                project.targetDate == null
                    ? '未设目标日期'
                    : '目标 ${DateFormat('yyyy-MM-dd').format(project.targetDate!)}',
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '${(project.completion * 100).round()}%',
            style: Theme.of(context).textTheme.displaySmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Text('已准备、已发送或已确认'),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: project.completion,
            minHeight: 8,
            borderRadius: BorderRadius.circular(10),
          ),
        ],
      ),
    ),
  );
}

class _ChecklistTile extends ConsumerWidget {
  const _ChecklistTile({required this.projectId, required this.item});
  final String projectId;
  final ChecklistItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(
          _statusIcon(item.status),
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          item.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${item.category} · ${item.owner}${item.attachmentCount > 0 ? ' · ${item.attachmentCount} 个文件' : ''}',
        ),
        trailing: IconButton(
          tooltip: '推进到下一状态',
          icon: const Icon(Icons.arrow_circle_right_outlined),
          onPressed: () => _advanceStatus(context, ref, projectId, item.id),
        ),
        onTap: () => _showChecklistItem(context, ref, projectId, item.id),
      ),
    );
  }

  IconData _statusIcon(ChecklistStatus status) => switch (status) {
    ChecklistStatus.notStarted => Icons.radio_button_unchecked,
    ChecklistStatus.preparing => Icons.pending_outlined,
    ChecklistStatus.ready => Icons.check_circle_outline,
    ChecklistStatus.sent => Icons.send_outlined,
    ChecklistStatus.confirmed => Icons.verified_outlined,
  };
}

Future<void> _advanceStatus(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  String itemId,
) async {
  try {
    await ref
        .read(appStoreProvider.notifier)
        .advanceChecklistItem(projectId, itemId);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('状态未更新：$error')));
    }
  }
}

Future<void> _showChecklistItem(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  String itemId,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final project = ref
            .watch(appStoreProvider)
            .projects
            .firstWhere((candidate) => candidate.id == projectId);
        final item = project.items.firstWhere(
          (candidate) => candidate.id == itemId,
        );
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.78,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    SourceBadge(
                      label: item.status.label,
                      verified:
                          item.status.index >= ChecklistStatus.ready.index,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${item.category} · ${item.owner}'),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      _advanceStatus(context, ref, projectId, itemId),
                  icon: const Icon(Icons.arrow_circle_right_outlined),
                  label: Text('推进为“${item.status.next.label}”'),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.event_outlined),
                        title: const Text('目标日期'),
                        subtitle: Text(
                          item.dueDate == null
                              ? '尚未设置'
                              : DateFormat('yyyy-MM-dd').format(item.dueDate!),
                        ),
                        onTap: () =>
                            _pickDueDate(context, ref, projectId, item),
                        trailing: item.dueDate == null
                            ? const Icon(Icons.chevron_right)
                            : IconButton(
                                tooltip: '清除目标日期',
                                icon: const Icon(Icons.close),
                                onPressed: () => _clearDueDate(
                                  context,
                                  ref,
                                  projectId,
                                  item,
                                ),
                              ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.notifications_active_outlined,
                        ),
                        title: const Text('系统提醒'),
                        subtitle: Text(
                          item.reminderAt == null
                              ? '点击设置；届时锁屏不显示材料名称'
                              : DateFormat('yyyy-MM-dd HH:mm')
                                    .format(item.reminderAt!),
                        ),
                        onTap: () =>
                            _pickReminder(context, ref, projectId, item),
                        trailing: item.reminderAt == null
                            ? const Icon(Icons.chevron_right)
                            : IconButton(
                                tooltip: '取消提醒',
                                icon: const Icon(
                                  Icons.notifications_off_outlined,
                                ),
                                onPressed: () => _clearReminder(
                                  context,
                                  ref,
                                  projectId,
                                  item,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.notes_outlined),
                    title: const Text('备注'),
                    subtitle: Text(item.note.isEmpty ? '尚未填写' : item.note),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _editNote(context, ref, projectId, item),
                  ),
                ),
                const SectionHeader(title: '本机附件'),
                const Text('附件默认复制到 App 私有目录，不因登录自动上传。删除原始选取文件也不会影响这里的副本。'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      _pickAttachment(context, ref, projectId, itemId),
                  icon: const Icon(Icons.attach_file),
                  label: const Text('从设备添加附件'),
                ),
                if (item.attachments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('尚未添加附件')),
                  )
                else
                  ...item.attachments.map(
                    (attachment) => Card(
                      child: ListTile(
                        leading: Icon(_attachmentIcon(attachment.name)),
                        title: Text(attachment.name),
                        subtitle: Text(
                          '${formatBytes(attachment.byteSize)} · ${_attachmentStatusLabel(attachment.syncStatus)}',
                        ),
                        onTap: () => _openAttachment(context, attachment),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'upload') {
                              _uploadAttachment(
                                context,
                                ref,
                                projectId,
                                itemId,
                                attachment,
                              );
                            }
                            if (value == 'remove') {
                              _removeAttachment(
                                context,
                                ref,
                                projectId,
                                itemId,
                                attachment,
                              );
                            }
                          },
                          itemBuilder: (_) => [
                            // 云文件未开放时不显示上传入口，避免用户点了才知道不可用。
                            if (ref.watch(appStoreProvider).cloudFileUploadsEnabled &&
                                project.isCloudSyncEnabled &&
                                attachment.syncStatus !=
                                    AttachmentSyncStatus.available &&
                                attachment.syncStatus !=
                                    AttachmentSyncStatus.scanning &&
                                attachment.syncStatus !=
                                    AttachmentSyncStatus.uploading)
                              const PopupMenuItem(
                                value: 'upload',
                                child: Text('明确上传到云端'),
                              ),
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('删除本机副本'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (project.isCloudSyncEnabled &&
                    item.attachments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '云文件上传必须逐个明确确认。上传后先进入隔离区，安全扫描通过前不能下载或分享。',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _editNote(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  ChecklistItem item,
) async {
  final controller = TextEditingController(text: item.note);
  final note = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('材料备注'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 2000,
        minLines: 4,
        maxLines: 10,
        decoration: const InputDecoration(hintText: '记录自己的准备情况；不要在这里填写政府表格答案。'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  if (note == null || !context.mounted) return;
  try {
    await ref
        .read(appStoreProvider.notifier)
        .updateChecklistNote(
          projectId: projectId,
          itemId: item.id,
          note: note.trim(),
        );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('备注未保存：$error')));
    }
  }
}

Future<void> _showActivityLog(BuildContext context, VisaProject project) async {
  final activities = [...project.activities]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Text('操作记录', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (activities.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('暂无操作记录')),
              )
            else
              ...activities.map(
                (activity) => ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(activity.message),
                  subtitle: Text(
                    DateFormat('yyyy-MM-dd HH:mm').format(activity.createdAt),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _pickDueDate(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  ChecklistItem item,
) async {
  final selected = await showDatePicker(
    context: context,
    initialDate: item.dueDate ?? DateTime.now().add(const Duration(days: 14)),
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 3650)),
  );
  if (selected == null || !context.mounted) return;
  await _setDates(
    context,
    ref,
    projectId: projectId,
    itemId: item.id,
    dueDate: selected,
  );
}

Future<void> _pickReminder(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  ChecklistItem item,
) async {
  final now = DateTime.now();
  final initial = item.reminderAt ?? now.add(const Duration(days: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 3650)),
  );
  if (date == null || !context.mounted) return;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null || !context.mounted) return;
  final reminder = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  await _setDates(
    context,
    ref,
    projectId: projectId,
    itemId: item.id,
    reminderAt: reminder,
  );
}

Future<void> _clearDueDate(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  ChecklistItem item,
) => _setDates(
  context,
  ref,
  projectId: projectId,
  itemId: item.id,
  clearDueDate: true,
);

Future<void> _clearReminder(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  ChecklistItem item,
) => _setDates(
  context,
  ref,
  projectId: projectId,
  itemId: item.id,
  clearReminderAt: true,
);

Future<void> _setDates(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
  required String itemId,
  DateTime? dueDate,
  DateTime? reminderAt,
  bool clearDueDate = false,
  bool clearReminderAt = false,
}) async {
  try {
    await ref
        .read(appStoreProvider.notifier)
        .setChecklistDates(
          projectId: projectId,
          itemId: itemId,
          dueDate: dueDate,
          reminderAt: reminderAt,
          clearDueDate: clearDueDate,
          clearReminderAt: clearReminderAt,
        );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('日期或提醒未更新：$error')));
    }
  }
}

Future<void> _pickAttachment(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  String itemId,
) async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const [
      'pdf',
      'doc',
      'docx',
      'jpg',
      'jpeg',
      'png',
      'heic',
    ],
  );
  if (picked == null) return;
  try {
    final bytes = await picked.readAsBytes();
    await ref
        .read(appStoreProvider.notifier)
        .addAttachment(
          projectId: projectId,
          itemId: itemId,
          name: picked.name,
          contentType: _contentTypeFor(picked.name),
          bytes: bytes,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存到 App 私有目录')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法添加附件：$error')));
    }
  }
}

Future<void> _openAttachment(
  BuildContext context,
  LocalAttachment attachment,
) async {
  final lower = attachment.name.toLowerCase();
  try {
    if (lower.endsWith('.pdf')) {
      final engine = createPdfDocumentEngine();
      final preflight = await engine.preflight(
        fileName: attachment.name,
        localPath: attachment.localPath,
        byteSize: attachment.byteSize,
      );
      if (!context.mounted) return;
      if (!preflight.canOpen || attachment.localPath == null) {
        throw FormatException(preflight.message);
      }
      await engine.openWorkingCopy(
        sourcePath: attachment.localPath!,
        displayName: attachment.name,
      );
      return;
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      final engine = createDocxDocumentEngine();
      final preflight = await engine.preflight(
        fileName: attachment.name,
        localPath: attachment.localPath,
        byteSize: attachment.byteSize,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${preflight.title}：${preflight.message}')),
      );
      return;
    }
    throw const FormatException('图片附件已安全保存；首发版暂不在 App 内编辑图片');
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法打开附件：$error')));
    }
  }
}

Future<void> _removeAttachment(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  String itemId,
  LocalAttachment attachment,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除这个本机副本？'),
      content: Text(attachment.name),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await ref
        .read(appStoreProvider.notifier)
        .removeAttachment(
          projectId: projectId,
          itemId: itemId,
          attachmentId: attachment.id,
        );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法删除：$error')));
    }
  }
}

Future<void> _uploadAttachment(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  String itemId,
  LocalAttachment attachment,
) async {
  final account = ref.read(appStoreProvider);
  if (account.cloudStorageAllocatedBytes + attachment.byteSize >
      account.cloudStorageBytes) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('云空间不足。你仍可下载、导出或删除已有文件；本机原件不会被锁定。')),
    );
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('上传这个附件？'),
      content: Text(
        '${attachment.name}\n\n文件将上传到此项目的云端隔离区，占用订阅存储空间；'
        '当前剩余约 ${formatBytes(account.cloudStorageRemainingBytes)}。安全扫描通过前不能下载或分享。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('明确上传'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref
        .read(appStoreProvider.notifier)
        .uploadAttachment(
          projectId: projectId,
          itemId: itemId,
          attachmentId: attachment.id,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('上传完成，正在确认安全状态')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('上传失败：$error')));
    }
  }
}

String _contentTypeFor(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (lower.endsWith('.doc')) return 'application/msword';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.heic')) return 'image/heic';
  return 'image/jpeg';
}

IconData _attachmentIcon(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
  if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
    return Icons.description_outlined;
  }
  return Icons.image_outlined;
}

String _attachmentStatusLabel(AttachmentSyncStatus status) => switch (status) {
  AttachmentSyncStatus.localOnly => '仅本机',
  AttachmentSyncStatus.uploading => '正在上传',
  AttachmentSyncStatus.scanning => '安全扫描中',
  AttachmentSyncStatus.available => '云端可用',
  AttachmentSyncStatus.failed => '上传失败',
};

Future<void> _addItem(
  BuildContext context,
  WidgetRef ref,
  String projectId,
) async {
  final controller = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('添加清单项'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '材料名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('添加'),
        ),
      ],
    ),
  );
  if (value != null && value.isNotEmpty) {
    await ref
        .read(appStoreProvider.notifier)
        .addChecklistItem(projectId, value);
  }
}

Future<void> _showShareOptions(
  BuildContext context,
  WidgetRef ref,
  VisaProject project,
) async {
  // 后续流程必须使用项目页的 context：面板自己的 context 在 Navigator.pop 之后会被卸载，
  // 之后任何 context.mounted 判断都会变成 false，操作会被静默跳过。
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.send_outlined),
            title: const Text('直接发送副本'),
            subtitle: const Text('发出后无法远程撤回'),
            onTap: () {
              Navigator.pop(sheetContext);
              _directShare(context, project);
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('创建安全分享入口'),
            subtitle: const Text('需要账号；默认 7 天、访问码、禁止下载'),
            onTap: () {
              Navigator.pop(sheetContext);
              _secureShare(context, ref, project);
            },
          ),
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: const Text('邀请 App 协作者'),
            subtitle: const Text('需要双方登录并明确接受权限'),
            onTap: () {
              Navigator.pop(sheetContext);
              _inviteCollaborator(context, ref, project);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _enableCloudSync(
  BuildContext context,
  WidgetRef ref,
  VisaProject project,
) async {
  final state = ref.read(appStoreProvider);
  if (!state.isSignedIn) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('请先在“我的”页面登录账号')));
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('开启此项目的云同步？'),
      content: const Text(
        '项目名称、申请人、清单、状态和备注将同步到澳洲区域的开发服务。文件不会因登录自动上传；本操作同时允许你随后主动选择文件上传。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('暂不开启'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('明确开启'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(appStoreProvider.notifier).enableCloudSync(project.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('项目云同步已开启')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法开启云同步：$error')));
    }
  }
}

Future<void> _directShare(BuildContext context, VisaProject project) async {
  // 本机文件通过系统分享面板直接发出。只有已经复制进 App 私有目录的附件可选，
  // 网页预览不保存敏感附件，因此那里这一节为空。
  final localFiles = [
    for (final item in project.items)
      for (final attachment in item.attachments)
        if (attachment.localPath != null) (item: item, attachment: attachment),
  ];
  final selected = <String>{};
  final selectedFiles = <String>{};
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('选择直接发送的内容'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text('默认不选择任何内容。发送后无法撤回或阻止对方复制。'),
              const SizedBox(height: 12),
              Text('材料清单', style: Theme.of(context).textTheme.labelLarge),
              ...project.items.map(
                (item) => CheckboxListTile(
                  value: selected.contains(item.id),
                  title: Text(item.title),
                  subtitle: Text(item.status.label),
                  onChanged: (value) => setState(() {
                    if (value == true) {
                      selected.add(item.id);
                    } else {
                      selected.remove(item.id);
                    }
                  }),
                ),
              ),
              const Divider(),
              Text('本机文件', style: Theme.of(context).textTheme.labelLarge),
              if (localFiles.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('这个项目还没有保存在本机的附件。'),
                )
              else
                ...localFiles.map(
                  (entry) => CheckboxListTile(
                    value: selectedFiles.contains(entry.attachment.id),
                    title: Text(entry.attachment.name),
                    subtitle: Text(
                      '${entry.item.title} · ${formatBytes(entry.attachment.byteSize)}',
                    ),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        selectedFiles.add(entry.attachment.id);
                      } else {
                        selectedFiles.remove(entry.attachment.id);
                      }
                    }),
                  ),
                ),
              if (selectedFiles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '你正在直接发出 ${selectedFiles.length} 个材料文件的副本。'
                    '对方可以永久保存这些文件，你无法远程收回。',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: selected.isEmpty && selectedFiles.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('确认并发送副本'),
          ),
        ],
      ),
    ),
  );
  if (accepted != true) return;
  final lines = project.items
      .where((item) => selected.contains(item.id))
      .map((item) => '• ${item.title}：${item.status.label}')
      .join('\n');
  final files = [
    for (final entry in localFiles)
      if (selectedFiles.contains(entry.attachment.id))
        XFile(
          entry.attachment.localPath!,
          name: entry.attachment.name,
          mimeType: entry.attachment.contentType,
        ),
  ];
  await SharePlus.instance.share(
    ShareParams(
      text: lines.isEmpty
          ? '${project.name}\n\n此副本发出后无法由发送者远程撤回。'
          : '${project.name}\n$lines\n\n此副本发出后无法由发送者远程撤回。',
      files: files,
    ),
  );
}

Future<void> _secureShare(
  BuildContext context,
  WidgetRef ref,
  VisaProject project,
) async {
  if (!ref.read(appStoreProvider).isSignedIn) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('请先登录账号')));
    return;
  }
  if (!project.isCloudSyncEnabled) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('请先明确开启此项目的云同步')));
    return;
  }
  // 只有通过安全扫描的云文件才能进入分享范围；读不到清单时仍可只分享清单项，
  // 但必须明确显示原因，不能让用户以为这个项目没有云文件。
  var cloudFiles = const <Map<String, dynamic>>[];
  String? cloudFilesError;
  try {
    cloudFiles =
        (await ref.read(appStoreProvider.notifier).listCloudFiles(project.id))
            .where((file) => file['scanStatus'] == 'CLEAN')
            .toList();
  } catch (error) {
    cloudFilesError = '$error';
  }
  if (!context.mounted) return;

  final selected = <String>{};
  final selectedFiles = <String>{};
  final code = TextEditingController(text: _randomAccessCode());
  var expiry = 7;
  var allowDownload = false;
  var includeNotes = false;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('创建安全分享入口'),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text('默认不选择内容、7 天有效、需要访问码、禁止下载。截屏和二次复制无法远程收回。'),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: expiry,
                decoration: const InputDecoration(labelText: '有效期'),
                items: const [1, 7, 14, 30]
                    .map(
                      (days) =>
                          DropdownMenuItem(value: days, child: Text('$days 天')),
                    )
                    .toList(),
                onChanged: (value) => setState(() => expiry = value ?? 7),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: code,
                decoration: const InputDecoration(labelText: '访问码（至少 8 位）'),
                onChanged: (_) => setState(() {}),
              ),
              CheckboxListTile(
                value: includeNotes,
                title: const Text('包含所选材料的备注'),
                onChanged: (value) =>
                    setState(() => includeNotes = value ?? false),
              ),
              CheckboxListTile(
                value: allowDownload,
                title: const Text('允许下载文件副本'),
                subtitle: const Text('下载后的副本无法撤回'),
                onChanged: (value) =>
                    setState(() => allowDownload = value ?? false),
              ),
              const Divider(),
              Text('材料清单', style: Theme.of(context).textTheme.labelLarge),
              ...project.items.map(
                (item) => CheckboxListTile(
                  value: selected.contains(item.id),
                  title: Text(item.title),
                  subtitle: Text(item.status.label),
                  onChanged: (value) => setState(() {
                    if (value == true) {
                      selected.add(item.id);
                    } else {
                      selected.remove(item.id);
                    }
                  }),
                ),
              ),
              const Divider(),
              Text('云端文件', style: Theme.of(context).textTheme.labelLarge),
              if (cloudFilesError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '无法读取云文件清单（$cloudFilesError）。可以只分享清单项，稍后再补充文件。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else if (cloudFiles.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('这个项目还没有通过安全扫描的云文件。'),
                )
              else
                ...cloudFiles.map(
                  (file) => CheckboxListTile(
                    value: selectedFiles.contains(file['id']),
                    title: Text(file['originalName'] as String? ?? '未命名文件'),
                    subtitle: Text(
                      '${formatBytes(int.tryParse(file['byteSize']?.toString() ?? '') ?? 0)} · 扫描通过',
                    ),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        selectedFiles.add(file['id'] as String);
                      } else {
                        selectedFiles.remove(file['id'] as String);
                      }
                    }),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed:
                (selected.isEmpty && selectedFiles.isEmpty) ||
                    code.text.length < 8
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('创建'),
          ),
        ],
      ),
    ),
  );
  if (accepted != true || !context.mounted) return;
  try {
    final share = await ref
        .read(appStoreProvider.notifier)
        .createSecureShare(
          projectId: project.id,
          checklistItemIds: selected.toList(),
          fileIds: selectedFiles.toList(),
          accessCode: code.text,
          expiresInDays: expiry,
          allowDownload: allowDownload,
          includeNotes: includeNotes,
        );
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('安全入口已创建'),
        content: SelectableText(
          '链接：${share['url']}\n\n访问码：${share['accessCode']}\n\n请尽量通过不同渠道发送链接和访问码。',
        ),
        actions: [
          // 复制访问码后必须能直接关闭；否则用户只剩“发送链接”一条出路。
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: share['accessCode'] as String),
              );
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('访问码已复制')));
            },
            child: const Text('复制访问码'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              SharePlus.instance.share(
                ShareParams(text: share['url'] as String),
              );
            },
            child: const Text('发送链接'),
          ),
        ],
      ),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('创建失败：$error')));
    }
  }
}

Future<void> _inviteCollaborator(
  BuildContext context,
  WidgetRef ref,
  VisaProject project,
) async {
  if (!ref.read(appStoreProvider).isSignedIn || !project.isCloudSyncEnabled) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('请先登录并开启项目云同步')));
    return;
  }
  final email = TextEditingController();
  var role = 'VIEWER';
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('邀请 App 协作者'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: '对方登录邮箱'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: '权限'),
              items: const [
                DropdownMenuItem(value: 'VIEWER', child: Text('仅查看')),
                DropdownMenuItem(value: 'COLLABORATOR', child: Text('可协作')),
              ],
              onChanged: (value) => setState(() => role = value ?? 'VIEWER'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('创建邀请'),
          ),
        ],
      ),
    ),
  );
  if (accepted != true || !context.mounted) return;
  try {
    final invitation = await ref
        .read(appStoreProvider.notifier)
        .inviteCollaborator(
          projectId: project.id,
          email: email.text,
          role: role,
        );
    await SharePlus.instance.share(
      ShareParams(
        text:
            '${project.name} 邀请\n${invitation['url']}\n请使用 ${email.text.trim()} 登录后接受。',
      ),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('邀请失败：$error')));
    }
  }
}

String _randomAccessCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(
    12,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

Future<void> _exportBackup(
  BuildContext context,
  WidgetRef ref,
  VisaProject project,
) async {
  final password = await _askBackupPassword(context, confirm: true);
  if (password == null || !context.mounted) return;
  late final Uint8List encrypted;
  try {
    final payload = await ref
        .read(appStoreProvider.notifier)
        .buildProjectBackup(project.id);
    encrypted = await BackupCodec.encrypt(payload, password);
  } on FormatException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
    return;
  }
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          encrypted,
          mimeType: 'application/octet-stream',
          name:
              '${project.name.replaceAll(RegExp(r'[^\w\u4e00-\u9fff-]'), '_')}.mcbackup',
        ),
      ],
      subject: '${project.name} 加密备份',
    ),
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('加密备份已生成；请把口令与文件分开保存')));
  }
}

Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
  final result = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['mcbackup'],
  );
  if (result == null || !context.mounted) return;
  final bytes = await result.readAsBytes();
  if (!context.mounted) return;
  final password = await _askBackupPassword(context);
  if (password == null || !context.mounted) return;
  try {
    final payload = await BackupCodec.decrypt(bytes, password);
    await ref.read(appStoreProvider.notifier).importProjectBackup(payload);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('项目备份已恢复')));
    }
  } on FormatException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

Future<String?> _askBackupPassword(
  BuildContext context, {
  bool confirm = false,
}) async {
  final password = TextEditingController();
  final repeated = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(confirm ? '设置备份口令' : '输入备份口令'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: '至少 10 个字符'),
          ),
          if (confirm) ...[
            const SizedBox(height: 12),
            TextField(
              controller: repeated,
              obscureText: true,
              decoration: const InputDecoration(labelText: '再次输入'),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            '我们无法找回遗忘的备份口令。请把口令与备份文件分开保存。',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (password.text.length < 10 ||
                (confirm && password.text != repeated.text)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请使用至少 10 个字符，并确认两次输入一致')),
              );
              return;
            }
            Navigator.pop(context, password.text);
          },
          child: Text(confirm ? '加密导出' : '恢复'),
        ),
      ],
    ),
  );
}
