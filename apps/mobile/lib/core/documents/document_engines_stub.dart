import 'document_engine.dart';
import 'document_preflight.dart';

PdfDocumentEngine createPdfDocumentEngine() => _BrowserPdfEngine();
DocxDocumentEngine createDocxDocumentEngine() => _MetadataDocxEngine();

class _BrowserPdfEngine implements PdfDocumentEngine {
  @override
  String get implementationName => '网页端（仅清单）';

  @override
  Future<String> openWorkingCopy({
    required String sourcePath,
    required String displayName,
  }) => throw UnsupportedError('网页端不打开设备文档');

  @override
  Future<DocumentPreflightResult> preflight({
    required String fileName,
    required String? localPath,
    required int byteSize,
  }) async => preflightByMetadata(
    fileName: fileName,
    byteSize: byteSize,
    hasLocalPath: false,
  );
}

class _MetadataDocxEngine implements DocxDocumentEngine {
  @override
  String get implementationName => '网页端（仅清单）';

  @override
  Future<String> openWorkingCopy({
    required String sourcePath,
    required String displayName,
  }) => throw UnsupportedError('网页端不打开设备文档');

  @override
  Future<DocumentPreflightResult> preflight({
    required String fileName,
    required String? localPath,
    required int byteSize,
  }) async => preflightByMetadata(
    fileName: fileName,
    byteSize: byteSize,
    hasLocalPath: false,
  );
}
