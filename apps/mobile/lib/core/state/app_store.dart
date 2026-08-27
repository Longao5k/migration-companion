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
    this.noticeDismissed = false,
  });

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
  final bool noticeDismissed;

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
    bool? noticeDismissed,
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
    noticeDismissed: noticeDismissed ?? this.noticeDismissed,
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
    _hydrate();
  }

  static const _projectsKey = 'migration_companion.projects.v1';
  static const _accountEmailKey = 'migration_companion.account_email.v1';
  static const _noticeKey = 'migration_companion.notice_dismissed.v1';
  static const _bookmarksKey = 'migration_companion.bookmarks.v1';
  final _uuid = const Uuid();
  final LocalRepository _repository;
  final AttachmentStorage _attachmentStorage;
  final NotificationService _notificationService;

  /// 所有服务端调用都经过这个工厂，测试可以注入带 mock 传输层的客户端。
  final ApiClient Function(String accountEmail) _apiClientFactory;

  Future<void> _hydrate() async {
    final raw = await _repository.read(_projectsKey);
    final projects = raw == null
        ? <VisaProject>[]
        : (jsonDecode(raw) as List<dynamic>)
              .map((item) => VisaProject.fromJson(item as Map<String, dynamic>))
              .toList();
    final accountEmail = await _repository.read(_accountEmailKey);
    final bookmarksRaw = await _repository.read(_bookmarksKey);
    final bookmarks = bookmarksRaw == null
        ? <String>{}
        : (jsonDecode(bookmarksRaw) as List<dynamic>).cast<String>().toSet();
    state = state.copyWith(
      news: state.news
          .map((item) => item.copyWith(bookmarked: bookmarks.contains(item.id)))
          .toList(),
      projects: projects,
      isSignedIn: accountEmail != null,
      accountEmail: accountEmail,
      noticeDismissed: await _repository.read(_noticeKey) == 'true',
      isHydrated: true,
    );
    if (accountEmail != null) {
      try {
        await refreshEntitlements();
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
    String? remoteItemId;
    var cloudVersion = existingProject.cloudVersion;
    if (existingProject.isCloudSyncEnabled &&
        existingProject.remoteId != null) {
      final email = state.accountEmail;
      if (email == null) throw const FormatException('云同步项目需要登录账号');
      final remote = await _apiClientFactory(email).post(
        '/projects/${existingProject.remoteId}/checklist',
        {'title': title, 'category': '自定义'},
      );
      remoteItemId = (remote['item'] as Map<String, dynamic>)['id'] as String;
      cloudVersion = remote['projectVersion'] as int;
    }
    state = state.copyWith(
      projects: state.projects.map((project) {
        if (project.id != projectId) return project;
        return project.copyWith(
          items: [
            ...project.items,
            ChecklistItem(
              id: _uuid.v4(),
              title: title,
              owner: project.applicant,
              category: '自定义',
              status: ChecklistStatus.notStarted,
              remoteId: remoteItemId,
            ),
          ],
          cloudVersion: cloudVersion,
          activities: [...project.activities, _activity('添加了材料项：$title')],
        );
      }).toList(),
    );
    await _persistProjects();
  }

  Future<void> advanceChecklistItem(String projectId, String itemId) async {
    final currentProject = state.projects.firstWhere(
      (project) => project.id == projectId,
    );
    final currentItem = currentProject.items.firstWhere(
      (item) => item.id == itemId,
    );
    final nextStatus = currentItem.status.next;
    var cloudVersion = currentProject.cloudVersion;
    if (currentProject.isCloudSyncEnabled &&
        currentProject.remoteId != null &&
        currentItem.remoteId != null) {
      final email = state.accountEmail;
      if (email == null) throw const FormatException('云同步项目需要登录账号');
      final remote = await _apiClientFactory(email).patch(
        '/projects/${currentProject.remoteId}/checklist/${currentItem.remoteId}',
        {
          'status': _serverChecklistStatus(nextStatus),
          'expectedProjectVersion': currentProject.cloudVersion,
        },
      );
      cloudVersion = remote['projectVersion'] as int;
    }
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
          cloudVersion: cloudVersion,
          activities: [
            ...project.activities,
            _activity('将“${currentItem.title}”更新为“${nextStatus.label}”'),
          ],
        );
      }).toList(),
    );
    await _persistProjects();
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
    var cloudVersion = currentProject.cloudVersion;
    if (currentProject.isCloudSyncEnabled &&
        currentProject.remoteId != null &&
        currentItem.remoteId != null) {
      final email = state.accountEmail;
      if (email == null) throw const FormatException('云同步项目需要登录账号');
      final remote = await _apiClientFactory(email).patch(
        '/projects/${currentProject.remoteId}/checklist/${currentItem.remoteId}',
        {
          'status': _serverChecklistStatus(currentItem.status),
          'expectedProjectVersion': currentProject.cloudVersion,
          if (nextDueDate != null)
            'dueAt': nextDueDate.toUtc().toIso8601String(),
          if (nextReminder != null)
            'reminderAt': nextReminder.toUtc().toIso8601String(),
          if (clearDueDate) 'clearDueAt': true,
          if (clearReminderAt) 'clearReminderAt': true,
        },
      );
      cloudVersion = remote['projectVersion'] as int;
    }
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
          cloudVersion: cloudVersion,
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
    try {
      final remote = await _apiClientFactory(email).uploadFile(
        '/projects/${project.remoteId}/files',
        fieldName: 'file',
        fileName: attachment.name,
        contentType: attachment.contentType,
        bytes: bytes,
        fields: {'checklistItemId': item.remoteId!},
      );
      final scanStatus = remote['scanStatus'] as String? ?? 'PENDING';
      await _updateAttachment(
        projectId,
        itemId,
        attachment.copyWith(
          remoteId: remote['id'] as String,
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
        attachment.copyWith(syncStatus: AttachmentSyncStatus.failed),
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
    var cloudVersion = currentProject.cloudVersion;
    if (currentProject.isCloudSyncEnabled &&
        currentProject.remoteId != null &&
        currentItem.remoteId != null) {
      final email = state.accountEmail;
      if (email == null) throw const FormatException('云同步项目需要登录账号');
      final remote = await _apiClientFactory(email).patch(
        '/projects/${currentProject.remoteId}/checklist/${currentItem.remoteId}',
        {
          'status': _serverChecklistStatus(currentItem.status),
          'expectedProjectVersion': currentProject.cloudVersion,
          'note': note,
        },
      );
      cloudVersion = remote['projectVersion'] as int;
    }
    state = state.copyWith(
      projects: state.projects.map((project) {
        if (project.id != projectId) return project;
        return project.copyWith(
          items: project.items
              .map(
                (item) => item.id == itemId ? item.copyWith(note: note) : item,
              )
              .toList(),
          cloudVersion: cloudVersion,
          activities: [...project.activities, _activity('更新了一个材料项的备注')],
        );
      }).toList(),
    );
    await _persistProjects();
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
        restoredAttachments.add(attachment.copyWith(localPath: localPath));
      }
      restoredItems.add(item.copyWith(attachments: restoredAttachments));
    }
    await importProject(decoded.copyWith(items: restoredItems));
  }

  Future<void> enableCloudSync(String projectId) async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    final project = state.projects.firstWhere((item) => item.id == projectId);
    if (project.isCloudSyncEnabled) return;
    final api = _apiClientFactory(email);
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
    final remote = await _apiClientFactory(email).patch(
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
    return _apiClientFactory(email)
        .post('/projects/${project.remoteId}/shares', {
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
    return _apiClientFactory(accountEmail).post(
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
    return _apiClientFactory(email);
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
    _appendActivity(
      projectId,
      role == 'VIEWER' ? '把一位成员降为仅查看' : '把一位成员设为可协作',
    );
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

  Future<void> signIn(String email) async {
    final normalized = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
      throw const FormatException('请输入有效邮箱地址');
    }
    await _apiClientFactory(normalized).getMap('/auth/me');
    await _repository.write(_accountEmailKey, normalized);
    state = state.copyWith(isSignedIn: true, accountEmail: normalized);
    await refreshEntitlements();
  }

  Future<void> signOut() async {
    await _repository.remove(_accountEmailKey);
    state = state.copyWith(
      isSignedIn: false,
      clearAccountEmail: true,
      entitlementTier: 'FREE',
      clearTrialEndsAt: true,
      cloudStorageBytes: 1024 * 1024 * 1024,
      cloudStorageUsedBytes: 0,
    );
  }

  Future<void> refreshEntitlements() async {
    final email = state.accountEmail;
    if (email == null) return;
    final payload = await _apiClientFactory(email)
        .getMap('/entitlements/me');
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
    );
  }

  Future<void> startTrial() async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    await _apiClientFactory(email).post('/entitlements/trial');
    await refreshEntitlements();
  }

  Future<void> submitPurchase({
    required String provider,
    required String productId,
    required String verificationData,
  }) async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    await _apiClientFactory(email).post('/entitlements/purchases', {
      'provider': provider,
      'productId': productId,
      'verificationData': verificationData,
    });
    await refreshEntitlements();
  }

  Future<void> restorePurchasesFromServer() async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    await _apiClientFactory(email).post('/entitlements/restore');
    await refreshEntitlements();
  }

  Future<void> requestAccountDeletion() async {
    final email = state.accountEmail;
    if (email == null) throw const FormatException('请先登录账号');
    await _apiClientFactory(email).delete('/auth/me');
    await signOut();
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
