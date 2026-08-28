import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:migration_companion/core/models/models.dart';
import 'package:migration_companion/core/state/app_store.dart';

import 'support/store_fakes.dart';

void main() {
  test('完整备份在清空本机数据后恢复项目、提醒、附件与校验值', () async {
    final sourceFiles = RecordingAttachmentStorage();
    final sourceStore = AppStore(
      InMemoryRepository(),
      sourceFiles,
      SilentNotificationService(),
    );
    await sourceStore.ready;

    final project = await sourceStore.addProject(
      name: 'SA 190 恢复演练',
      visaType: 'SA 190',
      applicant: '申请人 A',
    );
    final item = project.items.first;
    final reminder = DateTime(2026, 9, 18, 9, 30);
    await sourceStore.setChecklistDates(
      projectId: project.id,
      itemId: item.id,
      dueDate: DateTime(2026, 9, 20),
      reminderAt: reminder,
    );
    await sourceStore.advanceChecklistItem(project.id, item.id);
    final bytes = Uint8List.fromList(utf8.encode('%PDF-1.7 backup sample'));
    final attachment = await sourceStore.addAttachment(
      projectId: project.id,
      itemId: item.id,
      name: 'passport.pdf',
      contentType: 'application/pdf',
      bytes: bytes,
    );

    final backup = await sourceStore.buildProjectBackup(project.id);

    // 新仓库和新附件目录模拟用户清空 App 数据后重新安装。
    final restoredFiles = RecordingAttachmentStorage();
    final restoredStore = AppStore(
      InMemoryRepository(),
      restoredFiles,
      SilentNotificationService(),
    );
    await restoredStore.ready;
    await restoredStore.importProjectBackup(
      jsonDecode(jsonEncode(backup)) as Map<String, dynamic>,
    );

    final restored = restoredStore.state.projects.single;
    final restoredItem = restored.items.first;
    final restoredAttachment = restoredItem.attachments.single;
    expect(restored.name, 'SA 190 恢复演练');
    expect(restoredItem.status, ChecklistStatus.preparing);
    expect(restoredItem.dueDate, DateTime(2026, 9, 20));
    expect(restoredItem.reminderAt, reminder);
    expect(restoredAttachment.sha256, attachment.sha256);
    expect(restoredFiles.persisted[attachment.id], bytes);
    expect(restored.isCloudSyncEnabled, isFalse);
    expect(restored.remoteId, isNull);
    expect(restoredItem.remoteId, isNull);
    expect(restoredAttachment.remoteId, isNull);
    expect(restoredAttachment.syncStatus, AttachmentSyncStatus.localOnly);
  });
}
