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

  /// Creates an application-owned copy for the simple in-app DOCX editor.
  Future<String> createWorkingCopy({
    required String sourcePath,
    required String displayName,
  });

  /// Opens an application-owned copy in another app. Used for legacy .doc
  /// files and as a fallback for complex DOCX documents.
  Future<String> openExternalCopy({
    required String sourcePath,
    required String displayName,
  });
}
