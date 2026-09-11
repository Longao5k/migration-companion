import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../i18n/app_language.dart';
import 'docx_simple_editor.dart';

typedef DocxSaveCopy = Future<void> Function(
  Uint8List bytes,
  String suggestedName,
);

class DocxEditorScreen extends StatefulWidget {
  const DocxEditorScreen({
    required this.sourcePath,
    required this.displayName,
    this.onSaveCopy,
    super.key,
  });
  final String sourcePath;
  final String displayName;
  final DocxSaveCopy? onSaveCopy;

  @override
  State<DocxEditorScreen> createState() => _DocxEditorScreenState();
}

class _DocxEditorScreenState extends State<DocxEditorScreen> {
  SimpleDocxDocument? _document;
  Object? _error;
  bool _dirty = false;
  bool _saving = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final document = await SimpleDocxDocument.open(
        await File(widget.sourcePath).readAsBytes(),
      );
      if (mounted) setState(() => _document = document);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || !_dirty,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (await _confirmDiscard() && mounted) {
        setState(() => _allowPop = true);
        Navigator.of(this.context).pop();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.displayName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: tr(context, '用其他应用打开', 'Open in another app'),
            onPressed: _openExternal,
            icon: const Icon(Icons.open_in_new),
          ),
          IconButton(
            tooltip: tr(context, '保存副本', 'Save copy'),
            onPressed: _dirty && !_saving ? _save : null,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      floatingActionButton: _document == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addParagraph,
              icon: const Icon(Icons.add),
              label: Text(tr(context, '添加一段', 'Add paragraph')),
            ),
      body: _body(),
    ),
  );

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(
                  context,
                  '这个 Word 文档的结构太复杂，无法安全地在 App 内编辑。',
                  'This Word document is too complex for safe in-app editing.',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _openExternal,
                icon: const Icon(Icons.open_in_new),
                label: Text(tr(context, '用其他应用打开', 'Open in another app')),
              ),
            ],
          ),
        ),
      );
    }
    final doc = _document;
    if (doc == null) return const Center(child: CircularProgressIndicator());
    if (doc.paragraphs.isEmpty) {
      return Center(
        child: Text(
          tr(
            context,
            '没有找到可直接修改的普通段落。',
            'No directly editable text paragraphs were found.',
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: doc.paragraphs.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              tr(
                context,
                '点一段普通文字进行修改。表格、图片或复杂排版请用其他应用编辑，以免格式发生变化。',
                'Tap a plain paragraph to edit it. Use another app for tables, images or complex layout to avoid formatting changes.',
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final paragraphIndex = index - 1;
        final paragraph = doc.paragraphs[paragraphIndex];
        return Card(
          child: ListTile(
            title: Text(paragraph.text),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editParagraph(paragraphIndex, paragraph.text),
          ),
        );
      },
    );
  }

  Future<void> _editParagraph(int index, String original) async {
    final controller = TextEditingController(text: original);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, '修改文字', 'Edit text')),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 8,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, '取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(tr(context, '完成', 'Done')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value == original || !mounted) return;
    setState(() {
      _document!.replaceParagraph(index, value);
      _dirty = true;
    });
  }

  Future<void> _addParagraph() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, '添加一段文字', 'Add a paragraph')),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 8,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, '取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(tr(context, '添加', 'Add')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty || !mounted) return;
    setState(() {
      _document!.appendParagraph(value);
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final bytes = await _document!.export();
      final name = _copyName(widget.displayName);
      if (widget.onSaveCopy != null) {
        await widget.onSaveCopy!(bytes, name);
      } else {
        final output = await FilePicker.saveFile(
          fileName: name,
          bytes: bytes,
          mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          type: FileType.custom,
          allowedExtensions: const ['docx'],
        );
        if (output == null) return;
      }
      if (!mounted) return;
      setState(() => _dirty = false);
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

  Future<void> _openExternal() async {
    final result = await OpenFilex.open(widget.sourcePath);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              '没有找到能打开 Word 文档的应用。',
              'No app is available to open this Word document.',
            ),
          ),
        ),
      );
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
  return '${base}_edited.docx';
}
