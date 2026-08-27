import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'attachment_storage_base.dart';

AttachmentStorage createPlatformAttachmentStorage() =>
    NativeAttachmentStorage();

class NativeAttachmentStorage implements AttachmentStorage {
  @override
  Future<String> persist({
    required String projectId,
    required String attachmentId,
    required String originalName,
    required Uint8List bytes,
  }) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(path.join(root.path, 'attachments', projectId));
    await directory.create(recursive: true);
    final extension = path.extension(originalName).toLowerCase();
    final target = File(path.join(directory.path, '$attachmentId$extension'));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  @override
  Future<void> remove(String? localPath) async {
    if (localPath == null) return;
    final file = File(localPath);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<Uint8List?> read(String? localPath) async {
    if (localPath == null) return null;
    final file = File(localPath);
    return await file.exists() ? file.readAsBytes() : null;
  }
}
