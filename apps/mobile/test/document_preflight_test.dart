import 'package:flutter_test/flutter_test.dart';
import 'package:migration_companion/core/documents/document_engine.dart';
import 'package:migration_companion/core/documents/document_preflight.dart';

void main() {
  test('supported small files enter their editor', () {
    final pdf = preflightByMetadata(
      fileName: 'evidence.PDF',
      byteSize: 1024,
      hasLocalPath: true,
    );
    final docx = preflightByMetadata(
      fileName: 'statement.docx',
      byteSize: 1024,
      hasLocalPath: true,
    );
    expect(pdf.access, DocumentAccess.editable);
    expect(docx.access, DocumentAccess.editable);
  });

  test('small PDF on a device path proceeds to the PDF editor', () {
    final result = preflightByMetadata(
      fileName: 'evidence.PDF',
      byteSize: 1024,
      hasLocalPath: true,
    );
    expect(result.kind, DocumentKind.pdf);
    expect(result.access, DocumentAccess.editable);
    expect(result.canOpen, isTrue);
  });

  test('browser file never crosses into native viewer implicitly', () {
    final result = preflightByMetadata(
      fileName: 'evidence.pdf',
      byteSize: 1024,
      hasLocalPath: false,
    );
    expect(result.access, DocumentAccess.unavailable);
  });

  // 超限文件的按钮必须是禁用的：文案说「打不开」而按钮可按，比不提示更糟。
  test('oversize files are unavailable so the open button stays disabled', () {
    final largePdf = preflightByMetadata(
      fileName: 'scan.pdf',
      byteSize: maxPdfBytes + 1,
      hasLocalPath: true,
    );
    final largeDocx = preflightByMetadata(
      fileName: 'complex.docx',
      byteSize: maxDocxBytes + 1,
      hasLocalPath: true,
    );
    expect(largePdf.canOpen, isFalse);
    expect(largeDocx.canOpen, isFalse);
  });

  test('legacy doc is viewable rather than a dead end', () {
    final legacy = preflightByMetadata(
      fileName: 'legacy.doc',
      byteSize: 4096,
      hasLocalPath: true,
    );
    expect(legacy.kind, DocumentKind.legacyDoc);
    expect(legacy.canOpen, isTrue);
  });
}
