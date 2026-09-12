import 'package:flutter_test/flutter_test.dart';
import 'package:migration_companion/core/data/processing_times.dart';
import 'package:migration_companion/core/state/app_store.dart';

import 'support/store_fakes.dart';

void main() {
  test('新申请只默认创建两个核心材料项', () async {
    final store = AppStore(
      InMemoryRepository(),
      RecordingAttachmentStorage(),
      SilentNotificationService(),
    );
    await store.ready;

    final project = await store.addProject(
      name: 'Test 190',
      visaType: '190',
      applicant: 'Alex',
    );

    expect(project.items.map((item) => item.id), [
      'identity-passport',
      'employment-evidence',
    ]);
  });

  test('递交和下签日期会在重启后保留', () async {
    final repository = InMemoryRepository();
    final first = AppStore(
      repository,
      RecordingAttachmentStorage(),
      SilentNotificationService(),
    );
    await first.ready;
    final project = await first.addProject(
      name: 'Test 482',
      visaType: '482',
      applicant: 'Alex',
    );
    await first.markProjectSubmitted(project.id, DateTime(2026, 1, 2));
    await first.markProjectGranted(project.id, DateTime(2026, 5, 6));

    final restarted = AppStore(
      repository,
      RecordingAttachmentStorage(),
      SilentNotificationService(),
    );
    await restarted.ready;

    expect(restarted.state.projects.single.submittedAt, DateTime(2026, 1, 2));
    expect(restarted.state.projects.single.grantedAt, DateTime(2026, 5, 6));
  });

  test('官方审理时间映射使用签证类别中位数', () {
    expect(
      ProcessingTimes.forVisaType('South Australia 190')?.displayValue,
      '8 months',
    );
    expect(
      ProcessingTimes.forVisaType('482 · Skills in Demand')?.displayValue,
      '98 days',
    );
    expect(ProcessingTimes.forVisaType('Custom'), isNull);
  });
}
