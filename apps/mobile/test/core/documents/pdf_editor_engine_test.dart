import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:docx_creator/docx_creator.dart' as docx;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

void main() {
  test('rewrites real PDF text and reopens the saved result', () async {
    final qaSource = Platform.environment['WAYMARK_PDF_QA_SOURCE'];
    final sourceBytes = qaSource == null
        ? docx.PdfExporter().exportToBytes(
            docx.DocxBuiltDocument(
              elements: [docx.DocxParagraph.text('Applicant Old Name')],
            ),
          )
        : await File(qaSource).readAsBytes();
    final controller = PdfEditingController(sourceBytes);
    addTearDown(controller.dispose);

    PdfContentElement? target;
    var pageIndex = 0;
    for (
      var page = 0;
      page < controller.document.pageCount && target == null;
      page++
    ) {
      for (final element in controller.elementsOn(page).elements) {
        final text = element.text;
        if (element.kind == PdfElementKind.text &&
            text != null &&
            text.trim().length > 2) {
          target = element;
          pageIndex = page;
          break;
        }
      }
    }
    expect(target, isNotNull);
    final original = target!.text!;
    final replacement = original.split('').reversed.join();
    final changed = controller.replaceTextInElement(
      pageIndex,
      target,
      original,
      replacement,
      const PdfTextStyle(),
    );
    expect(changed, greaterThan(0));

    final outputBytes = controller.bytes;
    final reopened = PdfEditingController(outputBytes);
    addTearDown(reopened.dispose);
    final savedTexts = <String>[
      for (var page = 0; page < reopened.document.pageCount; page++)
        ...reopened
            .elementsOn(page)
            .elements
            .map((element) => element.text ?? ''),
    ];
    expect(savedTexts, contains(replacement));

    final output = Platform.environment['WAYMARK_PDF_QA_OUTPUT'];
    if (output != null) {
      await File(output).parent.create(recursive: true);
      await File(output).writeAsBytes(outputBytes);
    }
  });
}
