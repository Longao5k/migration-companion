import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:migration_companion/core/api/api_client.dart';
import 'package:migration_companion/core/models/models.dart';
import 'package:migration_companion/core/notifications/notification_service_base.dart';
import 'package:migration_companion/core/state/app_store.dart';
import 'package:migration_companion/core/storage/attachment_storage.dart';
import 'package:migration_companion/core/storage/local_repository.dart';

class InMemoryRepository implements LocalRepository {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

class RecordingAttachmentStorage implements AttachmentStorage {
  final persisted = <String, Uint8List>{};

  @override
  Future<String?> persist({
    required String projectId,
    required String attachmentId,
    required String originalName,
    required Uint8List bytes,
  }) async {
    persisted[attachmentId] = bytes;
    return '/private/$projectId/$attachmentId';
  }

  @override
  Future<void> remove(String? localPath) async {}

  @override
  Future<Uint8List?> read(String? localPath) async => null;
}

class SilentNotificationService implements NotificationService {
  @override
  Future<void> cancel(String stableId) async {}

  @override
  Future<void> schedule({
    required String stableId,
    required DateTime at,
    required String payload,
  }) async {}
}

/// 构造一个已登录的仓库，并把所有 HTTP 交互交给 [handler]。
Future<AppStore> signedInStore({
  required Future<http.Response> Function(http.Request request) handler,
  AttachmentStorage? attachments,
  VisaProject? project,
  String email = 'owner@migration-companion.invalid',
}) async {
  final store = AppStore(
    InMemoryRepository(),
    attachments ?? RecordingAttachmentStorage(),
    SilentNotificationService(),
    (accountEmail) =>
        ApiClient(accountEmail: accountEmail, httpClient: MockClient(handler)),
  );
  await store.signIn(email);
  if (project != null) await store.importProject(project);
  return store;
}

/// 一个已开启云同步、清单项与附件都已完成云端映射的项目。
VisaProject cloudProject({
  required String attachmentSha256,
  String? attachmentLocalPath,
  AttachmentSyncStatus syncStatus = AttachmentSyncStatus.scanning,
}) => VisaProject(
  id: 'local-project',
  name: 'SA 491 验收项目',
  visaType: 'SA 491',
  applicant: '主申请人',
  status: ProjectStatus.active,
  isCloudSyncEnabled: true,
  remoteId: 'remote-project',
  items: [
    ChecklistItem(
      id: 'local-item',
      title: '护照身份页',
      owner: '主申请人',
      category: '身份',
      status: ChecklistStatus.preparing,
      remoteId: 'remote-item',
      attachments: [
        LocalAttachment(
          id: 'local-attachment',
          name: 'passport.pdf',
          contentType: 'application/pdf',
          byteSize: 12,
          sha256: attachmentSha256,
          createdAt: DateTime(2026, 8, 27),
          localPath: attachmentLocalPath,
          remoteId: 'remote-file',
          syncStatus: syncStatus,
        ),
      ],
    ),
  ],
);
