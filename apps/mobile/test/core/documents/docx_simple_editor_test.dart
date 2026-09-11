import 'dart:io';

import 'package:docx_creator/docx_creator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migration_companion/core/documents/docx_simple_editor.dart';

void main() {
  test(
    'edits and appends DOCX paragraphs while keeping their structure',
    () async {
      final source = DocxBuiltDocument(
        elements: [
          const DocxParagraph(
            children: [DocxText('Applicant: '), DocxText.bold('Old Name')],
          ),
          DocxParagraph.text('Date: 1 January 2025'),
        ],
      );
      final sourceBytes = await DocxExporter().exportToBytes(source);

      final editor = await SimpleDocxDocument.open(sourceBytes);
      expect(editor.paragraphs.map((item) => item.text), [
        'Applicant: Old Name',
        'Date: 1 January 2025',
      ]);

      editor
        ..replaceParagraph(0, 'Applicant: New Name')
        ..replaceParagraph(1, 'Date: 11 September 2026')
        ..appendParagraph('Additional statement');

      final editedBytes = await editor.export();
      final qaOutput = Platform.environment['WAYMARK_DOCX_QA_OUTPUT'];
      if (qaOutput != null) {
        await File(qaOutput).parent.create(recursive: true);
        await File(qaOutput).writeAsBytes(editedBytes);
        final pdfOutput = Platform.environment['WAYMARK_DOCX_QA_PDF_OUTPUT'];
        if (pdfOutput != null) {
          await File(pdfOutput)
              .writeAsBytes(PdfExporter().exportToBytes(editor.document));
        }
      }
      final reopened = await SimpleDocxDocument.open(editedBytes);
      expect(reopened.paragraphs.map((item) => item.text), [
        'Applicant: New Name',
        'Date: 11 September 2026',
        'Additional statement',
      ]);
    },
  );
}
