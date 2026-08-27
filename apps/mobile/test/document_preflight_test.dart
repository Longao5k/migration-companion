import 'package:flutter_test/flutter_test.dart';
import 'package:migration_companion/core/documents/document_engine.dart';
import 'package:migration_companion/core/documents/document_preflight.dart';

void main() {
  test('small PDF is editable only when a device path exists', () {
    final result = preflightByMetadata(
      fileName: 'evidence.PDF',
      byteSize: 1024,
      hasLocalPath: true,
    );
    expect(result.kind, DocumentKind.pdf);
    expect(result.access, DocumentAccess.editable);
  });

  test('browser file never crosses into native editor implicitly', () {
    final result = preflightByMetadata(
      fileName: 'evidence.pdf',
      byteSize: 1024,
      hasLocalPath: false,
    );
    expect(result.access, DocumentAccess.unavailable);
  });

  test('large DOCX and legacy DOC explicitly downgrade to read only', () {
    final largeDocx = preflightByMetadata(
      fileName: 'complex.docx',
      byteSize: maxDocxBytes + 1,
      hasLocalPath: true,
    );
    final legacy = preflightByMetadata(
      fileName: 'legacy.doc',
      byteSize: 4096,
      hasLocalPath: true,
    );
    expect(largeDocx.access, DocumentAccess.readOnly);
    expect(legacy.access, DocumentAccess.readOnly);
  });
}
