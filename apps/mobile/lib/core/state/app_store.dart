import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../data/seed_data.dart';
import '../models/models.dart';
import '../notifications/notification_service.dart';
import '../storage/local_repository.dart';
import '../storage/attachment_storage.dart';

class AppState {
  const AppState({
    required this.news,
    required this.changes,
    required this.projects,
    required this.isHydrated,
    this.isSignedIn = false,
    this.accountEmail,
    this.entitlementTier = 'FREE',
    this.trialEndsAt,
    this.cloudStorageBytes = 1024 * 1024 * 1024,
    this.cloudStorageUsedBytes = 0,
    this.cloudStorageReservedBytes = 0,
    this.noticeDismissed = false,
    this.isContentRefreshing = false,
    this.contentError,
    this.contentUpdatedAt,
    this.deletionRequestedAt,
    this.policyNotificationsEnabled = false,
    this.followedJurisdictions = const ['AU-SA'],
    this.followedTags = const [],
    this.importantNotificationsOnly = true,
    this.monitoring,
    this.cloudFileUploadsEnabled = true,
    this.cloudFileUploadsDisabledReason,
  });

  /// 官方页面的监控状态。为空表示还没取到，界面此时不应断言「没有变化」。
  final MonitoringStatus? monitoring;

  /// 服务端是否开放云文件上传。当前阶段材料文件只保存在设备上，云存储待澳洲区域上线后开放。
  /// 由 `/entitlements/me` 下发，避免用户在上传时才撞到失败。
  final bool cloudFileUploadsEnabled;
  final String? cloudFileUploadsDisabledReason;

  final List<NewsItem> news;
  final List<PolicyChange> changes;
  final List<VisaProject> projects;
  final bool isHydrated;
  final bool isSignedIn;
  final String? accountEmail;
  final String entitlementTier;
  final DateTime? trialEndsAt;
  final int cloudStorageBytes;
  final int cloudStorageUsedBytes;
  final int cloudStorageReservedBytes;
  final bool noticeDismissed;
  final bool isContentRefreshing;
  final String? contentError;
  final DateTime? contentUpdatedAt;
  final DateTime? deletionRequestedAt;
  final bool policyNotificationsEnabled;
  final List<String> followedJurisdictions;
  final List<String> followedTags;
  final bool importantNotificationsOnly;

  int get cloudStorageAllocatedBytes =>
      cloudStorageUsedBytes + cloudStorageReservedBytes;

  bool get isCloudStorageOverLimit =>
      cloudStorageAllocatedBytes >= cloudStorageBytes;

  int get cloudStorageRemainingBytes => isCloudStorageOverLimit
      ? 0
      : cloudStorageBytes - cloudStorageAllocatedBytes;

  AppState copyWith({
    List<NewsItem>? news,
    List<PolicyChange>? changes,
    List<VisaProject>? projects,
    bool? isHydrated,
    bool? isSignedIn,
    String? accountEmail,
    bool clearAccountEmail = false,
    String? entitlementTier,
    DateTime? trialEndsAt,
    bool clearTrialEndsAt = false,
    int? cloudStorageBytes,
    int? cloudStorageUsedBytes,
    int? cloudStorageReservedBytes,
    bool? noticeDismissed,
    bool? isContentRefreshing,
    String? contentError,
    bool clearContentError = false,
    DateTime? contentUpdatedAt,
    bool clearContentUpdatedAt = false,
    DateTime? deletionRequestedAt,
    bool clearDeletionRequestedAt = false,
    bool? policyNotificationsEnabled,
    List<String>? followedJurisdictions,
    List<String>? followedTags,
    bool? importantNotificationsOnly,
    MonitoringStatus? monitoring,
    bool? cloudFileUploadsEnabled,
    String? cloudFileUploadsDisabledReason,
    bool clearCloudFileUploadsDisabledReason = false,
  }) => AppState(
    news: news ?? this.news,
    changes: changes ?? this.changes,
    projects: projects ?? this.projects,
    isHydrated: isHydrated ?? this.isHydrated,
    isSignedIn: isSignedIn ?? this.isSignedIn,
    accountEmail: clearAccountEmail ? null : accountEmail ?? this.accountEmail,
    entitlementTier: entitlementTier ?? this.entitlementTier,
    trialEndsAt: clearTrialEndsAt ? null : trialEndsAt ?? this.trialEndsAt,
    cloudStorageBytes: cloudStorageBytes ?? this.cloudStorageBytes,
    cloudStorageUsedBytes: cloudStorageUsedBytes ?? this.cloudStorageUsedBytes,
    cloudStorageReservedBytes:
        cloudStorageReservedBytes ?? this.cloudStorageReservedBytes,
    noticeDismissed: noticeDismissed ?? this.noticeDismissed,
    isContentRefreshing: isContentRefreshing ?? this.isContentRefreshing,
    contentError: clearContentError ? null : contentError ?? this.contentError,
    contentUpdatedAt: clearContentUpdatedAt
        ? null
        : contentUpdatedAt ?? this.contentUpdatedAt,
    deletionRequestedAt: clearDeletionRequestedAt
        ? null
        : deletionRequestedAt ?? this.deletionRequestedAt,
    policyNotificationsEnabled:
        policyNotificationsEnabled ?? this.policyNotificationsEnabled,
    followedJurisdictions: followedJurisdictions ?? this.followedJurisdictions,
    followedTags: followedTags ?? this.followedTags,
    importantNotificationsOnly:
        importantNotificationsOnly ?? this.importantNotificationsOnly,
    monitoring: monitoring ?? this.monitoring,
    cloudFileUploadsEnabled:
        cloudFileUploadsEnabled ?? this.cloudFileUploadsEnabled,
    cloudFileUploadsDisabledReason: clearCloudFileUploadsDisabledReason
        ? null
        : cloudFileUploadsDisabledReason ?? this.cloudFileUploadsDisabledReason,
  );
}

class AppStore extends StateNotifier<AppState> {
  AppStore(
    this._repository, [
    AttachmentStorage? attachmentStorage,
    NotificationService? notificationService,
    ApiClient Function(String accountEmail)? apiClientFactory,
  ]) : _notificationService =
           notificationService ?? createNotificationService(),
       _attachmentStorage = attachmentStorage ?? createAttachmentStorage(),
       _apiClientFactory =
           apiClientFactory ??
           ((accountEmail) => ApiClient(accountEmail: accountEmail)),
       super(
         AppState(
           news: SeedData.news,
           changes: SeedData.changes,
           projects: const [],
           isHydrated: false,
         ),
       ) {
    ready = _hydrate();
  }

  static const _projectsKey = 'migration_companion.projects.v1';
  static const _accountEmailKey = 'migration_companion.account_email.v1';
  static const _authTokenKey = 'migration_companion.auth_token.v1';
  static const _noticeKey = 'migration_companion.notice_dismissed.v1';
  static const _bookmarksKey = 'migration_companion.bookmarks.v1';
  static const _contentCacheKey = 'migration_companion.content_cache.v1';
  static const _pendingSyncKey = 'migration_companion.pending_sync.v1';
  final _uuid = const Uuid();
  final List<PendingSyncOperation> _pendingSyncOperations = [];
  final LocalRepository _repository;
  final AttachmentStorage _attachmentStorage;
  final NotificationService _notificationService;

  /// 完成本机状态恢复。测试和启动期流程可等待它，避免和异步 hydrate 竞争。
  late final Future<void> ready;

  /// 所有服务端调用都经过这个工厂，测试可以注入带 mock 传输层的客户端。
  final ApiClient Function(String accountEmail) _apiClientFactory;
  String? _accessToken;

  ApiClient _api(String accountEmail) {
    final client = _apiClientFactory(accountEmail);
    client.accessToken = _accessToken;
    return client;
  }

  List<PendingSyncOperation> get pendingSyncOperations =>
      List.unmodifiable(_pendingSyncOperations);

  Future<void> _hydrate() async {
    final raw = await _repository.read(_projectsKey);
    var projects = raw == null
        ? <VisaProject>[]
        : (jsonDecode(raw) as List<dynamic>)
              .map((item) => VisaProject.fromJson(item as Map<String, dynamic>))
              .toList();
    final pendingRaw = await _repository.read(_pendingSyncKey);
    if (pendingRaw != null) {
      try {
        _pendingSyncOperations
          ..clear()
          ..addAll(
            (jsonDecode(pendingRaw) as List<dynamic>).map(
              (item) =>
                  PendingSyncOperation.fromJson(item as Map<String, dynamic>),
            ),
          );
      } catch (_) {
        _pendingSyncOperations.clear();
      }
    }
    projects = projects.map((project) {
      final pendingCount = _pendingSyncOperations
          .where((operation) => operation.projectId == project.id)
          .length;
      if (pendingCount == 0) return project;
      return project.copyWith(
        pendingSyncCount: pendingCount,
        syncStatus: project.syncStatus == ProjectSyncStatus.conflict
            ? ProjectSyncStatus.conflict
            : ProjectSyncStatus.pending,
      );
    }).toList();
    final accountEmail = await _repository.read(_accountEmailKey);
    _accessToken = await _repository.read(_authTokenKey);
    final bookmarksRaw = await _repository.read(_bookmarksKey);
    final bookmarks = bookmarksRaw == null
        ? <String>{}
        : (jsonDecode(bookmarksRaw) as List<dynamic>).cast<String>().toSet();
    final cachedContentRaw = await _repository.read(_contentCacheKey);
    var hydratedNews = state.news;
    var hydratedChanges = state.changes;
    DateTime? contentUpdatedAt;
    if (cachedContentRaw != null) {
      try {
        final cached = jsonDecode(cachedContentRaw) as Map<String, dynamic>;
        hydratedNews = (cached['news'] as List<dynamic>? ?? const [])
            .map((item) => NewsItem.fromJson(item as Map<String, dynamic>))
            .toList();
        hydratedChanges = (cached['changes'] as List<dynamic>? ?? const [])
            .map((item) => PolicyChange.fromJson(item as Map<String, dynamic>))
            .toList();
        contentUpdatedAt = DateTime.tryParse(
          cached['updatedAt']?.toString() ?? '',
        );
      } catch (_) {
        // 损坏的内容缓存不会阻塞本机项目；下一次联网刷新会覆盖它。
      }
    }
    state = state.copyWith(
      news: hydratedNews
          .map((item) => item.copyWith(bookmarked: bookmarks.contains(item.id)))
          .toList(),
      changes: hydratedChanges,
      projects: projects,
      isSignedIn: accountEmail != null,
      accountEmail: accountEmail,
      noticeDismissed: await _repository.read(_noticeKey) == 'true',
      contentUpdatedAt: contentUpdatedAt,
      isHydrated: true,
    );
    if (accountEmail != null) {
      try {
        await refreshAccount();
        await refreshEntitlements();
        await refreshNotificationPreferences();
      } catch (_) {
        // Offline use remains available. The profile screen can retry explicitly.
      }
    }
  }

  Future<void> _persistProjects() async {
    await _repository.write(
      _projectsKey,
      jsonEncode(state.projects.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _persistSyncQueue() async {
    await _repository.write(
      _pendingSyncKey,
      jsonEncode(
        _pendingSyncOperations.map((operation) => operation.toJson()).toList(),
      ),
    );
  }

  Future<void> _enqueueChecklistUpdate({
    required String projectId,
    required String itemId,
    required ChecklistStatus status,
    required String note,
    required DateTime? dueAt,
    required DateTime? reminderAt,
  }) => _enqueueSyncOperation(
    PendingSyncOperation(
      id: _uuid.v4(),
      projectId: projectId,
      itemId: itemId,
      kind: SyncOperationKind.updateChecklist,
      createdAt: DateTime.now(),
      status: status,
      note: note,
      dueAt: dueAt,
      reminderAt: reminderAt,
    ),
  );

  Future<void> _enqueueSyncOperation(PendingSyncOperation operation) async {
    _pendingSyncOperations.add(operation);
    final pendingCount = _pendingSyncOperations
        .where((candidate) => candidate.projectId == operation.projectId)
        .length;
    state = state.copyWith(
      projects: state.projects.map((project) {
        if (project.id != operation.projectId) return project;
        return project.copyWith(
          syncStatus: ProjectSyncStatus.pending,
          pendingSyncCount: pendingCount,
          syncMessage: '有 $pendingCount 项本机修改等待同步',
        );
      }).toList(),
    );
    await Future.wait([_persistProjects(), _persistSyncQueue()]);
  }

  Future<void> _tryFlushProject(String projectId) async {
    final email = state.accountEmail;
    if (email == null) return;
    var project = state.projects.firstWhere(
      (candidate) => candidate.id == projectId,
    );
    if (!project.isCloudSyncEnabled || project.remoteId == null) return;
    if (project.syncStatus == ProjectSyncStatus.conflict) return;
    final api = _api(email);

    while (true) {
      final operation = _pendingSyncOperations
          .where((candidate) => candidate.projectId == projectId)
          .firstOrNull;
      if (operation == null) break;
      project = state.projects.firstWhere(
        (candidate) => candidate.id == projectId,
      );
      final item = project.items
          .where((candidate) => candidate.id == operation.itemId)
          .firstOrNull;
      if (item == null) {
        await _setProjectSyncState(
          projectId,
          ProjectSyncStatus.error,
          '待同步的材料项已不存在，请选择使用云端版本或重新创建。',
        );
        return;
      }
      if (operation.kind == SyncOperationKind.updateChecklist &&
          item.remoteId == null) {
        await _setProjectSyncState(
          projectId,
          ProjectSyncStatus.error,
          '材料项尚未建立云端映射，无法继续同步。',
        );
        return;
      }

      try {
        final response = await api.post(
          '/projects/${project.remoteId}/sync-operations',
          {
            'operationId': operation.id,
            'baseVersion': project.cloudVersion,
            'kind': operation.kind == SyncOperationKind.addChecklist
                ? 'ADD_CHECKLIST'
                : 'UPDATE_CHECKLIST',
            'clientItemId': operation.itemId,
            if (operation.kind == SyncOperationKind.addChecklist) ...{
              'title': operation.title,
              'category': operation.category,
            } else ...{
              'remoteItemId': item.remoteId,
              'status': _serverChecklistStatus(operation.status!),
              'note': operation.note ?? '',
              if (operation.dueAt != null)
                'dueAt': operation.dueAt!.toUtc().toIso8601String()
              else
                'clearDueAt': true,
              if (operation.reminderAt != null)
                'reminderAt': operation.reminderAt!.toUtc().toIso8601String()
              else
                'clearReminderAt': true,
            },
          },
        );
        final remoteItem = response['item'] as Map<String, dynamic>?;
        _pendingSyncOperations.removeWhere(
          (candidate) => candidate.id == operation.id,
        );
        final remaining = _pendingSyncOperations
            .where((candidate) => candidate.projectId == projectId)
            .length;
        state = state.copyWith(
          projects: state.projects.map((candidate) {
            if (candidate.id != projectId) return candidate;
            return candidate.copyWith(
              items: remoteItem == null
                  ? candidate.items
                  : candidate.items
                        .map(
                          (candidateItem) =>
                              candidateItem.id == operation.itemId
                              ? candidateItem.copyWith(
                                  remoteId: remoteItem['id'] as String,
                                )
                              : candidateItem,
                        )
                        .toList(),
              cloudVersion: response['projectVersion'] as int,
              syncStatus: remaining == 0
                  ? ProjectSyncStatus.synced
                  : ProjectSyncStatus.pending,
              pendingSyncCount: remaining,
              syncMessage: remaining == 0 ? null : '还有 $remaining 项本机修改等待同步',
              clearSyncMessage: remaining == 0,
              lastSyncedAt: DateTime.now(),
            );
          }).toList(),
        );
        await Future.wait([_persistProjects(), _persistSyncQueue()]);
      } on ApiException catch (error) {
        if (error.statusCode == 409) {
          final rawMessage = error.details?['message'];
          final serverVersion =
              (rawMessage is Map<String, dynamic>
                  ? rawMessage['serverVersion']
                  : null) ??
              error.details?['serverVersion'];
          await _setProjectSyncState(
            projectId,
            ProjectSyncStatus.conflict,
            serverVersion == null
                ? '云端已有其他修改，请比较差异后选择处理方式。'
                : '云端已更新到版本 $serverVersion，请比较差异后选择处理方式。',
          );
        } else if (error.statusCode == 0 || error.statusCode >= 500) {
          await _setProjectSyncState(
            projectId,
            ProjectSyncStatus.pending,
            '当前离线或服务暂不可用，本机修改已安全排队。',
          );
        } else {
          await _setProjectSyncState(
            projectId,
            ProjectSyncStatus.error,
            '同步被服务端拒绝：${error.message}',
          );
        }
        return;
      }
    }
  }

  Future<void> _setProjectSyncState(
    String projectId,
    ProjectSyncStatus status,
    String message,
  ) async {
    final pendingCount = _pendingSyncOperations
        .where((operation) => operation.projectId == projectId)
        .length;
    state = state.copyWith(
      projects: state.projects.map((project) {
        if (project.id != projectId) return project;
        return project.copyWith(
          syncStatus: status,
          pendingSyncCount: pendingCount,
          syncMessage: message,
        );
      }).toList(),
    );
    await Future.wait([_persistProjects(), _persistSyncQueue()]);
  }

  Future<void> syncProject(String projectId) async {
    final project = _requireCloudProject(projectId);
    if (project.syncStatus == ProjectSyncStatus.conflict) {
      throw const FormatException('请先查看并处理版本冲突');
    }
    await _tryFlushProject(projectId);
    final refreshed = state.projects.firstWhere(
      (candidate) => candidate.id == projectId,
    );
    if (refreshed.pendingSyncCount == 0 &&
        refreshed.syncStatus != ProjectSyncStatus.error) {
      await _pullCloudProject(projectId);
    }
  }

  Future<void> resumeCloudSync() async {
    if (!state.isSignedIn) return;
    try {
      await restoreCloudProjects();
    } catch (_) {
      // 本机项目仍然可用；每个项目的手动同步入口可以再次尝试。
    }
    final projectIds = _pendingSyncOperations
        .map((operation) => operation.projectId)
        .toSet();
    for (final projectId in projectIds) {
      await _tryFlushProject(projectId);
    }
  }

  /// 恢复账号可见的云端项目。带有本机待同步修改的项目不会被静默覆盖。
  Future<void> restoreCloudProjects() async {
    final email = state.accountEmail;
    if (email == null) return;
    final api = _api(email);
    final summaries = await api.getList('/projects');
    for (final summary in summaries.cast<Map<String, dynamic>>()) {
      final remoteId = summary['id'] as String;
      final existing = state.projects
          .where((project) => project.remoteId == remoteId)
          .firstOrNull;
      if (existing != null &&
          (existing.pendingSyncCount > 0 ||
              existing.syncStatus == ProjectSyncStatus.conflict)) {
        continue;
      }
      final remote = await api.getMap('/projects/$remoteId');
      final restored = _projectFromRemote(remote, existing: existing);
      state = state.copyWith(
        projects: [
          ...state.projects.where((project) => project.id != restored.id),
          restored,
        ],
      );
    }
    await _persistProjects();
  }

  Future<void> _pullCloudProject(String projectId) async {
    final project = _requireCloudProject(projectId);
    final remote = await _requireApi().getMap('/projects/${project.remoteId}');
    final restored = _projectFromRemote(remote, existing: project);
    state = state.copyWith(
      projects: state.projects
          .map((candidate) => candidate.id == projectId ? restored : candidate)
          .toList(),
    );
    await _persistProjects();
  }

  /// 返回可向用户展示的字段级差异。备注只报告“不同”，绝不把敏感内容放进摘要。
  Future<List<String>> compareCloudProject(String projectId) async {
    final project = _requireCloudProject(projectId);
    final remote = await _requireApi().getMap('/projects/${project.remoteId}');
    final differences = <String>[];
    if (remote['version'] != project.cloudVersion) {
      differences.add(
        '项目版本：本机 ${project.cloudVersion}，云端 ${remote['version']}',
      );
    }
    final remoteItems = (remote['checklist'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final remoteById = {
      for (final item in remoteItems) item['id'] as String: item,
    };
    for (final item in project.items) {
      if (item.remoteId == null) {
        differences.add('“${item.title}”：仅存在于本机');
        continue;
      }
      final cloud = remoteById.remove(item.remoteId);
      if (cloud == null) {
        differences.add('“${item.title}”：云端已不存在');
        continue;
      }
      final changedFields = <String>[];
      if (_localChecklistStatus(cloud['status'] as String?) != item.status) {
        changedFields.add('状态');
      }
      if ((cloud['note'] as String? ?? '') != item.note) {
        changedFields.add('备注');
      }
      if (!_sameInstant(cloud['dueAt'], item.dueDate)) {
        changedFields.add('目标日期');
      }
      if (!_sameInstant(cloud['reminderAt'], item.reminderAt)) {
        changedFields.add('提醒时间');
      }
      if (changedFields.isNotEmpty) {
        differences.add('“${item.title}”：${changedFields.join('、')}不同');
      }
    }
    for (final cloud in remoteById.values) {
      differences.add('“${cloud['title']}”：仅存在于云端');
    }
    if (differences.isEmpty) differences.add('材料字段没有差异，可以安全重试同步。');
    return differences;
  }

  /// 放弃此项目的排队修改并采用云端元数据；本机附件字节不会被删除。
  Future<void> useCloudProjectVersion(String projectId) async {
    final project = _requireCloudProject(projectId);
    final remote = await _requireApi().getMap('/projects/${project.remoteId}');
    _pendingSyncOperations.removeWhere(
      (operation) => operation.projectId == projectId,
    );
    final restored = _projectFromRemote(
      remote,
      existing: project,
      preserveUnmappedAttachments: true,
    );
    state = state.copyWith(
      projects: state.projects
          .map((candidate) => candidate.id == projectId ? restored : candidate)
          .toList(),
    );
    await Future.wait([_persistProjects(), _persistSyncQueue()]);
  }

  /// 以最新云端版本为基线，按原操作 ID 顺序重放本机排队修改。
  Future<void> keepLocalProjectVersion(String projectId) async {
    final project = _requireCloudProject(projectId);
    final remote = await _requireApi().getMap('/projects/${project.remoteId}');
    state = state.copyWith(
      projects: state.projects.map((candidate) {
        if (candidate.id != projectId) return candidate;
        return candidate.copyWith(
          cloudVersion: remote['version'] as int,
          syncStatus: ProjectSyncStatus.pending,
          syncMessage: '正在把本机修改应用到最新云端版本',
        );
      }).toList(),
    );
    await _persistProjects();
    await _tryFlushProject(projectId);
    final current = state.projects.firstWhere(
      (candidate) => candidate.id == projectId,
    );
    if (current.pendingSyncCount == 0 &&
        current.syncStatus == ProjectSyncStatus.synced) {
      await _pullCloudProject(projectId);
    }
  }

  VisaProject _projectFromRemote(
    Map<String, dynamic> remote, {
    VisaProject? existing,
    bool preserveUnmappedAttachments = false,
  }) {
    final remoteItems = (remote['checklist'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final remoteFiles = (remote['files'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final existingByRemoteId = {
      for (final item in existing?.items ?? const <ChecklistItem>[])
        if (item.remoteId != null) item.remoteId!: item,
    };
    final items = remoteItems.map((cloudItem) {
      final remoteItemId = cloudItem['id'] as String;
      final local = existingByRemoteId[remoteItemId];
      final files = remoteFiles
          .where((file) => file['checklistItemId'] == remoteItemId)
          .toList();
      final existingAttachments =
          local?.attachments ?? const <LocalAttachment>[];
      final existingFiles = {
        for (final attachment in existingAttachments)
          if (attachment.remoteId != null) attachment.remoteId!: attachment,
      };
      final attachments = <LocalAttachment>[
        ...existingAttachments.where(
          (attachment) => attachment.remoteId == null,
        ),
        ...files.map((file) {
          final remoteFileId = file['id'] as String;
          final known = existingFiles[remoteFileId];
          final byteSize = int.tryParse(file['byteSize'].toString()) ?? 0;
          return LocalAttachment(
            id: known?.id ?? 'cloud-$remoteFileId',
            name: file['originalName'] as String? ?? '云端文件',
            contentType:
                file['contentType'] as String? ?? 'application/octet-stream',
            byteSize: byteSize,
            sha256: file['sha256'] as String? ?? '',
            createdAt:
                DateTime.tryParse(file['createdAt']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            localPath: known?.localPath,
            remoteId: remoteFileId,
            syncStatus: _syncStatusFromScan(file['scanStatus'] as String?),
          );
        }),
      ];
      return ChecklistItem(
        id: local?.id ?? _uuid.v4(),
        title: cloudItem['title'] as String? ?? '未命名材料',
        owner: cloudItem['person'] as String? ?? '主申请人',
        category: cloudItem['category'] as String? ?? '其他',
        status: _localChecklistStatus(cloudItem['status'] as String?),
        dueDate: _optionalDate(cloudItem['dueAt']),
        reminderAt: _optionalDate(cloudItem['reminderAt']),
        note: cloudItem['note'] as String? ?? '',
        attachments: attachments,
        remoteId: remoteItemId,
      );
    }).toList();
    if (preserveUnmappedAttachments && existing != null) {
      items.addAll(
        existing.items.where(
          (item) => item.remoteId == null && item.attachments.isNotEmpty,
        ),
      );
    }
    final template = remote['template'] as String? ?? 'BLANK';
    return VisaProject(
      id: existing?.id ?? _uuid.v4(),
      name: remote['name'] as String? ?? existing?.name ?? '云端项目',
      visaType: switch (template) {
        'SA_190' => 'SA 190',
        'SA_491' => 'SA 491',
        _ => existing?.visaType ?? '空白项目',
      },
      applicant:
          remote['applicantName'] as String? ?? existing?.applicant ?? '主申请人',
      status: existing?.status ?? ProjectStatus.active,
      items: items,
      targetDate: _optionalDate(remote['targetDate']),
      // 该对象本身来自账号云端；cloudFilesEnabled 仅表示附件上传授权。
      isCloudSyncEnabled: true,
      allowViewerDownload: remote['allowViewerDownload'] as bool? ?? false,
      remoteId: remote['id'] as String,
      cloudVersion: remote['version'] as int? ?? 1,
      activities: [
        ...(existing?.activities ?? const <ProjectActivity>[]),
        _activity(existing == null ? '从账号恢复了云端项目' : '完成了云端同步'),
      ],
      syncStatus: ProjectSyncStatus.synced,
      pendingSyncCount: 0,
      lastSyncedAt: DateTime.now(),
      cloudRole:
          remote['currentRole'] as String? ?? existing?.cloudRole ?? 'VIEWER',
    );
  }

  Future<void> toggleBookmark(String id) async {
    state = state.copyWith(
      news: state.news
          .map(
            (item) => item.id == id
                ? item.copyWith(bookmarked: !item.bookmarked)
                : item,
          )
          .toList(),
    );
    await _repository.write(
      _bookmarksKey,
      jsonEncode(
        state.news
            .where((item) => item.bookmarked)
            .map((item) => item.id)
            .toList(),
      ),
    );
  }

  Future<void> refreshContent() async {
    if (state.isContentRefreshing) return;
    state = state.copyWith(isContentRefreshing: true, clearContentError: true);
    try {
      final api = _api(
        state.accountEmail ?? 'public@migration-companion.invalid',
      );
      final payloads = await Future.wait([
        api.getList('/content/news'),
        api.getList('/content/changes'),
      ]);
      // 监控状态取不到不应让整次内容刷新失败：拿不到就保持未知，
      // 界面在未知状态下同样不会断言「没有变化」。
      MonitoringStatus? monitoring;
      try {
        monitoring = MonitoringStatus.fromJson(
          await api.getMap('/content/monitoring'),
        );
      } catch (_) {
        monitoring = state.monitoring;
      }
      final bookmarkedIds = state.news
          .where((item) => item.bookmarked)
          .map((item) => item.id)
          .toSet();
      final news = payloads[0]
          .cast<Map<String, dynamic>>()
          .map(
            (item) => _newsFromApi(
              item,
              bookmarked: bookmarkedIds.contains(item['id']),
            ),
          )
          .toList();
      final changes = payloads[1]
          .cast<Map<String, dynamic>>()
          .map(_changeFromApi)
          .toList();
      final updatedAt = DateTime.now().toUtc();
      state = state.copyWith(
        news: news,
        changes: changes,
        monitoring: monitoring,
        isContentRefreshing: false,
        clearContentError: true,
        contentUpdatedAt: updatedAt,
      );
      await _repository.write(
        _contentCacheKey,
        jsonEncode({
          'updatedAt': updatedAt.toIso8601String(),
          'news': news.map((item) => item.toJson()).toList(),
          'changes': changes.map((item) => item.toJson()).toList(),
        }),
      );
    } catch (error) {
      state = state.copyWith(
        isContentRefreshing: false,
        contentError: '无法更新官方内容，当前继续显示本机缓存：$error',
      );
    }
  }

  Future<VisaProject> addProject({
    required String name,
    required String visaType,
    required String applicant,
  }) async {
    final project = VisaProject(
      id: _uuid.v4(),
      name: name,
      visaType: visaType,
      applicant: applicant,
      status: ProjectStatus.active,
      items: SeedData.templateFor(visaType),
      targetDate: DateTime.now().add(const Duration(days: 120)),
      activities: [_activity('创建了项目')],
    );
    state = state.copyWith(projects: [...state.projects, project]);
    await _persistProjects();
    return project;
  }

  Future<void> addChecklistItem(String projectId, String title) async {
    final existingProject = state.projects.firstWhere(
      (project) => project.id == projectId,
    );
    final itemId = _uuid.v4();
    state = state.copyWith(
      projects: state.projects.map((project) {
        if (project.id != projectId) return project;
        return project.copyWith(
          items: [
            ...project.items,
            ChecklistItem(
              id: itemId,
              title: title,
              owner: project.applicant,
              category: '自定义',
              status: ChecklistStatus.notStarted,
            ),
          ],
          activities: [...project.activities, _activity('添加了材料项：$title')],
        );
      }).toList(),
    );
    await _persistProjects();
    if (existingProject.isCloudSyncEnabled &&
        existingProject.remoteId != null) {
      await _enqueueSyncOperation(
        PendingSyncOperation(
          id: _uuid.v4(),
          projectId: projectId,
          itemId: itemId,
          kind: SyncOperationKind.addChecklist,
          createdAt: DateTime.now(),
          title: title,
          category: '自定义',
        ),
      );
      await _tryFlushProject(projectId);
    }
  }

  Future<void> advanceChecklistItem(String projectId, String itemId) async {
    final currentProject = state.projects.firstWhere(
      (project) => project.id == projectId,
    );
    final currentItem = currentProject.items.firstWhere(
      (item) => item.id == itemId,
    );
    final nextStatus = currentItem.status.next;
    state = state.copyWith(
      projects: state.projects.map((project) {
        if (project.id != projectId) return project;
        return project.copyWith(
          items: project.items
              .map(
                (item) => item.id == itemId
                    ? item.copyWith(status: nextStatus)
                    : item,
              )
              .toList(),
          activities: [
            ...project.activities,
            _activity('将“${currentItem.title}”更新为“${nextStatus.label}”'),
          ],
        );
      }).toList(),
    );
    await _persistProjects();
    if (currentProject.isCloudSyncEnabled && currentProject.remoteId != null) {
      await _enqueueChecklistUpdate(
        projectId: projectId,
        itemId: itemId,
        status: nextStatus,
        note: currentItem.note,
        dueAt: currentItem.dueDate,
        reminderAt: currentItem.reminderAt,
      );
      await _tryFlushProject(projectId);
    }
  }

  Future<void> setChecklistDates({
    required String projectId,
    required String itemId,
    DateTime? dueDate,
    DateTime? reminderAt,
    bool clearDueDate = false,
    bool clearReminderAt = false,
  }) async {
    final currentProject = state.projects.firstWhere(
      (project) => project.id == projectId,
    );
    final currentItem = currentProject.items.firstWhere(
      (item) => item.id == itemId,
    );
    final nextDueDate = clearDueDate ? null : dueDate ?? currentItem.dueDate;
    final nextReminder = clearReminderAt
        ? null
        : reminderAt ?? currentItem.reminderAt;
    if (clearReminderAt || nextReminder == null) {
      await _notificationService.cancel('$projectId:$itemId');
    } else {
      await _notificationService.schedule(
        stableId: '$projectId:$itemId',
        at: nextReminder,
        payload: '$projectId:$itemId',
      );
    }
    state = state.copyWith(
      projects: state.projects.map((project) {
        if (project.id != projectId) return project;
        return project.copyWith(
          items: project.items.map((item) {
            if (item.id != itemId) return item;
            return item.copyWith(
              dueDate: nextDueDate,
              clearDueDate: nextDueDate == null,
              reminderAt: nextReminder,
              clearReminderAt: nextReminder == null,
            );
          }).toList(),
          activities: [
            ...project.activities,
            _activity(
              clearReminderAt
                  ? '取消了“${currentItem.title}”的提醒'
                  : reminderAt != null
                  ? '设置了“${currentItem.title}”的提醒'
                  : clearDueDate
                  ? '清除了“${currentItem.title}”的目标日期'
                  : '更新了“${currentItem.title}”的目标日期',
            ),
          ],
        );
      }).toList(),
    );
    await _persistProjects();
    if (currentProject.isCloudSyncEnabled && currentProject.remoteId != null) {
      await _enqueueChecklistUpdate(
        projectId: projectId,
        itemId: itemId,
        status: currentItem.status,
        note: currentItem.note,
        dueAt: nextDueDate,
        reminderAt: nextReminder,
      );
      await _tryFlushProject(projectId);
    }
  }

  Future<LocalAttachment> addAttachment({
    required String projectId,
    required String itemId,
    required String name,
    required String contentType,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) throw const FormatException('文件为空，无法添加');
    if (bytes.length > 50 * 1024 * 1024) {
      throw const FormatException('单个文件不能超过 50 MB');
    }
    final attachmentId = _uuid.v4();
    final localPath = await _attachmentStorage.persist(
      projectId: projectId,
      attachmentId: attachmentId,
      originalName: name,
      bytes: bytes,
    );
    if (localPath == null) {
      throw const FormatException('网页预览不会保存敏感附件；请在 Android 或 iPhone App 中添加');
    }
    final attachment = LocalAttachment(
      id: attachmentId,
      name: name,
      contentType: contentType,
      byteSize: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      createdAt: DateTime.now(),
      localPath: localPath,
    );
    state = state.copyWith(
      projects: state.projects.map((project) {
        if (project.id != projectId) return project;
        return project.copyWith(
          items: project.items.map((item) {
            if (item.id != itemId) return item;
            return item.copyWith(
              attachments: [...item.attachments, attachment],
            );
          }).toList(),
          activities: [...project.activities, _activity('为材料项添加了一个本机附件')],
        );
      }).toList(),
    );
    await _persistProjects();
    return attachment;
  }

  Future<void> removeAttachment({
    required String projectId,
    required String itemId,
    required String attachmentId,
  }) async {
    final project = state.projects.firstWhere(
      (candidate) => candidate.id == projectId,
    );
    final item = project.items.firstWhere(
      (candidate) => candidate.id == itemId,
    );
    final attachment = item.attachments.firstWhere(
      (candidate) => candidate.id == attachmentId,
    );
    if (attachment.remoteId != null) {
      throw const FormatException('云端文件不能从本机静默删除；请先在云文件管理中确认删除');
    }
    await _attachmentStorage.remove(attachment.localPath);
    state = state.copyWith(
      projects: state.projects.map((candidate) {
        if (candidate.id != projectId) return candidate;
        return candidate.copyWith(
          items: candidate.items.map((candidateItem) {
            if (candidateItem.id != itemId) return candidateItem;
            return candidateItem.copyWith(
              attachments: candidateItem.attachments
                  .where(
                    (candidateAttachment) =>
                        candidateAttachment.id != attachmentId,
                  )
                  .toList(),
            );
          }).toList(),
          activities: [...candidate.activities, _activity('删除了一个本机附件')],
        );
      }).toList(),
    );
    await _persistProjects();
  }

  Future<void> uploadAttachment({
    required String projectId,
    required String itemId,
    required String attachmentId,
  }) async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    if (!state.cloudFileUploadsEnabled) {
      throw FormatException(
        state.cloudFileUploadsDisabledReason ?? '云文件上传尚未开放',
      );
    }
    final project = state.projects.firstWhere(
      (candidate) => candidate.id == projectId,
    );
    if (!project.isCloudSyncEnabled || project.remoteId == null) {
      throw const FormatException('请先明确开启此项目的云同步');
    }
    final item = project.items.firstWhere(
      (candidate) => candidate.id == itemId,
    );
    if (item.remoteId == null) throw const FormatException('材料项尚未完成云同步');
    final attachment = item.attachments.firstWhere(
      (candidate) => candidate.id == attachmentId,
    );
    await refreshEntitlements();
    try {
      await refreshNotificationPreferences();
    } catch (_) {
      // 登录本身不依赖推送偏好服务；用户可稍后在“我的”中重试。
    }
    if (state.cloudStorageAllocatedBytes + attachment.byteSize >
        state.cloudStorageBytes) {
      throw const FormatException('云空间不足。你仍可下载、导出或删除已有文件；本机原件不会被锁定。');
    }
    final bytes = await _attachmentStorage.read(attachment.localPath);
    if (bytes == null ||
        sha256.convert(bytes).toString() != attachment.sha256) {
      throw const FormatException('本机附件缺失或校验失败');
    }
    await _updateAttachment(
      projectId,
      itemId,
      attachment.copyWith(syncStatus: AttachmentSyncStatus.uploading),
    );
    var activeAttachment = attachment.copyWith(
      syncStatus: AttachmentSyncStatus.uploading,
    );
    try {
      final api = _api(email);
      Map<String, dynamic>? remote;

      // App 在 PUT 已完成、complete 响应丢失时可能被关闭。只持久化会话 ID，
      // 不保存带签名的短时 URL；重试先完成旧会话，避免重复上传字节。
      if (activeAttachment.uploadSessionId != null &&
          activeAttachment.uploadSessionUploaded) {
        try {
          remote = await api.post(
            '/uploads/${activeAttachment.uploadSessionId}/complete',
            {'checklistItemId': item.remoteId!},
          );
        } on ApiException catch (error) {
          if (error.statusCode != 400 && error.statusCode != 404) rethrow;
          activeAttachment = activeAttachment.copyWith(
            clearUploadSession: true,
          );
          await _updateAttachment(projectId, itemId, activeAttachment);
        }
      }

      if (remote == null) {
        final session = await api.post(
          '/projects/${project.remoteId}/uploads',
          {
            'originalName': activeAttachment.name,
            'contentType': activeAttachment.contentType,
            'byteSize': activeAttachment.byteSize,
            'sha256': activeAttachment.sha256,
            'checklistItemId': item.remoteId!,
          },
        );
        activeAttachment = activeAttachment.copyWith(
          uploadSessionId: session['uploadId'] as String,
          uploadSessionUploaded: false,
          syncStatus: AttachmentSyncStatus.uploading,
        );
        await _updateAttachment(projectId, itemId, activeAttachment);
        final requiredHeaders =
            (session['requiredHeaders'] as Map<String, dynamic>? ??
                    const <String, dynamic>{})
                .map((key, value) => MapEntry(key, value.toString()));
        await api.putSignedUrl(
          session['uploadUrl'] as String,
          bytes,
          headers: requiredHeaders,
        );
        activeAttachment = activeAttachment.copyWith(
          uploadSessionUploaded: true,
        );
        await _updateAttachment(projectId, itemId, activeAttachment);
        remote = await api.post(
          '/uploads/${activeAttachment.uploadSessionId}/complete',
          {'checklistItemId': item.remoteId!},
        );
      }
      final scanStatus = remote['scanStatus'] as String? ?? 'PENDING';
      await _updateAttachment(
        projectId,
        itemId,
        activeAttachment.copyWith(
          remoteId: remote['id'] as String,
          clearUploadSession: true,
          syncStatus: scanStatus == 'CLEAN'
              ? AttachmentSyncStatus.available
              : AttachmentSyncStatus.scanning,
        ),
      );
      await refreshEntitlements();
    } catch (_) {
      await _updateAttachment(
        projectId,
        itemId,
        activeAttachment.copyWith(syncStatus: AttachmentSyncStatus.failed),
      );
      rethrow;
    }
  }

  Future<void> _updateAttachment(
    String projectId,
    String itemId,
    LocalAttachment attachment,
  ) async {
    state = state.copyWith(
      projects: state.projects.map((project) {
        if (project.id != projectId) return project;
        return project.copyWith(
          items: project.items.map((item) {
            if (item.id != itemId) return item;
            return item.copyWith(
              attachments: item.attachments
                  .map(
                    (candidate) =>
                        candidate.id == attachment.id ? attachment : candidate,
                  )
                  .toList(),
            );
          }).toList(),
        );
      }).toList(),
    );
    await _persistProjects();
  }

  Future<void> importProject(VisaProject project) async {
    state = state.copyWith(
      projects: [
        ...state.projects.where((item) => item.id != project.id),
        project,
      ],
    );
    await _persistProjects();
  }

  Future<void> updateChecklistNote({
    required String projectId,
    required String itemId,
    required String note,
  }) async {
    final currentProject = state.projects.firstWhere(
      (project) => project.id == projectId,
    );
    final currentItem = currentProject.items.firstWhere(
      (item) => item.id == itemId,
    );
    state = state.copyWith(
      projects: state.projects.map((project) {
        if (project.id != projectId) return project;
        return project.copyWith(
          items: project.items
              .map(
                (item) => item.id == itemId ? item.copyWith(note: note) : item,
              )
              .toList(),
          activities: [...project.activities, _activity('更新了一个材料项的备注')],
        );
      }).toList(),
    );
    await _persistProjects();
    if (currentProject.isCloudSyncEnabled && currentProject.remoteId != null) {
      await _enqueueChecklistUpdate(
        projectId: projectId,
        itemId: itemId,
        status: currentItem.status,
        note: note,
        dueAt: currentItem.dueDate,
        reminderAt: currentItem.reminderAt,
      );
      await _tryFlushProject(projectId);
    }
  }

  Future<Map<String, Object?>> buildProjectBackup(String projectId) async {
    final project = state.projects.firstWhere(
      (candidate) => candidate.id == projectId,
    );
    final projectJson = project.toJson();
    final attachmentBlobs = <Map<String, Object?>>[];
    final itemJson = projectJson['items']! as List<Map<String, Object?>>;
    for (var itemIndex = 0; itemIndex < project.items.length; itemIndex++) {
      final item = project.items[itemIndex];
      final attachmentsJson =
          itemJson[itemIndex]['attachments']! as List<Map<String, Object?>>;
      for (
        var attachmentIndex = 0;
        attachmentIndex < item.attachments.length;
        attachmentIndex++
      ) {
        final attachment = item.attachments[attachmentIndex];
        attachmentsJson[attachmentIndex]['localPath'] = null;
        final bytes = await _attachmentStorage.read(attachment.localPath);
        if (bytes == null) throw FormatException('找不到附件：${attachment.name}');
        if (sha256.convert(bytes).toString() != attachment.sha256) {
          throw FormatException('附件校验失败：${attachment.name}');
        }
        attachmentBlobs.add({'id': attachment.id, 'data': base64Encode(bytes)});
      }
    }
    return {
      'schema': 'migration-companion-backup/v2',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'project': projectJson,
      'attachmentBlobs': attachmentBlobs,
    };
  }

  Future<void> importProjectBackup(Map<String, dynamic> payload) async {
    final schema = payload['schema'];
    if (schema == 'migration-companion-backup/v1') {
      await importProject(
        VisaProject.fromJson(payload['project'] as Map<String, dynamic>),
      );
      return;
    }
    if (schema != 'migration-companion-backup/v2') {
      throw const FormatException('备份内容版本不受支持');
    }
    final blobs = <String, Uint8List>{};
    for (final raw
        in payload['attachmentBlobs'] as List<dynamic>? ?? const []) {
      final blob = raw as Map<String, dynamic>;
      blobs[blob['id'] as String] = base64Decode(blob['data'] as String);
    }
    final decoded = VisaProject.fromJson(
      payload['project'] as Map<String, dynamic>,
    );
    final restoredItems = <ChecklistItem>[];
    for (final item in decoded.items) {
      final restoredAttachments = <LocalAttachment>[];
      for (final attachment in item.attachments) {
        final bytes = blobs[attachment.id];
        if (bytes == null ||
            sha256.convert(bytes).toString() != attachment.sha256) {
          throw FormatException('附件缺失或校验失败：${attachment.name}');
        }
        final localPath = await _attachmentStorage.persist(
          projectId: decoded.id,
          attachmentId: attachment.id,
          originalName: attachment.name,
          bytes: bytes,
        );
        if (localPath == null) throw const FormatException('当前平台不能恢复附件');
        restoredAttachments.add(
          attachment.copyWith(
            localPath: localPath,
            clearRemoteId: true,
            syncStatus: AttachmentSyncStatus.localOnly,
          ),
        );
      }
      restoredItems.add(
        item.copyWith(attachments: restoredAttachments, clearRemoteId: true),
      );
    }
    await importProject(
      decoded.copyWith(
        items: restoredItems,
        isCloudSyncEnabled: false,
        allowViewerDownload: false,
        clearRemoteId: true,
        cloudVersion: 1,
        activities: [...decoded.activities, _activity('从完整备份恢复到本机；云端引用未导入')],
      ),
    );
  }

  Future<void> enableCloudSync(String projectId) async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    final project = state.projects.firstWhere((item) => item.id == projectId);
    if (project.isCloudSyncEnabled) return;
    final api = _api(email);
    final remote = await api.post('/projects', {
      'name': project.name,
      'template': switch (project.visaType) {
        'SA 190' => 'SA_190',
        'SA 491' => 'SA_491',
        _ => 'BLANK',
      },
      'applicantName': project.applicant,
      if (project.targetDate != null)
        'targetDate': project.targetDate!.toIso8601String(),
    });
    final cloudConsent = await api.patch(
      '/projects/${remote['id']}/cloud-files',
      {'enabled': true},
    );
    var resultingCloudVersion = cloudConsent['version'] as int;
    final remoteItems = (remote['checklist'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final claimed = <String>{};
    final mappedItems = <ChecklistItem>[];
    for (final local in project.items) {
      final match = remoteItems.where((candidate) {
        if (claimed.contains(candidate['id'])) return false;
        return candidate['title'] == local.title;
      }).firstOrNull;
      if (match != null) {
        claimed.add(match['id'] as String);
        mappedItems.add(local.copyWith(remoteId: match['id'] as String));
      } else {
        final created = await api.post('/projects/${remote['id']}/checklist', {
          'title': local.title,
          'category': local.category,
        });
        mappedItems.add(
          local.copyWith(
            remoteId: (created['item'] as Map<String, dynamic>)['id'] as String,
          ),
        );
        resultingCloudVersion = created['projectVersion'] as int;
      }
    }
    state = state.copyWith(
      projects: state.projects.map((candidate) {
        if (candidate.id != projectId) return candidate;
        return candidate.copyWith(
          items: mappedItems,
          isCloudSyncEnabled: true,
          remoteId: remote['id'] as String,
          cloudVersion: resultingCloudVersion,
          syncStatus: ProjectSyncStatus.synced,
          pendingSyncCount: 0,
          clearSyncMessage: true,
          lastSyncedAt: DateTime.now(),
          cloudRole: 'OWNER',
          activities: [...candidate.activities, _activity('明确开启了项目云同步')],
        );
      }).toList(),
    );
    await _persistProjects();
  }

  Future<void> setViewerDownload(String projectId, bool enabled) async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    final project = state.projects.firstWhere(
      (candidate) => candidate.id == projectId,
    );
    if (!project.isCloudSyncEnabled || project.remoteId == null) {
      throw const FormatException('请先开启此项目的云同步');
    }
    final remote = await _api(email).patch(
      '/projects/${project.remoteId}/viewer-download',
      {'enabled': enabled},
    );
    state = state.copyWith(
      projects: state.projects.map((candidate) {
        if (candidate.id != projectId) return candidate;
        return candidate.copyWith(
          allowViewerDownload: remote['allowViewerDownload'] as bool,
          cloudVersion: remote['version'] as int,
          activities: [
            ...candidate.activities,
            _activity(enabled ? '允许仅查看成员下载文件' : '关闭仅查看成员下载权限'),
          ],
        );
      }).toList(),
    );
    await _persistProjects();
  }

  Future<Map<String, dynamic>> createSecureShare({
    required String projectId,
    required List<String> checklistItemIds,
    required String accessCode,
    required int expiresInDays,
    required bool allowDownload,
    required bool includeNotes,
    List<String> fileIds = const [],
  }) async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    final project = state.projects.firstWhere((item) => item.id == projectId);
    if (!project.isCloudSyncEnabled || project.remoteId == null) {
      throw const FormatException('创建安全入口前，请先明确开启此项目的云同步');
    }
    final selectedRemoteIds = project.items
        .where((item) => checklistItemIds.contains(item.id))
        .map((item) => item.remoteId)
        .whereType<String>()
        .toList();
    if (selectedRemoteIds.isEmpty && fileIds.isEmpty) {
      throw const FormatException('请至少选择一项分享内容');
    }
    return _api(email).post('/projects/${project.remoteId}/shares', {
      'expiresInDays': expiresInDays,
      'allowDownload': allowDownload,
      'accessCode': accessCode,
      'checklistItemIds': selectedRemoteIds,
      'fileIds': fileIds,
      'includeNotes': includeNotes,
    });
  }

  Future<Map<String, dynamic>> inviteCollaborator({
    required String projectId,
    required String email,
    required String role,
  }) async {
    final accountEmail = state.accountEmail;
    if (accountEmail == null) throw const FormatException('请先登录账号');
    final project = state.projects.firstWhere((item) => item.id == projectId);
    if (!project.isCloudSyncEnabled || project.remoteId == null) {
      throw const FormatException('邀请协作者前，请先开启此项目的云同步');
    }
    return _api(accountEmail).post(
      '/projects/${project.remoteId}/invitations',
      {'email': email.trim().toLowerCase(), 'role': role},
    );
  }

  // --- 云端管理：安全分享、协作与云文件 ---
  //
  // 这三类数据都是服务端事实，不写入本机项目状态。撤销分享、降权成员和删除云文件之后，
  // 本机缓存会让用户误判当前权限，因此相关界面每次都直接读服务端并显示失败状态。

  ApiClient _requireApi() {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    return _api(email);
  }

  VisaProject _requireCloudProject(String projectId) {
    final project = state.projects.firstWhere((item) => item.id == projectId);
    if (!project.isCloudSyncEnabled || project.remoteId == null) {
      throw const FormatException('请先明确开启此项目的云同步');
    }
    return project;
  }

  Future<List<Map<String, dynamic>>> listShares(String projectId) async {
    final project = _requireCloudProject(projectId);
    final payload = await _requireApi().getList(
      '/projects/${project.remoteId}/shares',
    );
    return payload.cast<Map<String, dynamic>>();
  }

  Future<void> revokeShare({
    required String projectId,
    required String shareId,
  }) async {
    _requireCloudProject(projectId);
    await _requireApi().delete('/shares/$shareId');
    _appendActivity(projectId, '撤销了一个安全分享入口');
    await _persistProjects();
  }

  Future<Map<String, dynamic>> fetchCollaboration(String projectId) async {
    final project = _requireCloudProject(projectId);
    return _requireApi().getMap('/projects/${project.remoteId}/collaboration');
  }

  Future<void> updateCollaboratorRole({
    required String projectId,
    required String accountId,
    required String role,
  }) async {
    final project = _requireCloudProject(projectId);
    await _requireApi().patch(
      '/projects/${project.remoteId}/collaborators/$accountId',
      {'role': role},
    );
    _appendActivity(projectId, role == 'VIEWER' ? '把一位成员降为仅查看' : '把一位成员设为可协作');
    await _persistProjects();
  }

  Future<void> removeCollaborator({
    required String projectId,
    required String accountId,
  }) async {
    final project = _requireCloudProject(projectId);
    await _requireApi().delete(
      '/projects/${project.remoteId}/collaborators/$accountId',
    );
    _appendActivity(projectId, '移除了一位协作成员');
    await _persistProjects();
  }

  Future<void> revokeInvitation({
    required String projectId,
    required String invitationId,
  }) async {
    final project = _requireCloudProject(projectId);
    await _requireApi().delete(
      '/projects/${project.remoteId}/invitations/$invitationId',
    );
    _appendActivity(projectId, '撤销了一个协作邀请');
    await _persistProjects();
  }

  Future<List<Map<String, dynamic>>> listComments(String projectId) async {
    final project = _requireCloudProject(projectId);
    final payload = await _requireApi().getList(
      '/projects/${project.remoteId}/comments',
    );
    return payload.cast<Map<String, dynamic>>();
  }

  Future<void> addComment({
    required String projectId,
    required String body,
  }) async {
    final project = _requireCloudProject(projectId);
    await _requireApi().post('/projects/${project.remoteId}/comments', {
      'body': body,
    });
  }

  Future<List<Map<String, dynamic>>> listCloudFiles(String projectId) async {
    final project = _requireCloudProject(projectId);
    final remote = await _requireApi().getMap('/projects/${project.remoteId}');
    return (remote['files'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
  }

  /// 拉取云文件清单并把扫描状态回写到本机附件；服务端已不存在的文件退回“仅本机”。
  Future<List<Map<String, dynamic>>> refreshCloudFileStatuses(
    String projectId,
  ) async {
    final files = await listCloudFiles(projectId);
    final byRemoteId = {for (final file in files) file['id'] as String: file};
    var changed = false;
    final projects = state.projects.map((project) {
      if (project.id != projectId) return project;
      return project.copyWith(
        items: project.items.map((item) {
          return item.copyWith(
            attachments: item.attachments.map((attachment) {
              final remoteId = attachment.remoteId;
              if (remoteId == null) return attachment;
              final remote = byRemoteId[remoteId];
              if (remote == null) {
                changed = true;
                return attachment.copyWith(
                  clearRemoteId: true,
                  syncStatus: AttachmentSyncStatus.localOnly,
                );
              }
              final status = _syncStatusFromScan(
                remote['scanStatus'] as String?,
              );
              if (status == attachment.syncStatus) return attachment;
              changed = true;
              return attachment.copyWith(syncStatus: status);
            }).toList(),
          );
        }).toList(),
      );
    }).toList();
    if (changed) {
      state = state.copyWith(projects: projects);
      await _persistProjects();
    }
    return files;
  }

  /// 删除的是云端副本；本机原件保留，附件退回“仅本机”。
  Future<void> deleteCloudFile({
    required String projectId,
    required String fileId,
  }) async {
    _requireCloudProject(projectId);
    await _requireApi().delete('/files/$fileId');
    state = state.copyWith(
      projects: state.projects.map((project) {
        if (project.id != projectId) return project;
        return project.copyWith(
          items: project.items
              .map(
                (item) => item.copyWith(
                  attachments: item.attachments
                      .map(
                        (attachment) => attachment.remoteId == fileId
                            ? attachment.copyWith(
                                clearRemoteId: true,
                                syncStatus: AttachmentSyncStatus.localOnly,
                              )
                            : attachment,
                      )
                      .toList(),
                ),
              )
              .toList(),
          activities: [...project.activities, _activity('删除了一个云端文件副本')],
        );
      }).toList(),
    );
    await _persistProjects();
    await refreshEntitlements();
  }

  /// 把云文件下载回 App 私有目录。已知校验值不一致时丢弃下载内容，不覆盖本机原件。
  Future<String> downloadCloudFile({
    required String projectId,
    required String fileId,
  }) async {
    final project = _requireCloudProject(projectId);
    final api = _requireApi();
    final ticket = await api.getMap('/files/$fileId/download');
    final bytes = await api.fetchSignedUrl(ticket['downloadUrl'] as String);
    final digest = sha256.convert(bytes).toString();
    final known = project.items
        .expand((item) => item.attachments)
        .where((attachment) => attachment.remoteId == fileId)
        .firstOrNull;
    if (known != null && known.sha256.isNotEmpty && known.sha256 != digest) {
      throw const FormatException('下载内容与已知校验值不一致，已丢弃');
    }
    final localPath = await _attachmentStorage.persist(
      projectId: projectId,
      attachmentId: known?.id ?? 'cloud-$fileId',
      originalName: ticket['displayName'] as String,
      bytes: Uint8List.fromList(bytes),
    );
    if (localPath == null) {
      throw const FormatException('网页预览不保存敏感文件副本，请在手机 App 中下载');
    }
    if (known != null && known.localPath == null) {
      await _replaceAttachment(projectId, known.copyWith(localPath: localPath));
    }
    return localPath;
  }

  void _appendActivity(String projectId, String message) {
    state = state.copyWith(
      projects: state.projects.map((project) {
        if (project.id != projectId) return project;
        return project.copyWith(
          activities: [...project.activities, _activity(message)],
        );
      }).toList(),
    );
  }

  Future<void> _replaceAttachment(
    String projectId,
    LocalAttachment attachment,
  ) async {
    state = state.copyWith(
      projects: state.projects.map((project) {
        if (project.id != projectId) return project;
        return project.copyWith(
          items: project.items
              .map(
                (item) => item.copyWith(
                  attachments: item.attachments
                      .map(
                        (candidate) => candidate.id == attachment.id
                            ? attachment
                            : candidate,
                      )
                      .toList(),
                ),
              )
              .toList(),
        );
      }).toList(),
    );
    await _persistProjects();
  }

  Future<void> signIn(String email, {String accessCode = ''}) async {
    final normalized = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
      throw const FormatException('请输入有效邮箱地址');
    }
    final previousToken = _accessToken;
    try {
      if (accessCode.trim().isNotEmpty) {
        final login = await _apiClientFactory(normalized).postPublic(
          '/auth/pilot',
          {'email': normalized, 'accessCode': accessCode.trim()},
        );
        _accessToken = login['accessToken'] as String?;
        if (_accessToken == null || _accessToken!.isEmpty) {
          throw const FormatException('身份服务没有返回有效登录凭据');
        }
      }
      final account = await _api(normalized).getMap('/auth/me');
      await _repository.write(_accountEmailKey, normalized);
      if (_accessToken case final token?) {
        await _repository.write(_authTokenKey, token);
      } else {
        await _repository.remove(_authTokenKey);
      }
      state = state.copyWith(
        isSignedIn: true,
        accountEmail: normalized,
        deletionRequestedAt: _optionalDate(account['deletionRequestedAt']),
        clearDeletionRequestedAt: account['deletionRequestedAt'] == null,
      );
      await refreshEntitlements();
    } catch (_) {
      _accessToken = previousToken;
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _repository.remove(_accountEmailKey);
    await _repository.remove(_authTokenKey);
    _accessToken = null;
    state = state.copyWith(
      isSignedIn: false,
      clearAccountEmail: true,
      entitlementTier: 'FREE',
      clearTrialEndsAt: true,
      cloudStorageBytes: 1024 * 1024 * 1024,
      cloudStorageUsedBytes: 0,
      cloudStorageReservedBytes: 0,
      clearDeletionRequestedAt: true,
      policyNotificationsEnabled: false,
      followedJurisdictions: const ['AU-SA'],
      followedTags: const [],
      importantNotificationsOnly: true,
    );
  }

  Future<void> refreshAccount() async {
    final email = state.accountEmail;
    if (email == null) return;
    final account = await _api(email).getMap('/auth/me');
    state = state.copyWith(
      deletionRequestedAt: _optionalDate(account['deletionRequestedAt']),
      clearDeletionRequestedAt: account['deletionRequestedAt'] == null,
    );
  }

  Future<void> refreshEntitlements() async {
    final email = state.accountEmail;
    if (email == null) return;
    final payload = await _api(email).getMap('/entitlements/me');
    // 旧服务端没有这个字段时按“开放”处理，避免升级顺序造成误报未开放。
    final cloudUploads =
        payload['cloudFileUploads'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    state = state.copyWith(
      entitlementTier: payload['tier'] as String? ?? 'FREE',
      trialEndsAt: payload['trialEndsAt'] == null
          ? null
          : DateTime.parse(payload['trialEndsAt'] as String),
      clearTrialEndsAt: payload['trialEndsAt'] == null,
      cloudStorageBytes:
          payload['cloudStorageBytes'] as int? ?? 1024 * 1024 * 1024,
      cloudStorageUsedBytes:
          int.tryParse(payload['cloudStorageUsedBytes']?.toString() ?? '') ?? 0,
      cloudStorageReservedBytes:
          int.tryParse(
            payload['cloudStorageReservedBytes']?.toString() ?? '',
          ) ??
          0,
      cloudFileUploadsEnabled: cloudUploads['enabled'] as bool? ?? true,
      cloudFileUploadsDisabledReason:
          cloudUploads['disabledReason'] as String?,
      clearCloudFileUploadsDisabledReason:
          cloudUploads['disabledReason'] == null,
    );
  }

  Future<void> startTrial() async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    await _api(email).post('/entitlements/trial');
    await refreshEntitlements();
  }

  Future<void> submitPurchase({
    required String provider,
    required String productId,
    required String verificationData,
  }) async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    await _api(email).post('/entitlements/purchases', {
      'provider': provider,
      'productId': productId,
      'verificationData': verificationData,
    });
    await refreshEntitlements();
  }

  Future<void> restorePurchasesFromServer() async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    await _api(email).post('/entitlements/restore');
    await refreshEntitlements();
  }

  Future<void> requestAccountDeletion() async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    final result = await _api(email).delete('/auth/me');
    state = state.copyWith(
      deletionRequestedAt:
          _optionalDate(result['requestedAt']) ?? DateTime.now(),
    );
  }

  Future<void> refreshNotificationPreferences() async {
    final email = state.accountEmail;
    if (email == null) return;
    final payload = await _api(email).getMap('/notification-preferences');
    state = state.copyWith(
      policyNotificationsEnabled: payload['policyUpdates'] as bool? ?? false,
      followedJurisdictions:
          (payload['jurisdictions'] as List<dynamic>? ?? const ['AU-SA'])
              .cast<String>(),
      followedTags: (payload['tags'] as List<dynamic>? ?? const [])
          .cast<String>(),
      importantNotificationsOnly: payload['importantOnly'] as bool? ?? true,
    );
  }

  Future<void> updateNotificationPreferences({
    required bool enabled,
    required List<String> jurisdictions,
    required List<String> tags,
    required bool importantOnly,
  }) async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    final payload = await _api(email).patch('/notification-preferences', {
      'policyUpdates': enabled,
      'productUpdates': false,
      'jurisdictions': jurisdictions,
      'tags': tags,
      'importantOnly': importantOnly,
      'timezone': 'Australia/Adelaide',
    });
    state = state.copyWith(
      policyNotificationsEnabled: payload['policyUpdates'] as bool,
      followedJurisdictions: (payload['jurisdictions'] as List<dynamic>)
          .cast<String>(),
      followedTags: (payload['tags'] as List<dynamic>).cast<String>(),
      importantNotificationsOnly: payload['importantOnly'] as bool,
    );
  }

  Future<void> cancelAccountDeletion() async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    await _api(email).post('/auth/me/deletion/cancel');
    state = state.copyWith(clearDeletionRequestedAt: true);
  }

  Future<void> dismissNotice() async {
    await _repository.write(_noticeKey, true.toString());
    state = state.copyWith(noticeDismissed: true);
  }
}

AttachmentSyncStatus _syncStatusFromScan(String? scanStatus) =>
    switch (scanStatus) {
      'CLEAN' => AttachmentSyncStatus.available,
      'REJECTED' || 'ERROR' => AttachmentSyncStatus.failed,
      _ => AttachmentSyncStatus.scanning,
    };

ProjectActivity _activity(String message) => ProjectActivity(
  id: const Uuid().v4(),
  message: message,
  createdAt: DateTime.now(),
);

final appStoreProvider = StateNotifierProvider<AppStore, AppState>(
  (ref) => AppStore(createLocalRepository()),
);

String _serverChecklistStatus(ChecklistStatus status) => switch (status) {
  ChecklistStatus.notStarted => 'NOT_STARTED',
  ChecklistStatus.preparing => 'PREPARING',
  ChecklistStatus.ready => 'READY',
  ChecklistStatus.sent => 'SENT',
  ChecklistStatus.confirmed => 'CONFIRMED',
};

ChecklistStatus _localChecklistStatus(String? status) => switch (status) {
  'PREPARING' => ChecklistStatus.preparing,
  'READY' => ChecklistStatus.ready,
  'SENT' => ChecklistStatus.sent,
  'CONFIRMED' => ChecklistStatus.confirmed,
  _ => ChecklistStatus.notStarted,
};

DateTime? _optionalDate(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}

bool _sameInstant(Object? remote, DateTime? local) {
  final remoteDate = _optionalDate(remote);
  if (remoteDate == null || local == null) return remoteDate == local;
  return remoteDate.toUtc() == local.toUtc();
}

NewsItem _newsFromApi(Map<String, dynamic> json, {required bool bookmarked}) {
  final source = json['source'] as Map<String, dynamic>? ?? const {};
  final sourceType = switch (source['sourceType']?.toString().toLowerCase()) {
    'industry' => NewsSourceType.industry,
    'editorial' => NewsSourceType.editorial,
    'change_log' || 'changelog' => NewsSourceType.changeLog,
    _ => NewsSourceType.official,
  };
  return NewsItem(
    id: json['id'] as String,
    title: json['titleZh'] as String,
    summary: json['summaryZh'] as String,
    sourceName:
        source['name'] as String? ?? json['sourceTitle'] as String? ?? '官方来源',
    sourceUrl: json['sourceUrl'] as String,
    publishedAt: DateTime.parse(json['publishedAt'] as String).toLocal(),
    sourceType: sourceType,
    tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
    bookmarked: bookmarked,
  );
}

PolicyChange _changeFromApi(Map<String, dynamic> json) {
  final source = json['source'] as Map<String, dynamic>? ?? const {};
  final verification = switch (json['reviewStatus'] as String?) {
    'VERIFIED' => VerificationStatus.verified,
    'CORRECTED' => VerificationStatus.corrected,
    _ => VerificationStatus.pendingReview,
  };
  final severity = switch (json['importance'] as String?) {
    'MAJOR' => ChangeSeverity.critical,
    'IMPORTANT' => ChangeSeverity.important,
    _ => ChangeSeverity.general,
  };
  final context = json['context'] as String?;
  return PolicyChange(
    id: json['id'] as String,
    pageTitle: json['titleZh'] as String,
    sourceUrl: source['url'] as String? ?? '',
    discoveredAt: DateTime.parse(json['discoveredAt'] as String).toLocal(),
    summary:
        json['editorSummaryZh'] as String? ??
        context ??
        '监控器发现页面变化，当前只展示证据，不判断对个人申请的影响。',
    beforeText: json['oldExcerpt'] as String? ?? '没有可展示的上一版本文字片段。',
    afterText: json['newExcerpt'] as String? ?? '没有可展示的当前版本文字片段。',
    severity: severity,
    verification: verification,
    tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
  );
}
