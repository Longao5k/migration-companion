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

  /// Creates an application-owned working copy and opens that copy.
  Future<String> openWorkingCopy({
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
}
