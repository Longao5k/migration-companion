import 'package:flutter_test/flutter_test.dart';
import 'package:migration_companion/core/models/models.dart';

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
      expect(item.copyWith(bookmarked: true).sourceTitle, 'Income threshold update');
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
    ChecklistItem item(
      String id,
      ChecklistStatus status, {
      DateTime? due,
    }) => ChecklistItem(
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
}
