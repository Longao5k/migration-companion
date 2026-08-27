import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdftron_flutter/pdftron_flutter.dart';

import 'document_engine.dart';
import 'document_preflight.dart';

PdfDocumentEngine createPdfDocumentEngine() => ApryseEvaluationPdfEngine();
DocxDocumentEngine createDocxDocumentEngine() => _MetadataDocxEngine();

class ApryseEvaluationPdfEngine implements PdfDocumentEngine {
  static bool _initialized = false;

  @override
  String get implementationName => 'Apryse 免费评估适配器';

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
        title: '文件内容不是有效 PDF',
        message: '扩展名与文件内容不一致，因此不会交给编辑器或覆盖原件。',
      );
    }
    return result;
  }

  @override
  Future<String> openWorkingCopy({
    required String sourcePath,
    required String displayName,
  }) async {
    final root = await getApplicationDocumentsDirectory();
    final workingDirectory = Directory(
      path.join(root.path, 'document-working-copies'),
    );
    await workingDirectory.create(recursive: true);
    final safeName = displayName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final target = File(
      path.join(
        workingDirectory.path,
        '${DateTime.now().millisecondsSinceEpoch}_$safeName',
      ),
    );
    await File(sourcePath).copy(target.path);
    if (!_initialized) {
      const licenseKey = String.fromEnvironment('APRYSE_LICENSE_KEY');
      await PdftronFlutter.initialize(licenseKey);
      _initialized = true;
    }
    final config = Config()..multiTabEnabled = false;
    await PdftronFlutter.openDocument(target.path, config: config);
    return target.path;
  }
}

class _MetadataDocxEngine implements DocxDocumentEngine {
  @override
  String get implementationName => 'ONLYOFFICE 试用适配器';

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
}
