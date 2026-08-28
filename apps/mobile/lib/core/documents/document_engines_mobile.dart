import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'document_engine.dart';
import 'document_preflight.dart';

PdfDocumentEngine createPdfDocumentEngine() => SystemViewerPdfEngine();
DocxDocumentEngine createDocxDocumentEngine() => _SystemViewerDocxEngine();

/// 用系统自带的阅读器打开文档，不捆绑任何第三方文档 SDK。
///
/// 此前这里接的是 Apryse 免费评估版。ADR-011 明确规定「发布构建不得包含仅限评估、
/// 不允许终端用户使用的组件」，因此评估版不能进商店包——那是许可违约，不是风格问题。
/// 在自研 SDK 完成或购买生产许可之前，第一版只提供**查看**：把文件交给系统阅读器，
/// 不承诺批注、表单、签名和页面整理。
///
/// 保留的仍然是我们自己的逻辑：先做兼容性预检、校验 `%PDF-` 文件头、复制出 App 自有的
/// 工作副本再交给外部程序——原件在任何情况下都不被外部程序直接持有。
class SystemViewerPdfEngine implements PdfDocumentEngine {
  @override
  String get implementationName => '系统阅读器（仅查看）';

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
    if (result.kind != DocumentKind.pdf || localPath == null) return result;

    final file = File(localPath);
    final header = await file
        .openRead(0, 5)
        .fold<List<int>>(<int>[], (bytes, part) => bytes..addAll(part));
    if (header.length < 5 || String.fromCharCodes(header) != '%PDF-') {
      return const DocumentPreflightResult(
        kind: DocumentKind.pdf,
        access: DocumentAccess.unavailable,
        title: '这个文件不是 PDF',
        message: '文件的实际内容和扩展名对不上，为了不损坏原件，我们不会打开它。',
      );
    }
    // 编辑能力尚未提供，如实降级为只读，不用「已保存」掩盖做不到的事。
    return const DocumentPreflightResult(
      kind: DocumentKind.pdf,
      access: DocumentAccess.readOnly,
      title: '可以查看',
      message: '当前版本用系统阅读器打开 PDF。批注和签名还在开发中。',
    );
  }

  @override
  Future<String> openWorkingCopy({
    required String sourcePath,
    required String displayName,
  }) async {
    final target = await _createWorkingCopy(sourcePath, displayName);
    final result = await OpenFilex.open(target.path, type: 'application/pdf');
    if (result.type != ResultType.done) {
      throw FileSystemException('这台设备没有可以打开 PDF 的应用。', target.path);
    }
    return target.path;
  }
}

class _SystemViewerDocxEngine implements DocxDocumentEngine {
  @override
  String get implementationName => '系统阅读器（仅查看）';

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
  Future<String> openWorkingCopy({
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
