import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

typedef PdfSaveCopy = Future<void> Function(
  Uint8List bytes,
  String suggestedName,
);

/// A deliberately small mobile PDF editor for quick text and form changes.
class PdfEditorScreen extends StatefulWidget {
  const PdfEditorScreen({
    required this.sourcePath,
    required this.displayName,
    this.onSaveCopy,
    super.key,
  });

  final String sourcePath;
  final String displayName;
  final PdfSaveCopy? onSaveCopy;

  @override
  State<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends State<PdfEditorScreen> {
  Uint8List? _bytes;
  Object? _error;
  bool _dirty = false;
  bool _saved = false;
  bool _allowPop = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.sourcePath).readAsBytes();
      if (mounted) setState(() => _bytes = bytes);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || !_dirty || _saved,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (await _confirmDiscard() && mounted) {
        setState(() => _allowPop = true);
        Navigator.of(this.context).pop();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.displayName, overflow: TextOverflow.ellipsis),
            Text(
              tr(context, '简单编辑 · 保存为新副本', 'Simple edit · save a new copy'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: _body(),
    ),
  );

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tr(
              context,
              '这份 PDF 无法打开：$_error',
              'This PDF could not be opened: $_error',
            ),
          ),
        ),
      );
    }
    final bytes = _bytes;
    if (bytes == null) return const Center(child: CircularProgressIndicator());
    return PdfEditorView(
      bytes: bytes,
      documentId: widget.sourcePath,
      features: const PdfEditorFeatures(
        author: false,
        authorEditable: false,
        reflowView: false,
        pageColorEditable: false,
        annotationLibrary: false,
        propertiesPanel: false,
        pageEditing: false,
        flatten: false,
        colorProcessing: false,
        tools: {
          PdfEditTool.select,
          PdfEditTool.content,
          PdfEditTool.freeText,
          PdfEditTool.form,
          PdfEditTool.ink,
          PdfEditTool.signature,
        },
      ),
      saveButtonLabel: tr(context, '保存副本', 'Save copy'),
      onDocumentChanged: (_) {
        if (mounted && !_dirty) setState(() => _dirty = true);
      },
      onSave: (edited) => unawaited(_save(edited)),
      onSaveAs: (edited) => unawaited(_save(edited)),
    );
  }

  Future<void> _save(Uint8List bytes) async {
    if (_saving) return;
    setState(() => _saving = true);
    final name = _copyName(widget.displayName);
    try {
      if (widget.onSaveCopy != null) {
        await widget.onSaveCopy!(bytes, name);
      } else {
        final output = await FilePicker.saveFile(
          fileName: name,
          bytes: bytes,
          mimeType: 'application/pdf',
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
        );
        if (output == null) return;
      }
      if (!mounted) return;
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, '已保存新副本', 'New copy saved'))),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, '保存失败：$error', 'Save failed: $error')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr(context, '放弃未保存的修改？', 'Discard unsaved changes?')),
          content: Text(
            tr(context, '原件不会受影响。', 'The original file will not be changed.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr(context, '继续编辑', 'Keep editing')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(context, '放弃', 'Discard')),
            ),
          ],
        ),
      ) ??
      false;
}

String _copyName(String original) {
  final dot = original.lastIndexOf('.');
  final base = dot > 0 ? original.substring(0, dot) : original;
  return '${base}_edited.pdf';
}
