import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:migration_companion/core/models/models.dart';

import 'support/store_fakes.dart';

void main() {
  test('断网编辑先保存在本机，联网后使用同一操作完成同步', () async {
    var online = false;
    String? firstOperationId;
    String? retriedOperationId;
    final requests = <String>[];
    final repository = InMemoryRepository();
    var store = await signedInStore(
      project: cloudProject(attachmentSha256: 'a' * 64),
      repository: repository,
      handler: (request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/auth/me')) {
          return http.Response('{}', 200);
        }
        if (request.url.path.endsWith('/entitlements/me')) {
          return _jsonResponse({'tier': 'FREE'});
        }
        if (request.url.path.endsWith('/sync-operations')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (!online) {
            firstOperationId = body['operationId'] as String;
            return http.Response('unavailable', 503);
          }
          retriedOperationId = body['operationId'] as String;
          return _jsonResponse({
            'operationId': retriedOperationId,
            'projectVersion': 2,
          }, 201);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/projects/remote-project')) {
          return _jsonResponse(_remoteProject(version: 2));
        }
        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      },
    );

    await store.advanceChecklistItem('local-project', 'local-item');
    var project = store.state.projects.single;
    expect(project.items.single.status, ChecklistStatus.ready);
    expect(project.syncStatus, ProjectSyncStatus.pending);
    expect(project.pendingSyncCount, 1);

    online = true;
    store = await signedInStore(
      repository: repository,
      handler: (request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/auth/me')) {
          return http.Response('{}', 200);
        }
        if (request.url.path.endsWith('/entitlements/me')) {
          return _jsonResponse({'tier': 'FREE'});
        }
        if (request.url.path.endsWith('/sync-operations')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          retriedOperationId = body['operationId'] as String;
          return _jsonResponse({
            'operationId': retriedOperationId,
            'projectVersion': 2,
          }, 201);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/projects/remote-project')) {
          return _jsonResponse(_remoteProject(version: 2));
        }
        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      },
    );
    expect(store.state.projects.single.pendingSyncCount, 1);
    try {
      await store.syncProject('local-project');
    } catch (error) {
      fail('$error\n${requests.join('\n')}');
    }
    project = store.state.projects.single;
    expect(firstOperationId, isNotNull);
    expect(retriedOperationId, firstOperationId);
    expect(project.syncStatus, ProjectSyncStatus.synced);
    expect(project.pendingSyncCount, 0);
    expect(project.cloudVersion, 2);
  });

  test('409 冲突只展示字段名，用户可保留本机修改并重放', () async {
    var conflict = true;
    String? operationId;
    final requests = <String>[];
    final store = await signedInStore(
      project: cloudProject(attachmentSha256: 'b' * 64),
      handler: (request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/auth/me')) {
          return http.Response('{}', 200);
        }
        if (request.url.path.endsWith('/entitlements/me')) {
          return _jsonResponse({'tier': 'FREE'});
        }
        if (request.url.path.endsWith('/sync-operations')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          operationId ??= body['operationId'] as String;
          expect(body['operationId'], operationId);
          if (conflict) {
            return _jsonResponse({
              'code': 'PROJECT_VERSION_CONFLICT',
              'message': '项目已有新版本，请先比较差异',
              'serverVersion': 3,
            }, 409);
          }
          return _jsonResponse({
            'operationId': operationId,
            'projectVersion': 4,
          }, 201);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/projects/remote-project')) {
          return _jsonResponse(
            _remoteProject(
              version: conflict ? 3 : 4,
              status: conflict ? 'PREPARING' : 'READY',
              note: conflict ? '云端的私密备注' : '',
            ),
          );
        }
        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      },
    );

    await store.advanceChecklistItem('local-project', 'local-item');
    expect(
      store.state.projects.single.syncStatus,
      ProjectSyncStatus.conflict,
      reason:
          '${store.state.projects.single.syncMessage}\n${requests.join('\n')}',
    );

    final differences = await store.compareCloudProject('local-project');
    expect(differences.join(), contains('备注'));
    expect(differences.join(), isNot(contains('云端的私密备注')));

    conflict = false;
    await store.keepLocalProjectVersion('local-project');
    final project = store.state.projects.single;
    expect(project.syncStatus, ProjectSyncStatus.synced);
    expect(project.pendingSyncCount, 0);
    expect(project.cloudVersion, 4);
    expect(project.items.single.status, ChecklistStatus.ready);
  });

  test('新设备登录后可以恢复云端项目和文件清单', () async {
    final store = await signedInStore(
      handler: (request) async {
        if (request.url.path.endsWith('/auth/me')) {
          return http.Response('{}', 200);
        }
        if (request.url.path.endsWith('/entitlements/me')) {
          return _jsonResponse({'tier': 'FREE'});
        }
        if (request.method == 'GET' && request.url.path.endsWith('/projects')) {
          return _jsonResponse([
            {'id': 'remote-project'},
          ]);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/projects/remote-project')) {
          final remote = _remoteProject(version: 7);
          remote['files'] = [
            {
              'id': 'remote-file',
              'checklistItemId': 'remote-item',
              'originalName': 'passport.pdf',
              'contentType': 'application/pdf',
              'byteSize': '42',
              'sha256': 'c' * 64,
              'scanStatus': 'CLEAN',
              'createdAt': '2026-08-28T00:00:00.000Z',
            },
          ];
          return _jsonResponse(remote);
        }
        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      },
    );

    await store.restoreCloudProjects();
    final restored = store.state.projects.single;
    expect(restored.remoteId, 'remote-project');
    expect(restored.cloudVersion, 7);
    expect(restored.cloudRole, 'OWNER');
    expect(restored.items.single.attachments.single.remoteId, 'remote-file');
    expect(restored.items.single.attachments.single.localPath, isNull);
    expect(
      restored.items.single.attachments.single.syncStatus,
      AttachmentSyncStatus.available,
    );
  });
}

http.Response _jsonResponse(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _remoteProject({
  required int version,
  String status = 'READY',
  String note = '',
}) => {
  'id': 'remote-project',
  'name': 'SA 491 验收项目',
  'template': 'SA_491',
  'applicantName': '主申请人',
  'targetDate': null,
  'version': version,
  'cloudFilesEnabled': true,
  'allowViewerDownload': false,
  'currentRole': 'OWNER',
  'checklist': [
    {
      'id': 'remote-item',
      'title': '护照身份页',
      'person': '主申请人',
      'category': '身份',
      'status': status,
      'note': note,
      'dueAt': null,
      'reminderAt': null,
    },
  ],
  'files': <Object?>[],
};
