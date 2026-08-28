import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/state/app_store.dart';
import '../../shared/widgets/common.dart';

/// 云端管理界面：云文件、安全分享入口和 App 协作。
///
/// 三个页签都直接读服务端。撤销分享、降权成员和删除文件之后，本机缓存会让用户误判
/// 当前权限，因此这里不缓存列表，只在成功后重新拉取。
class ProjectCloudScreen extends ConsumerWidget {
  const ProjectCloudScreen({super.key, required this.projectId});

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
    if (!project.isCloudSyncEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('云端与协作')),
        body: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: '此项目仅保存在本机',
          body: '云文件、安全分享入口和 App 协作都需要先明确开启这个项目的云同步。',
          action: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回项目'),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(project.name),
          bottom: const TabBar(
            tabs: [
              Tab(text: '云文件'),
              Tab(text: '安全分享'),
              Tab(text: '协作'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _CloudFilesTab(project: project),
            _SharesTab(project: project),
            _CollaborationTab(project: project),
          ],
        ),
      ),
    );
  }
}

/// 每个页签共用的“加载 / 失败可重试 / 空状态”骨架。失败必须显示为失败，
/// 不能退回到看起来正常的空列表。
class _RemoteSection<T> extends StatefulWidget {
  const _RemoteSection({
    super.key,
    required this.load,
    required this.builder,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 32),
    this.pollWhile,
    this.pollInterval = const Duration(seconds: 3),
  });

  final Future<T> Function() load;
  final Widget Function(
    BuildContext context,
    T data,
    Future<void> Function() reload,
  )
  builder;
  final EdgeInsets padding;
  final bool Function(T data)? pollWhile;
  final Duration pollInterval;

  @override
  State<_RemoteSection<T>> createState() => _RemoteSectionState<T>();
}

class _RemoteSectionState<T> extends State<_RemoteSection<T>> {
  late Future<T> _future;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _future = _loadAndSchedule();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<T> _loadAndSchedule() async {
    final data = await widget.load();
    _pollTimer?.cancel();
    if (mounted && (widget.pollWhile?.call(data) ?? false)) {
      _pollTimer = Timer(widget.pollInterval, () {
        if (!mounted) return;
        setState(() => _future = _loadAndSchedule());
      });
    }
    return data;
  }

  Future<void> _reload() async {
    _pollTimer?.cancel();
    final next = _loadAndSchedule();
    setState(() => _future = next);
    // 刷新失败由 FutureBuilder 呈现为可重试的失败状态，不再抛回调用方，
    // 否则“操作已成功但刷新失败”会被错误地报成操作失败。
    await next.then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Padding(
            padding: widget.padding,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 12),
                Text(
                  '无法读取服务端数据：${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => setState(() => _future = _loadAndSchedule()),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() => _future = _loadAndSchedule()),
          child: ListView(
            padding: widget.padding,
            children: [widget.builder(context, snapshot.data as T, _reload)],
          ),
        );
      },
    );
  }
}

// --- 云文件 ---

class _CloudFilesTab extends ConsumerWidget {
  const _CloudFilesTab({required this.project});

  final VisaProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(appStoreProvider.notifier);
    return _RemoteSection<List<Map<String, dynamic>>>(
      load: () => store.refreshCloudFileStatuses(project.id),
      pollWhile: (files) => files.any(
        (file) => (file['scanStatus'] as String? ?? 'PENDING') == 'PENDING',
      ),
      builder: (context, files, reload) {
        final state = ref.watch(appStoreProvider);
        if (files.isEmpty && !state.cloudFileUploadsEnabled) {
          return EmptyState(
            icon: Icons.cloud_off_outlined,
            title: '云文件暂未开放',
            body:
                state.cloudFileUploadsDisabledReason ??
                '当前版本的材料文件只保存在你的设备上。记得定期导出加密备份。',
            action: const SizedBox.shrink(),
          );
        }
        if (files.isEmpty) {
          return const EmptyState(
            icon: Icons.cloud_upload_outlined,
            title: '此项目还没有云文件',
            body: '在材料项里逐个选择要上传的文件。上传不会因为登录自动发生。',
            action: SizedBox.shrink(),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '共 ${files.length} 个云文件。只有通过安全扫描的文件才能下载或分享；'
                  '删除云副本不会删除这台设备上的原件。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...files.map(
              (file) => _CloudFileTile(
                project: project,
                file: file,
                onChanged: reload,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CloudFileTile extends ConsumerWidget {
  const _CloudFileTile({
    required this.project,
    required this.file,
    required this.onChanged,
  });

  final VisaProject project;
  final Map<String, dynamic> file;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanStatus = file['scanStatus'] as String? ?? 'PENDING';
    final bytes = int.tryParse(file['byteSize']?.toString() ?? '') ?? 0;
    final linkedItem = project.items
        .where((item) => item.remoteId == file['checklistItemId'])
        .firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              file['originalName'] as String? ?? '未命名文件',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${_scanLabel(scanStatus)} · ${formatBytes(bytes)} · '
              '${_compatibilityLabel(file['compatibility'] as String?)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (linkedItem != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '关联材料项：${linkedItem.title}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (scanStatus == 'REJECTED' || scanStatus == 'ERROR')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  scanStatus == 'REJECTED'
                      ? '安全扫描拒绝了这个文件，云端副本不可用。本机原件未受影响。'
                      : '安全扫描未完成。可以稍后刷新，或删除云副本后重新上传。',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => onChanged(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('刷新状态'),
                ),
                TextButton.icon(
                  onPressed: scanStatus == 'CLEAN'
                      ? () => _download(context, ref)
                      : null,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('下载到 App'),
                ),
                TextButton.icon(
                  onPressed: () => _delete(context, ref),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('删除云副本'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appStoreProvider.notifier)
          .downloadCloudFile(
            projectId: project.id,
            fileId: file['id'] as String,
          );
      messenger.showSnackBar(const SnackBar(content: Text('已下载到 App 私有目录')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('下载失败：$error')));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个云端副本？'),
        content: const Text(
          '云端副本会被立即删除，引用它的安全分享将不再返回这个文件。'
          '这台设备上的原件不受影响。已经被他人下载的副本无法收回。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除云副本'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appStoreProvider.notifier)
          .deleteCloudFile(projectId: project.id, fileId: file['id'] as String);
      await onChanged();
      messenger.showSnackBar(const SnackBar(content: Text('云端副本已删除')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }
}

// --- 安全分享 ---

class _SharesTab extends ConsumerWidget {
  const _SharesTab({required this.project});

  final VisaProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(appStoreProvider.notifier);
    return _RemoteSection<List<Map<String, dynamic>>>(
      load: () => store.listShares(project.id),
      builder: (context, shares, reload) {
        if (shares.isEmpty) {
          return const EmptyState(
            icon: Icons.link_off_outlined,
            title: '还没有安全分享入口',
            body: '在项目页的分享菜单里创建。默认 7 天有效、需要访问码、禁止下载。',
            action: SizedBox.shrink(),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '链接和访问码只在创建时显示一次，之后无法再读取。'
                  '撤销会立即阻止后续访问，但无法收回对方已经保存或截屏的内容。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...shares.map(
              (share) =>
                  _ShareTile(project: project, share: share, onChanged: reload),
            ),
          ],
        );
      },
    );
  }
}

class _ShareTile extends ConsumerWidget {
  const _ShareTile({
    required this.project,
    required this.share,
    required this.onChanged,
  });

  final VisaProject project;
  final Map<String, dynamic> share;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final status = share['status'] as String? ?? 'ACTIVE';
    final scope = share['scope'] as Map<String, dynamic>? ?? const {};
    final itemCount =
        (scope['checklistItemIds'] as List<dynamic>? ?? const []).length;
    final fileCount = (scope['fileIds'] as List<dynamic>? ?? const []).length;
    final lastAccessedAt = share['lastAccessedAt'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: switch (status) {
                      'ACTIVE' => scheme.primaryContainer,
                      'EXPIRED' => scheme.surfaceContainerHighest,
                      _ => scheme.errorContainer,
                    },
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    _shareStatusLabel(status),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  share['allowDownload'] == true ? '允许下载' : '禁止下载',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('内容：$itemCount 个清单项、$fileCount 个文件'),
            Text(
              '到期：${_formatDateTime(share['expiresAt'] as String?)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              lastAccessedAt == null
                  ? '尚未被访问'
                  : '最近访问：${_formatDateTime(lastAccessedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: status == 'ACTIVE'
                    ? () => _revoke(context, ref)
                    : null,
                icon: const Icon(Icons.block_outlined, size: 18),
                label: const Text('立即撤销'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('立即撤销这个入口？'),
        content: const Text('撤销后，持有链接和访问码的人无法再访问。已经下载或截屏的副本无法收回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appStoreProvider.notifier)
          .revokeShare(projectId: project.id, shareId: share['id'] as String);
      await onChanged();
      messenger.showSnackBar(const SnackBar(content: Text('分享入口已撤销')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('撤销失败：$error')));
    }
  }
}

// --- 协作 ---

class _CollaborationTab extends ConsumerWidget {
  const _CollaborationTab({required this.project});

  final VisaProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(appStoreProvider.notifier);
    return _RemoteSection<_CollaborationData>(
      load: () async {
        final results = await Future.wait([
          store.fetchCollaboration(project.id),
          store.listComments(project.id),
        ]);
        return _CollaborationData(
          collaborators:
              ((results[0] as Map<String, dynamic>)['collaborators']
                          as List<dynamic>? ??
                      const [])
                  .cast<Map<String, dynamic>>(),
          invitations:
              ((results[0] as Map<String, dynamic>)['invitations']
                          as List<dynamic>? ??
                      const [])
                  .cast<Map<String, dynamic>>(),
          comments: results[1] as List<Map<String, dynamic>>,
        );
      },
      builder: (context, data, reload) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: '成员'),
            ...data.collaborators.map(
              (member) => _MemberTile(
                project: project,
                member: member,
                onChanged: reload,
              ),
            ),
            const SectionHeader(title: '待接受的邀请'),
            if (data.invitations.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('没有待接受的邀请。'),
                ),
              )
            else
              ...data.invitations.map(
                (invitation) => _InvitationTile(
                  project: project,
                  invitation: invitation,
                  onChanged: reload,
                ),
              ),
            const SectionHeader(title: '项目讨论'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '讨论只用于协调材料准备。不要在这里填写证件号码、访问码或政府表格答案。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (data.comments.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('还没有讨论内容。'),
                ),
              )
            else
              ...data.comments.map(
                (comment) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(comment['body'] as String? ?? ''),
                    subtitle: Text(
                      '${(comment['author'] as Map<String, dynamic>?)?['email'] ?? '成员'} · '
                      '${_formatDateTime(comment['createdAt'] as String?)}',
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => _addComment(context, ref, reload),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('发表讨论'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addComment(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() reload,
  ) async {
    final controller = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发表讨论'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 2000,
          decoration: const InputDecoration(hintText: '例如：工作证明已经补齐第二页'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('发表'),
          ),
        ],
      ),
    );
    if (submitted != true || controller.text.trim().isEmpty) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appStoreProvider.notifier)
          .addComment(projectId: project.id, body: controller.text.trim());
      await reload();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('发表失败：$error')));
    }
  }
}

class _CollaborationData {
  const _CollaborationData({
    required this.collaborators,
    required this.invitations,
    required this.comments,
  });

  final List<Map<String, dynamic>> collaborators;
  final List<Map<String, dynamic>> invitations;
  final List<Map<String, dynamic>> comments;
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.project,
    required this.member,
    required this.onChanged,
  });

  final VisaProject project;
  final Map<String, dynamic> member;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = member['role'] as String? ?? 'VIEWER';
    final accountId = member['accountId'] as String;
    final email =
        (member['account'] as Map<String, dynamic>?)?['email'] as String? ??
        '成员';
    final accepted = member['acceptedAt'] != null;
    final isOwner = role == 'OWNER';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${_roleLabel(role)}${accepted ? '' : ' · 尚未接受'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (isOwner)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '所有权不能通过邀请或角色调整转移。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _changeRole(
                      context,
                      ref,
                      accountId,
                      role == 'VIEWER' ? 'COLLABORATOR' : 'VIEWER',
                    ),
                    child: Text(role == 'VIEWER' ? '设为可协作' : '降为仅查看'),
                  ),
                  TextButton(
                    onPressed: () => _remove(context, ref, accountId, email),
                    child: const Text('移除成员'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeRole(
    BuildContext context,
    WidgetRef ref,
    String accountId,
    String role,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appStoreProvider.notifier)
          .updateCollaboratorRole(
            projectId: project.id,
            accountId: accountId,
            role: role,
          );
      await onChanged();
      messenger.showSnackBar(const SnackBar(content: Text('权限已更新')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('更新失败：$error')));
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    String accountId,
    String email,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除这位成员？'),
        content: Text(
          '$email 将立即失去访问权限，无法再读取此项目的最新内容。'
          '对方此前导出或下载的副本无法远程收回。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appStoreProvider.notifier)
          .removeCollaborator(projectId: project.id, accountId: accountId);
      await onChanged();
      messenger.showSnackBar(const SnackBar(content: Text('成员已移除')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('移除失败：$error')));
    }
  }
}

class _InvitationTile extends ConsumerWidget {
  const _InvitationTile({
    required this.project,
    required this.invitation,
    required this.onChanged,
  });

  final VisaProject project;
  final Map<String, dynamic> invitation;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(invitation['email'] as String? ?? ''),
        subtitle: Text(
          '${_roleLabel(invitation['role'] as String? ?? 'VIEWER')} · '
          '到期 ${_formatDateTime(invitation['expiresAt'] as String?)}',
        ),
        trailing: TextButton(
          onPressed: () => _revoke(context, ref),
          child: const Text('撤销邀请'),
        ),
      ),
    );
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appStoreProvider.notifier)
          .revokeInvitation(
            projectId: project.id,
            invitationId: invitation['id'] as String,
          );
      await onChanged();
      messenger.showSnackBar(const SnackBar(content: Text('邀请已撤销')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('撤销失败：$error')));
    }
  }
}

// --- 展示辅助 ---

String _roleLabel(String role) => switch (role) {
  'OWNER' => '所有者',
  'COLLABORATOR' => '可协作',
  _ => '仅查看',
};

String _shareStatusLabel(String status) => switch (status) {
  'ACTIVE' => '有效',
  'EXPIRED' => '已过期',
  _ => '已撤销',
};

String _scanLabel(String status) => switch (status) {
  'CLEAN' => '扫描通过',
  'REJECTED' => '扫描拒绝',
  'ERROR' => '扫描失败',
  _ => '扫描中',
};

String _compatibilityLabel(String? compatibility) => switch (compatibility) {
  'PDF_SUPPORTED' => 'PDF 完全支持',
  'DOCX_REQUIRES_PREFLIGHT' => 'DOCX 需兼容性预检',
  _ => '只读',
};

String _formatDateTime(String? iso) {
  if (iso == null) return '未知';
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return '未知';
  return DateFormat('yyyy年M月d日 HH:mm').format(parsed.toLocal());
}
