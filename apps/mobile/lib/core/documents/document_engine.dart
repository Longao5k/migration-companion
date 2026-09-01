enum DocumentKind { pdf, docx, legacyDoc, unsupported }

enum DocumentAccess { editable, readOnly, unavailable }

class DocumentPreflightResult {
  const DocumentPreflightResult({
    required this.kind,
    required this.access,
    required this.title,
    required this.message,
  });

  final DocumentKind kind;
  final DocumentAccess access;
  final String title;
  final String message;

  bool get canOpen => access != DocumentAccess.unavailable;
}

abstract interface class PdfDocumentEngine {
  String get implementationName;

  Future<DocumentPreflightResult> preflight({
    required String fileName,
    required String? localPath,
    required int byteSize,
  });

  /// Creates an application-owned working copy for the in-app editor.
  ///
  /// The source is never handed to the SDK and is never overwritten.
  Future<String> createWorkingCopy({
    required String sourcePath,
    required String displayName,
  });
}

abstract interface class DocxDocumentEngine {
  String get implementationName;

  Future<DocumentPreflightResult> preflight({
    required String fileName,
    required String? localPath,
    required int byteSize,
  });

  /// 与 PDF 相同：先复制出 App 自有的工作副本，再把副本交给外部程序。
  Future<String> openWorkingCopy({
    required String sourcePath,
    required String displayName,
  });
}
