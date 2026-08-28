import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:migration_companion/core/api/api_client.dart';
import 'package:migration_companion/core/models/models.dart';
import 'package:migration_companion/core/state/app_store.dart';

import 'support/store_fakes.dart';

void main() {
  test('服务端内容会替换种子数据并缓存，离线重启继续显示缓存', () async {
    final repository = InMemoryRepository();
    final online = AppStore(
      repository,
      RecordingAttachmentStorage(),
      SilentNotificationService(),
      (email) => ApiClient(
        accountEmail: email,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/content/news')) {
            return http.Response(
              jsonEncode([
                {
                  'id': 'news-remote',
                  'titleZh': '南澳官方更新',
                  'summaryZh': '事实性摘要，请回到官方原文核对。',
                  'sourceTitle': 'Official update',
                  'sourceUrl': 'https://migration.sa.gov.au/news/update',
                  'tags': ['SA', '190'],
                  'publishedAt': '2026-08-28T01:00:00.000Z',
                  'source': {
                    'name': 'Move to South Australia',
                    'sourceType': 'official',
                  },
                },
              ]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            jsonEncode([
              {
                'id': 'change-remote',
                'titleZh': 'Documents required 页面变化',
                'oldExcerpt': '旧片段',
                'newExcerpt': '新片段',
                'context': '自动发现的一般变化，仍待人工核实。',
                'importance': 'GENERAL',
                'reviewStatus': 'PENDING',
                'discoveredAt': '2026-08-28T01:10:00.000Z',
                'tags': ['SA', '491'],
                'source': {
                  'url': 'https://migration.sa.gov.au/how-to-apply/documents-required',
                  'sourceType': 'official',
                },
              },
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    await online.ready;
    await online.refreshContent();
    await online.toggleBookmark('news-remote');

    expect(online.state.news, hasLength(1), reason: online.state.contentError);
    expect(online.state.news.single.title, '南澳官方更新');
    expect(online.state.news.single.bookmarked, isTrue);
    expect(
      online.state.changes.single.verification,
      VerificationStatus.pendingReview,
    );
    expect(online.state.contentError, isNull);
    expect(online.state.contentUpdatedAt, isNotNull);

    final offline = AppStore(
      repository,
      RecordingAttachmentStorage(),
      SilentNotificationService(),
    );
    await offline.ready;

    expect(offline.state.news.single.id, 'news-remote');
    expect(offline.state.news.single.bookmarked, isTrue);
    expect(offline.state.changes.single.id, 'change-remote');
    expect(offline.state.contentUpdatedAt, isNotNull);
  });

  test('刷新失败保留已有内容并明确记录错误状态', () async {
    final store = AppStore(
      InMemoryRepository(),
      RecordingAttachmentStorage(),
      SilentNotificationService(),
      (email) => ApiClient(
        accountEmail: email,
        httpClient: MockClient((_) async => http.Response('unavailable', 503)),
      ),
    );
    await store.ready;
    final originalIds = store.state.news.map((item) => item.id).toList();

    await store.refreshContent();

    expect(store.state.news.map((item) => item.id), originalIds);
    expect(store.state.contentError, contains('本机缓存'));
    expect(store.state.isContentRefreshing, isFalse);
  });
}
