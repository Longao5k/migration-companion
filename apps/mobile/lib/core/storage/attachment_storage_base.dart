import 'dart:typed_data';

abstract interface class AttachmentStorage {
  Future<String?> persist({
    required String projectId,
    required String attachmentId,
    required String originalName,
    required Uint8List bytes,
  });

  Future<void> remove(String? localPath);
  Future<Uint8List?> read(String? localPath);
}
