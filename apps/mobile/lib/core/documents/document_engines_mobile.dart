import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'document_engine.dart';
import 'document_preflight.dart';

PdfDocumentEngine createPdfDocumentEngine() => DartPdfDocumentEngine();
DocxDocumentEngine createDocxDocumentEngine() => _MobileDocxEngine();

/// Lightweight host boundary for the open-source PDF editor.
///
/// The original is only read to validate its signature and create an app-owned
/// working copy. Every save produces another file, so user material is never
/// overwritten in place.
class DartPdfDocumentEngine implements PdfDocumentEngine {
  @override
  String get implementationName => 'dart_pdf_editor 4.4.0';

  @override
  Future<DocumentPreflightResult> preflight({
    required String fileName,
    required String? localPath,
    required int byteSize,
  }) async {
    final result = preflightByMetadata(
      fileName: fileName,
      byteSize: byteSize,
      hasLocalPath: localPath != null,
    );
    if (result.kind != DocumentKind.pdf ||
        !result.canOpen ||
        localPath == null) {
      return result;
    }

    try {
      final bytes = await File(localPath)
          .openRead(0, 8)
          .fold<List<int>>(<int>[], (all, part) => all..addAll(part));
      final signature = String.fromCharCodes(bytes.take(5));
      if (signature != '%PDF-') {
        return const DocumentPreflightResult(
          kind: DocumentKind.pdf,
          access: DocumentAccess.unavailable,
          title: '这个文件不是 PDF',
          message: '文件的实际内容和扩展名对不上。原件没有被修改。',
        );
      }
      return const DocumentPreflightResult(
        kind: DocumentKind.pdf,
        access: DocumentAccess.editable,
        title: '可以编辑',
        message: '会打开一份安全副本，可修改已有文字、填写表单或添加少量文字；原件始终不动。',
      );
    } on FileSystemException catch (error) {
      return DocumentPreflightResult(
        kind: DocumentKind.pdf,
        access: DocumentAccess.unavailable,
        title: '读取 PDF 失败',
        message: error.message,
      );
    }
  }

  @override
  Future<String> createWorkingCopy({
    required String sourcePath,
    required String displayName,
  }) async {
    final target = await _createWorkingCopy(sourcePath, displayName);
    return target.path;
  }
}

class _MobileDocxEngine implements DocxDocumentEngine {
  @override
  String get implementationName => 'docx_creator 1.3.2';

  @override
  Future<DocumentPreflightResult> preflight({
    required String fileName,
    required String? localPath,
    required int byteSize,
  }) async => preflightByMetadata(
    fileName: fileName,
    byteSize: byteSize,
    hasLocalPath: localPath != null,
  );

  @override
  Future<String> createWorkingCopy({
    required String sourcePath,
    required String displayName,
  }) async => (await _createWorkingCopy(sourcePath, displayName)).path;

  @override
  Future<String> openExternalCopy({
    required String sourcePath,
    required String displayName,
  }) async {
    final target = await _createWorkingCopy(sourcePath, displayName);
    // 不传 type：DOC/DOCX 的 MIME 在两个平台上不一致，交给系统按扩展名选应用。
    final result = await OpenFilex.open(target.path);
    if (result.type != ResultType.done) {
      throw FileSystemException('这台设备没有可以打开 Word 文档的应用。', target.path);
    }
    return target.path;
  }
}

/// 工作副本的保留时长。副本是完整的申请材料（护照、成绩单、雇主信），
/// 留在磁盘上没有意义，只是多一份可能泄露的拷贝。
const workingCopyRetention = Duration(hours: 24);

/// 永远只把副本交给外部程序，原件不出 App 的私有目录。
Future<File> _createWorkingCopy(String sourcePath, String displayName) async {
  final root = await getApplicationDocumentsDirectory();
  final workingDirectory = Directory(
    path.join(root.path, 'document-working-copies'),
  );
  await workingDirectory.create(recursive: true);
  await pruneWorkingCopies(workingDirectory);
  final safeName = displayName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final target = File(
    path.join(
      workingDirectory.path,
      '${DateTime.now().millisecondsSinceEpoch}_$safeName',
    ),
  );
  await File(sourcePath).copy(target.path);
  return target;
}

/// 清理过期工作副本。App 启动时调用一次。
///
/// 只在创建下一份副本时清理是不够的：用户打开一次护照扫描件之后再不碰文档工具，
/// 那份明文拷贝就会一直留在磁盘上。
Future<void> pruneStaleWorkingCopies() async {
  try {
    final root = await getApplicationDocumentsDirectory();
    await pruneWorkingCopies(
      Directory(path.join(root.path, 'document-working-copies')),
    );
  } on Exception {
    // 清理失败不该影响启动。
  }
}

/// 删除过期的工作副本。此前这个目录只增不减：用户每打开一份材料就永久多留一份
/// 明文拷贝，删掉原件也删不掉它。
Future<void> pruneWorkingCopies(Directory workingDirectory) async {
  if (!await workingDirectory.exists()) return;
  final cutoff = DateTime.now().subtract(workingCopyRetention);
  await for (final entity in workingDirectory.list()) {
    if (entity is! File) continue;
    try {
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) await entity.delete();
    } on FileSystemException {
      // 副本可能正被外部阅读器占用；下一轮再删，不要因此打不开文件。
    }
  }
}
