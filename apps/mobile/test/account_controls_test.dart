import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/store_fakes.dart';

void main() {
  test('删除申请保留登录与本机项目，并可在计划执行前撤回', () async {
    final requests = <String>[];
    final store = await signedInStore(
      handler: (request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.method == 'DELETE' &&
            request.url.path.endsWith('/auth/me')) {
          return _json({
            'accepted': true,
            'requestedAt': '2026-08-28T00:00:00.000Z',
            'scheduledFor': '2026-09-04T00:00:00.000Z',
          });
        }
        if (request.url.path.endsWith('/auth/me/deletion/cancel')) {
          return _json({'cancelled': true}, 201);
        }
        if (request.url.path.endsWith('/auth/me')) {
          return _json({'deletionRequestedAt': null});
        }
        if (request.url.path.endsWith('/notification-preferences')) {
          return _json({
            'policyUpdates': false,
            'jurisdictions': ['AU-SA'],
            'tags': <String>[],
            'importantOnly': true,
          });
        }
        return _json({'tier': 'FREE'});
      },
    );
    final project = await store.addProject(
      name: '本机项目',
      visaType: 'SA 190',
      applicant: '申请人',
    );

    await store.requestAccountDeletion();
    expect(store.state.isSignedIn, isTrue);
    expect(store.state.projects.single.id, project.id);
    expect(
      store.state.deletionRequestedAt?.toUtc(),
      DateTime.utc(2026, 8, 28),
    );

    await store.cancelAccountDeletion();
    expect(store.state.deletionRequestedAt, isNull);
    expect(requests, contains('POST /v1/auth/me/deletion/cancel'));
  });

  test('政策关注规则保存到服务端，材料本机提醒不受影响', () async {
    final store = await signedInStore(
      handler: (request) async {
        if (request.method == 'PATCH' &&
            request.url.path.endsWith('/notification-preferences')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return _json(body);
        }
        if (request.url.path.endsWith('/notification-preferences')) {
          return _json({
            'policyUpdates': false,
            'jurisdictions': ['AU-SA'],
            'tags': <String>[],
            'importantOnly': true,
          });
        }
        if (request.url.path.endsWith('/auth/me')) {
          return _json({'deletionRequestedAt': null});
        }
        return _json({'tier': 'FREE'});
      },
    );

    await store.updateNotificationPreferences(
      enabled: true,
      jurisdictions: const ['AU-SA', 'AU-FED'],
      tags: const ['190', '491'],
      importantOnly: true,
    );
    expect(store.state.policyNotificationsEnabled, isTrue);
    expect(store.state.followedJurisdictions, ['AU-SA', 'AU-FED']);
    expect(store.state.followedTags, ['190', '491']);
    expect(store.state.importantNotificationsOnly, isTrue);
  });
}

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
