import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:migration_companion/core/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/store_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('扫描通过的云文件会把本机附件标记为云端可用', () async {
    final store = await signedInStore(
      project: cloudProject(attachmentSha256: 'a' * 64),
      handler: (request) async {
        if (request.url.path.endsWith('/projects/remote-project')) {
          return http.Response(
            jsonEncode({
              'id': 'remote-project',
              'version': 3,
              'files': [
                {
                  'id': 'remote-file',
                  'checklistItemId': 'remote-item',
                  'originalName': 'passport.pdf',
                  'byteSize': '12',
                  'compatibility': 'PDF_SUPPORTED',
                  'scanStatus': 'CLEAN',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'tier': 'FREE'}), 200);
      },
    );

    final files = await store.refreshCloudFileStatuses('local-project');

    expect(files, hasLength(1));
    final attachment =
        store.state.projects.single.items.single.attachments.single;
    expect(attachment.syncStatus, AttachmentSyncStatus.available);
    expect(attachment.remoteId, 'remote-file');
  });

  test('服务端已删除的云文件让附件退回仅本机，并清除远端引用', () async {
    final store = await signedInStore(
      project: cloudProject(attachmentSha256: 'a' * 64),
      handler: (request) async {
        if (request.url.path.endsWith('/projects/remote-project')) {
          return http.Response(
            jsonEncode({'id': 'remote-project', 'version': 4, 'files': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'tier': 'FREE'}), 200);
      },
    );

    await store.refreshCloudFileStatuses('local-project');

    final attachment =
        store.state.projects.single.items.single.attachments.single;
    expect(attachment.syncStatus, AttachmentSyncStatus.localOnly);
    expect(attachment.remoteId, isNull);
  });

  test('下载内容与已知校验值不一致时丢弃，不写入私有目录', () async {
    final attachments = RecordingAttachmentStorage();
    final store = await signedInStore(
      attachments: attachments,
      project: cloudProject(attachmentSha256: 'b' * 64),
      handler: (request) async {
        if (request.url.path.endsWith('/files/remote-file/download')) {
          return http.Response(
            jsonEncode({
              'id': 'remote-file',
              'displayName': 'passport.pdf',
              'downloadUrl': 'https://storage.invalid/signed-object',
              'expiresInSeconds': 60,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.host == 'storage.invalid') {
          return http.Response.bytes(utf8.encode('tampered-bytes'), 200);
        }
        return http.Response(jsonEncode({'tier': 'FREE'}), 200);
      },
    );

    await expectLater(
      store.downloadCloudFile(
        projectId: 'local-project',
        fileId: 'remote-file',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(attachments.persisted, isEmpty);
  });

  test('校验一致的下载写入私有目录并补回本机路径', () async {
    final payload = utf8.encode('%PDF-1.7 sample');
    final digest = sha256.convert(payload).toString();
    final attachments = RecordingAttachmentStorage();
    final store = await signedInStore(
      attachments: attachments,
      project: cloudProject(attachmentSha256: digest),
      handler: (request) async {
        if (request.url.path.endsWith('/files/remote-file/download')) {
          return http.Response(
            jsonEncode({
              'id': 'remote-file',
              'displayName': 'passport.pdf',
              'downloadUrl': 'https://storage.invalid/signed-object',
              'expiresInSeconds': 60,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.host == 'storage.invalid') {
          return http.Response.bytes(payload, 200);
        }
        return http.Response(jsonEncode({'tier': 'FREE'}), 200);
      },
    );

    final localPath = await store.downloadCloudFile(
      projectId: 'local-project',
      fileId: 'remote-file',
    );

    expect(localPath, contains('local-attachment'));
    expect(attachments.persisted['local-attachment'], payload);
    expect(
      store.state.projects.single.items.single.attachments.single.localPath,
      localPath,
    );
  });

  test('删除云副本后本机附件保留，但退回仅本机', () async {
    final store = await signedInStore(
      project: cloudProject(
        attachmentSha256: 'c' * 64,
        attachmentLocalPath: '/private/local-project/local-attachment',
      ),
      handler: (request) async {
        if (request.method == 'DELETE' &&
            request.url.path.endsWith('/files/remote-file')) {
          return http.Response(jsonEncode({'deleted': true}), 200);
        }
        return http.Response(
          jsonEncode({'tier': 'FREE', 'cloudStorageUsedBytes': '0'}),
          200,
        );
      },
    );

    await store.deleteCloudFile(
      projectId: 'local-project',
      fileId: 'remote-file',
    );

    final attachment =
        store.state.projects.single.items.single.attachments.single;
    expect(attachment.remoteId, isNull);
    expect(attachment.syncStatus, AttachmentSyncStatus.localOnly);
    expect(attachment.localPath, '/private/local-project/local-attachment');
  });
}
