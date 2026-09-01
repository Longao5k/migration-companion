import 'dart:io';

import 'package:document_sdk/document_sdk.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'document_engine.dart';
import 'document_preflight.dart';

PdfDocumentEngine createPdfDocumentEngine() => DocumentSdkPdfEngine();
DocxDocumentEngine createDocxDocumentEngine() => _SystemViewerDocxEngine();

/// 自研 Document SDK 的宿主边界。
///
/// 先用元数据挡住缺文件和超限，再让 SDK 对实际字节逐份给出兼容等级和 capability。
/// 原件只用于创建 App 私有工作副本；编辑器打开副本，保存时再产出一个新的、经过
/// SDK 验证的文件，所以不会把用户材料原地覆盖。
class DocumentSdkPdfEngine implements PdfDocumentEngine {
  @override
  String get implementationName => 'Waymark 自研 PDF 引擎';

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

    final file = File(localPath);
    final sdk = DocumentSdk();
    try {
      final report = await sdk.probe(
        await file.readAsBytes(),
        fileName: fileName,
      );
      if (report.info.format != DocumentFormat.pdf) {
        return const DocumentPreflightResult(
          kind: DocumentKind.pdf,
          access: DocumentAccess.unavailable,
          title: '这个文件不是 PDF',
          message: '文件的实际内容和扩展名对不上。原件没有被修改。',
        );
      }
      final issueNote = report.issues.isEmpty
          ? ''
          : ' 另有 ${report.issues.length} 项兼容性提示，打开后会逐页说明。';
      if (report.canEdit) {
        return DocumentPreflightResult(
          kind: DocumentKind.pdf,
          access: DocumentAccess.editable,
          title: '可在 Waymark 内编辑',
          message: '这份 PDF 已通过兼容性检查；工具会按文件实际支持的能力开启。$issueNote',
        );
      }
      if (report.compatibility == CompatibilityLevel.readOnly) {
        return DocumentPreflightResult(
          kind: DocumentKind.pdf,
          access: DocumentAccess.readOnly,
          title: '可以查看，但不能保存修改',
          message: 'SDK 判断这份文件只能安全查看，因此不会显示保存编辑的入口。$issueNote',
        );
      }
      return DocumentPreflightResult(
        kind: DocumentKind.pdf,
        access: DocumentAccess.unavailable,
        title: '暂时打不开这份 PDF',
        message: report.issues.isEmpty
            ? 'SDK 不支持这份文件的结构，原件没有被修改。'
            : report.issues.first.message,
      );
    } on DocumentSdkException catch (error) {
      return DocumentPreflightResult(
        kind: DocumentKind.pdf,
        access: DocumentAccess.unavailable,
        title: 'PDF 兼容性检查失败',
        message: error.message,
      );
    } finally {
      await sdk.dispose();
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
