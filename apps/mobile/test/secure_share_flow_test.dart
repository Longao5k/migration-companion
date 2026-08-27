import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:migration_companion/core/state/app_store.dart';
import 'package:migration_companion/features/projects/projects_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/store_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// 回归测试：分享面板弹出的后续流程曾经使用面板自己的 BuildContext。
  /// Navigator.pop 之后那个 context 会被卸载，`context.mounted` 变成 false，
  /// 于是“创建安全分享入口”会静默什么都不做——没有入口，也没有错误提示。
  testWidgets('从分享面板创建安全入口会真正调用服务端', (tester) async {
    final requests = <String>[];
    final store = await signedInStore(
      project: cloudProject(attachmentSha256: 'a' * 64),
      handler: (request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/shares')) {
          return http.Response(
            jsonEncode({
              'id': 'share-1',
              'expiresAt': '2026-09-03T00:00:00.000Z',
              'allowDownload': false,
              'url': 'http://127.0.0.1:53003/s/share-1#secret',
              'accessCode': 'LOCALCODE123',
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/projects/remote-project')) {
          return http.Response(
            jsonEncode({'id': 'remote-project', 'files': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'tier': 'FREE'}), 200);
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: const MaterialApp(
          home: ProjectDetailScreen(projectId: 'local-project'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('分享'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建安全分享入口'));
    await tester.pumpAndSettle();

    expect(find.text('创建安全分享入口'), findsOneWidget, reason: '创建对话框应当打开');

    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();

    expect(
      requests,
      contains('POST /v1/projects/remote-project/shares'),
      reason: '面板关闭后仍必须发出创建请求',
    );
    expect(find.text('安全入口已创建'), findsOneWidget);
    expect(find.textContaining('LOCALCODE123'), findsOneWidget);
  });
}
