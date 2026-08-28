import 'package:flutter_test/flutter_test.dart';
import 'package:migration_companion/core/models/models.dart';
import 'package:migration_companion/core/state/app_store.dart';

void main() {
  group('官方原标题', () {
    test('从接口读回并保留，用于详情页的中英对照', () {
      final item = NewsItem.fromJson({
        'id': 'n1',
        'title': '南澳更新收入门槛',
        'summary': '摘要',
        'sourceName': 'Move to South Australia',
        'sourceTitle': '  Income threshold update  ',
        'sourceUrl': 'https://migration.sa.gov.au/news/x',
        'publishedAt': '2026-07-02T00:00:00.000Z',
        'sourceType': 'official',
        'tags': <String>['SA'],
      });
      expect(item.sourceTitle, 'Income threshold update');
      // 收藏后仍要留着，否则详情页的英文原标题会在收藏时消失。
      expect(
        item.copyWith(bookmarked: true).sourceTitle,
        'Income threshold update',
      );
    });

    test('缺失或空串都归一成 null，界面据此不显示这一块', () {
      NewsItem build(Object? raw) => NewsItem.fromJson({
        'id': 'n1',
        'title': '标题',
        'summary': '摘要',
        'sourceName': '来源',
        'sourceTitle': ?raw,
        'sourceUrl': 'https://migration.sa.gov.au/news/x',
        'publishedAt': '2026-07-02T00:00:00.000Z',
        'sourceType': 'official',
        'tags': <String>[],
      });
      expect(build(null).sourceTitle, isNull);
      expect(build('').sourceTitle, isNull);
      expect(build('   ').sourceTitle, isNull);
    });
  });

  group('下一步该做什么', () {
    ChecklistItem item(String id, ChecklistStatus status, {DateTime? due}) =>
        ChecklistItem(
          id: id,
          title: id,
          owner: '本人',
          category: '材料',
          status: status,
          dueDate: due,
        );

    VisaProject project(List<ChecklistItem> items) => VisaProject(
      id: 'p1',
      name: '南澳 190',
      visaType: 'SA 190',
      applicant: '本人',
      status: ProjectStatus.active,
      items: items,
    );

    test('未完成项里优先给最早到期的那一项', () {
      final next = project([
        item('已办好', ChecklistStatus.confirmed),
        item('无期限', ChecklistStatus.notStarted),
        item('晚到期', ChecklistStatus.preparing, due: DateTime(2026, 12, 1)),
        item('早到期', ChecklistStatus.notStarted, due: DateTime(2026, 9, 1)),
      ]).nextAction;
      expect(next?.title, '早到期');
    });

    test('有期限的排在没期限的前面', () {
      final next = project([
        item('无期限', ChecklistStatus.notStarted),
        item('有期限', ChecklistStatus.notStarted, due: DateTime(2027, 1, 1)),
      ]).nextAction;
      expect(next?.title, '有期限');
    });

    test('全部办好时没有下一步，进度不再催用户', () {
      final done = project([
        item('a', ChecklistStatus.ready),
        item('b', ChecklistStatus.sent),
      ]);
      expect(done.nextAction, isNull);
      expect(done.doneCount, 2);
      expect(done.completion, 1.0);
    });

    test('已准备之前的状态都算未办好', () {
      final partial = project([
        item('a', ChecklistStatus.notStarted),
        item('b', ChecklistStatus.preparing),
        item('c', ChecklistStatus.ready),
        item('d', ChecklistStatus.confirmed),
      ]);
      expect(partial.doneCount, 2);
      expect(partial.nextAction?.title, 'a');
    });
  });

  group('监控状态', () {
    MonitoringStatus parse(Map<String, dynamic> json) =>
        MonitoringStatus.fromJson(json);

    test('部分页面取不到的辖区，措辞是「部分」而不是整个辖区都监控不到', () {
      final status = parse({
        'monitoredCount': 5,
        'unavailableCount': 3,
        'jurisdictions': [
          {'jurisdiction': 'AU-SA', 'monitoredCount': 4, 'unavailableCount': 0},
          {
            'jurisdiction': 'AU-FED',
            'monitoredCount': 1,
            'unavailableCount': 3,
          },
        ],
      });
      expect(status.hasGap, isTrue);
      expect(status.fullyDown, isEmpty);
      expect(status.partlyDown.single.jurisdiction, 'AU-FED');
      // 「联邦的页面现在监控不到」会被读成「联邦法规变了我们也看不见」，正好说反。
      expect(status.gapSentence, '联邦有部分页面监控不到');
    });

    test('整个辖区都取不到时才说「现在监控不到」', () {
      final status = parse({
        'monitoredCount': 0,
        'unavailableCount': 2,
        'jurisdictions': [
          {'jurisdiction': 'AU-SA', 'monitoredCount': 0, 'unavailableCount': 2},
        ],
      });
      expect(status.gapSentence, '南澳的页面现在监控不到');
    });

    test('没有缺口时不产生任何提示', () {
      final status = parse({
        'monitoredCount': 6,
        'unavailableCount': 0,
        'jurisdictions': [
          {'jurisdiction': 'AU-SA', 'monitoredCount': 6, 'unavailableCount': 0},
        ],
      });
      expect(status.hasGap, isFalse);
      expect(status.gapSentence, isNull);
    });

    test('待人工核实的条数会被读出来，空列表才不会被说成「没有变化」', () {
      final status = parse({
        'monitoredCount': 6,
        'unavailableCount': 0,
        'pendingReviewCount': 6,
      });
      expect(status.pendingReviewCount, 6);
      expect(status.hasGap, isFalse);
    });

    test('旧服务端不返回 jurisdictions 时，缺口仍要说出来，只是没有细分', () {
      final status = parse({'monitoredCount': 3, 'unavailableCount': 1});
      expect(status.hasGap, isTrue);
      // 分不出辖区不等于没有缺口。返回 null 会让界面落到「没有变化」。
      expect(status.gapSentence, '有一部分官方页面现在监控不到');
      expect(status.pendingReviewCount, 0);
    });
  });

  group('监控缺口的兜底', () {
    test('旧服务端只给计数、不给 jurisdictions 时，仍然说出缺口', () {
      // 这条路径以前会让 gapSentence 返回 null，界面一路落到
      // 「这些页面暂时没有变化」——为了修「说反话」而造出一句「说没变化」。
      final status = MonitoringStatus.fromJson({
        'monitoredCount': 3,
        'unavailableCount': 2,
      });
      expect(status.hasGap, isTrue);
      expect(status.gapSentence, isNotNull);
    });

    test('没有缺口时依然不产生提示', () {
      final status = MonitoringStatus.fromJson({
        'monitoredCount': 3,
        'unavailableCount': 0,
      });
      expect(status.gapSentence, isNull);
    });
  });

  group('首页讨论卡片', () {
    ProjectDiscussionPreview preview(String author) => ProjectDiscussionPreview(
      projectId: 'p1',
      projectName: '南澳 190',
      body: '工作证明补齐了',
      author: author,
      createdAt: DateTime(2026, 8, 28),
      totalCount: 3,
    );

    test('协作者邮箱在首页只显示前两位', () {
      expect(preview('alice@example.com').authorLabel, 'al***');
      expect(preview('bo@example.com').authorLabel, 'bo***');
      expect(preview('a@example.com').authorLabel, 'a***');
    });

    test('不是邮箱的显示名原样保留', () {
      expect(preview('成员').authorLabel, '成员');
    });
  });
}
