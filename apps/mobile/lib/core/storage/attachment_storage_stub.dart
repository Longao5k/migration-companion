import 'dart:typed_data';

import 'attachment_storage_base.dart';

AttachmentStorage createPlatformAttachmentStorage() => StubAttachmentStorage();

class StubAttachmentStorage implements AttachmentStorage {
  @override
  Future<String?> persist({
    required String projectId,
    required String attachmentId,
    required String originalName,
    required Uint8List bytes,
  }) async => null;

  @override
  Future<void> remove(String? localPath) async {}

  @override
  Future<Uint8List?> read(String? localPath) async => null;
}
