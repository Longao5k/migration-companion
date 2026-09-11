import 'dart:typed_data';

import 'package:docx_creator/docx_creator.dart';

class EditableDocxParagraph {
  const EditableDocxParagraph({required this.elementIndex, required this.text});
  final int elementIndex;
  final String text;
}

class SimpleDocxDocument {
  SimpleDocxDocument._(this.document, this.paragraphs);

  DocxBuiltDocument document;
  final List<EditableDocxParagraph> paragraphs;

  static Future<SimpleDocxDocument> open(Uint8List bytes) async {
    final document = await DocxReader.loadFromBytes(bytes);
    final paragraphs = <EditableDocxParagraph>[];
    for (var i = 0; i < document.elements.length; i++) {
      final node = document.elements[i];
      if (node is! DocxParagraph) continue;
      final text = node.children
          .whereType<DocxText>()
          .map((run) => run.content)
          .join();
      if (text.trim().isNotEmpty) {
        paragraphs.add(EditableDocxParagraph(elementIndex: i, text: text));
      }
    }
    return SimpleDocxDocument._(document, paragraphs);
  }

  void replaceParagraph(int paragraphListIndex, String text) {
    final target = paragraphs[paragraphListIndex];
    final elements = List<DocxNode>.of(document.elements);
    final paragraph = elements[target.elementIndex] as DocxParagraph;
    var used = false;
    final children = paragraph.children
        .map((child) {
          if (child is! DocxText) return child;
          if (!used) {
            used = true;
            return child.copyWith(content: text);
          }
          return child.copyWith(content: '');
        })
        .toList(growable: false);
    elements[target.elementIndex] = paragraph.copyWith(children: children);
    document = _withElements(document, elements);
    paragraphs[paragraphListIndex] = EditableDocxParagraph(
      elementIndex: target.elementIndex,
      text: text,
    );
  }

  void appendParagraph(String text) {
    if (text.trim().isEmpty) return;
    final elements = List<DocxNode>.of(document.elements)
      ..add(DocxParagraph.text(text));
    final index = elements.length - 1;
    document = _withElements(document, elements);
    paragraphs.add(EditableDocxParagraph(elementIndex: index, text: text));
  }

  Future<Uint8List> export() => DocxExporter().exportToBytes(document);
}

DocxBuiltDocument _withElements(
  DocxBuiltDocument source,
  List<DocxNode> elements,
) => DocxBuiltDocument(
  elements: List.unmodifiable(elements),
  section: source.section,
  fonts: source.fonts,
  footnotes: source.footnotes,
  endnotes: source.endnotes,
  stylesXml: source.stylesXml,
  numberingXml: source.numberingXml,
  settingsXml: source.settingsXml,
  fontTableXml: source.fontTableXml,
  fontTableRelsXml: source.fontTableRelsXml,
  themeXml: source.themeXml,
  contentTypesXml: source.contentTypesXml,
  rootRelsXml: source.rootRelsXml,
  headerBgXml: source.headerBgXml,
  headerBgRelsXml: source.headerBgRelsXml,
  footnotesXml: source.footnotesXml,
  endnotesXml: source.endnotesXml,
  numberingRelsXml: source.numberingRelsXml,
  numberingImages: source.numberingImages,
  theme: source.theme,
);
