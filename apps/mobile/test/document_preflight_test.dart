import 'package:flutter_test/flutter_test.dart';
import 'package:migration_companion/core/documents/document_engine.dart';
import 'package:migration_companion/core/documents/document_preflight.dart';

void main() {
  // 元数据预检不能猜 capability。PDF 的 editable 只能由原生 document_sdk probe
  // 返回，网页与 DOC/DOCX 仍不会仅凭扩展名承诺编辑。
  test('metadata alone never promises editability', () {
    const names = [
      'evidence.PDF',
      'evidence.pdf',
      'statement.docx',
      'legacy.doc',
      'notes.txt',
    ];
    for (final name in names) {
      for (final size in [1024, maxDocxBytes + 1, maxPdfBytes + 1]) {
        final result = preflightByMetadata(
          fileName: name,
          byteSize: size,
          hasLocalPath: true,
        );
        expect(
          result.access,
          isNot(DocumentAccess.editable),
          reason: '$name @ $size bytes 仅凭元数据声称可编辑',
        );
      }
    }
  });

  test('small PDF on a device path proceeds to SDK compatibility check', () {
    final result = preflightByMetadata(
      fileName: 'evidence.PDF',
      byteSize: 1024,
      hasLocalPath: true,
    );
    expect(result.kind, DocumentKind.pdf);
    expect(result.access, DocumentAccess.readOnly);
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
