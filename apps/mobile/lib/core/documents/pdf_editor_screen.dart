import 'dart:async';
import 'dart:io';

import 'package:document_sdk/document_sdk_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/app_language.dart';

typedef PdfSaveCopy = Future<void> Function(
  Uint8List bytes,
  String suggestedName,
);

/// Product host for the self-built Document SDK.
///
/// [sourcePath] must point at an application-owned working copy. The SDK never
/// receives the user's source file and every save creates another file.
class PdfEditorScreen extends StatefulWidget {
  const PdfEditorScreen({
    required this.sourcePath,
    required this.displayName,
    this.onSaveCopy,
    super.key,
  });

  final String sourcePath;
  final String displayName;

  /// When opened from a project, saving adds a new attachment beside the
  /// original. When null, the platform save dialog is used.
  final PdfSaveCopy? onSaveCopy;

  @override
  State<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends State<PdfEditorScreen> {
  final _sdk = DocumentSdk();
  final _viewerKey = GlobalKey<PdfViewerState>();

  DocumentSdkSession? _session;
  PdfDocumentController? _controller;
  String? _error;
  String? _status;
  var _opening = true;
  var _zoom = 1.0;
  var _page = 0;
  var _noteMode = false;
  var _signMode = false;
  var _allowPop = false;
  var _copySaved = false;
  var _editWarningShown = false;
  Uint8List? _latinReplacementFont;
  Uint8List? _wideReplacementFont;
  final List<List<DisplayPoint>> _strokes = <List<DisplayPoint>>[];
  int? _strokePage;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _controller?.dispose();
    unawaited(_closeSdk());
    super.dispose();
  }

  Future<void> _closeSdk() async {
    await _session?.close();
    await _sdk.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return PopScope(
      canPop: _allowPop || controller?.isDirty != true || _copySaved,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (!mounted) return;
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
                tr(
                  context,
                  '编辑副本 · 原件保持不变',
                  'Editing a copy · original stays unchanged',
                ),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: tr(context, '搜索文字', 'Search text'),
              onPressed: controller == null ? null : _search,
              icon: const Icon(Icons.search),
            ),
            IconButton(
              tooltip: tr(context, '撤销', 'Undo'),
              onPressed: controller?.canUndo == true ? _undo : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: tr(context, '重做', 'Redo'),
              onPressed: controller?.canRedo == true ? _redo : null,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              tooltip: widget.onSaveCopy == null
                  ? tr(context, '另存到设备', 'Save to device')
                  : tr(context, '另存到文件库', 'Save to files'),
              onPressed:
                  controller != null && !controller.isBusy && _can('save_copy')
                  ? _saveCopy
                  : null,
              icon: const Icon(Icons.save_outlined),
            ),
            PopupMenuButton<_PdfMenuAction>(
              tooltip: tr(context, '更多工具', 'More tools'),
              onSelected: _runMenuAction,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _PdfMenuAction.forms,
                  child: Text(
                    tr(context, '填写当前页表单', 'Fill fields on this page'),
                  ),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.annotations,
                  child: Text(
                    tr(context, '管理当前页批注', 'Manage page annotations'),
                  ),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.moveUp,
                  child: Text(tr(context, '当前页向前移动', 'Move page earlier')),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.moveDown,
                  child: Text(tr(context, '当前页向后移动', 'Move page later')),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.extract,
                  child: Text(tr(context, '导出当前页', 'Export this page')),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.merge,
                  child: Text(tr(context, '合并另一份 PDF', 'Merge another PDF')),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.flatten,
                  child: Text(
                    tr(context, '固定批注与表单内容', 'Flatten annotations and forms'),
                  ),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.exportDevice,
                  child: Text(tr(context, '导出副本到设备', 'Export copy to device')),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.compatibility,
                  child: Text(tr(context, '文件兼容性', 'File compatibility')),
                ),
              ],
            ),
          ],
        ),
        body: _buildBody(controller),
        bottomNavigationBar: controller == null
            ? null
            : _StatusBar(
                dirty: controller.isDirty && !_copySaved,
                saved: _copySaved,
                status: _status,
              ),
      ),
    );
  }

  Widget _buildBody(PdfDocumentController? controller) {
    if (_opening) return const Center(child: CircularProgressIndicator());
    if (_error case final error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 14),
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(tr(context, '返回', 'Back')),
              ),
            ],
          ),
        ),
      );
    }
    if (controller == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.loadError case final error?) {
          return Center(child: Text(_describe(error)));
        }
        return Column(
          children: [
            _CompatibilityStrip(
              report: controller.preflight,
              onTap: _showCompatibility,
            ),
            if (_can('pdf_edit_text'))
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.tertiaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.touch_app_outlined, size: 19),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        tr(
                          context,
                          '点击任意一行文字，然后选择“替换文字”或“删除文字”。',
                          'Tap any line, then choose Replace text or Delete text.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            _buildToolbar(controller),
            if (controller.selection case final selection?)
              _SelectionStrip(
                selection: selection,
                onCopy: _copySelection,
                onReplace: _can('pdf_edit_text') ? _replaceSelection : null,
                onDelete: _can('pdf_edit_text') ? _deleteSelection : null,
                onMarkup: _markSelection,
                onClear: controller.clearSelection,
              ),
            Expanded(
              child: PdfViewer(
                key: _viewerKey,
                controller: controller,
                zoom: _zoom,
                onZoomChanged: (value) => setState(() => _zoom = value),
                onPageChanged: (value) => setState(() => _page = value),
                onPageTap: _noteMode ? _addNoteAt : null,
                onPageStroke: _signMode ? _collectStroke : null,
                showCompatibilityBanners: true,
                selectTextBlockOnTap:
                    !_noteMode && !_signMode && _can('pdf_edit_text'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(PdfDocumentController controller) {
    final canEdit = controller.preflight.canEdit && !controller.isBusy;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: tr(context, '上一页', 'Previous page'),
              onPressed: _page > 0 ? () => _goToPage(_page - 1) : null,
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            Text(
              '${controller.pageCount == 0 ? 0 : _page + 1}/${controller.pageCount}',
            ),
            IconButton(
              tooltip: tr(context, '下一页', 'Next page'),
              onPressed: _page + 1 < controller.pageCount
                  ? () => _goToPage(_page + 1)
                  : null,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: tr(context, '缩小', 'Zoom out'),
              onPressed: _zoom > 0.3
                  ? () => setState(() => _zoom = (_zoom / 1.25).clamp(0.25, 6))
                  : null,
              icon: const Icon(Icons.zoom_out),
            ),
            Text('${(_zoom * 100).round()}%'),
            IconButton(
              tooltip: tr(context, '放大', 'Zoom in'),
              onPressed: _zoom < 6
                  ? () => setState(() => _zoom = (_zoom * 1.25).clamp(0.25, 6))
                  : null,
              icon: const Icon(Icons.zoom_in),
            ),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              tooltip: tr(context, '旋转当前页', 'Rotate this page'),
              onPressed: canEdit && _can('pdf_rotate_pages') ? _rotate : null,
              icon: const Icon(Icons.rotate_right),
            ),
            IconButton(
              tooltip: tr(context, '删除当前页', 'Delete this page'),
              onPressed:
                  canEdit &&
                      controller.pageCount > 1 &&
                      _can('pdf_delete_pages')
                  ? _deletePage
                  : null,
              icon: const Icon(Icons.delete_outline),
            ),
            IconButton(
              tooltip: _noteMode
                  ? tr(context, '点按页面放置便签', 'Tap the page to place a note')
                  : tr(context, '添加便签', 'Add note'),
              isSelected: _noteMode,
              onPressed: canEdit && _can('pdf_annotate_text')
                  ? _toggleNote
                  : null,
              icon: const Icon(Icons.add_comment_outlined),
              selectedIcon: const Icon(Icons.add_comment),
            ),
            IconButton(
              tooltip: _signMode
                  ? tr(
                      context,
                      '正在手写；完成后点勾',
                      'Drawing · tap the tick when finished',
                    )
                  : tr(context, '手写签名或批注', 'Draw or sign'),
              isSelected: _signMode,
              onPressed: canEdit && _can('pdf_annotate_ink')
                  ? _toggleSigning
                  : null,
              icon: const Icon(Icons.draw_outlined),
              selectedIcon: const Icon(Icons.draw),
            ),
            if (_signMode)
              IconButton.filled(
                tooltip: _strokes.isEmpty
                    ? tr(context, '请先在页面上书写', 'Draw on the page first')
                    : tr(context, '写入 PDF', 'Apply to PDF'),
                onPressed: _strokes.isEmpty ? null : _finishSigning,
                icon: const Icon(Icons.check),
              ),
            if (controller.searchResults?.hits.isNotEmpty == true) ...[
              IconButton(
                tooltip: tr(context, '上一个搜索结果', 'Previous search result'),
                onPressed: () => _stepSearch(next: false),
                icon: const Icon(Icons.navigate_before),
              ),
              Text(
                '${controller.activeHitIndex + 1}/${controller.searchResults!.hits.length}',
              ),
              IconButton(
                tooltip: tr(context, '下一个搜索结果', 'Next search result'),
                onPressed: () => _stepSearch(next: true),
                icon: const Icon(Icons.navigate_next),
              ),
            ],
            if (controller.isBusy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _open() async {
    Uint8List bytes;
    try {
      bytes = await File(widget.sourcePath).readAsBytes();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _opening = false;
          _error = tr(
            context,
            '读取工作副本失败：$error',
            'Could not read the working copy: $error',
          );
        });
      }
      return;
    }

    String? password;
    var wrongPassword = false;
    while (mounted) {
      try {
        final session = await _sdk.open(
          bytes,
          fileName: widget.displayName,
          options: OpenOptions(password: password),
        );
        final controller = PdfDocumentController(session);
        await controller.load();
        if (!mounted) {
          controller.dispose();
          await session.close();
          return;
        }
        setState(() {
          _session = session;
          _controller = controller;
          _opening = false;
          _status = password == null
              ? tr(
                  context,
                  '点按文字可替换，拖选文字可复制或标记。',
                  'Tap text to replace it, or drag to copy and mark text.',
                )
              : tr(
                  context,
                  '已用密码打开；受保护的内容可能只读。',
                  'Opened with a password; protected content may be read-only.',
                );
        });
        return;
      } on DocumentSdkException catch (error) {
        final needsPassword =
            error.code == 'password_required' ||
            error.code == 'invalid_password';
        if (!needsPassword) {
          setState(() {
            _opening = false;
            _error = _describe(error);
          });
          return;
        }
        wrongPassword = error.code == 'invalid_password';
        password = await _promptPassword(wrongPassword);
        if (password == null) {
          if (mounted) {
            setState(() {
              _opening = false;
              _error = tr(
                context,
                '这份 PDF 需要密码才能打开。',
                'This PDF needs a password to open.',
              );
            });
          }
          return;
        }
      } on Object catch (error) {
        if (mounted) {
          setState(() {
            _opening = false;
            _error = _describe(error);
          });
        }
        return;
      }
    }
  }

  bool _can(String capability) =>
      _controller?.preflight.capabilities.contains(capability) == true;

  Future<void> _goToPage(int index) async {
    await _viewerKey.currentState?.goToPage(
      index,
      duration: const Duration(milliseconds: 220),
    );
    if (mounted) setState(() => _page = index);
  }

  Future<void> _rotate() => _execute(
    PdfRotatePagesCommand(pages: [_page], clockwiseDegrees: 90),
    '已旋转第 ${_page + 1} 页',
    'Page ${_page + 1} rotated',
  );

  Future<void> _deletePage() async {
    if (!await _confirm(
      tr(context, '删除当前页？', 'Delete this page?'),
      tr(
        context,
        '只会从编辑副本中删除，原始 PDF 不受影响。',
        'Only the editing copy will change. The original PDF is unaffected.',
      ),
    )) {
      return;
    }
    await _execute(
      PdfDeletePagesCommand(pages: [_page]),
      '已删除一页',
      'Page deleted',
    );
    final count = _controller?.pageCount ?? 0;
    if (mounted) {
      setState(() => _page = count == 0 ? 0 : _page.clamp(0, count - 1));
    }
  }

  Future<void> _movePage(int delta) async {
    final controller = _controller;
    if (controller == null || !_can('pdf_reorder_pages')) return;
    final target = (_page + delta).clamp(0, controller.pageCount - 1);
    if (target == _page) {
      setState(
        () => _status = delta < 0
            ? tr(context, '已经是第一页', 'This is already the first page')
            : tr(context, '已经是最后一页', 'This is already the last page'),
      );
      return;
    }
    final order = List<int>.generate(controller.pageCount, (index) => index);
    final moving = order.removeAt(_page);
    order.insert(target, moving);
    await _execute(
      PdfReorderPagesCommand(order: order),
      '已移动当前页',
      'Page moved',
    );
    await _goToPage(target);
  }

  Future<void> _execute(
    DocumentCommand command,
    String successZh,
    String successEn,
  ) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final receipt = await controller.execute(command);
      if (receipt.changed) _copySaved = false;
      if (!mounted) return;
      setState(() {
        _status = receipt.changed
            ? tr(
                context,
                '$successZh；另存副本后才会保留。',
                '$successEn. Save a copy to keep it.',
              )
            : tr(context, '没有内容发生变化。', 'Nothing changed.');
      });
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _undo() async {
    try {
      final changed = await _controller?.undo() ?? false;
      if (changed) _copySaved = false;
      if (mounted) {
        setState(() => _status = tr(context, '已撤销上一步', 'Last change undone'));
      }
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _redo() async {
    try {
      final changed = await _controller?.redo() ?? false;
      if (changed) _copySaved = false;
      if (mounted) {
        setState(() => _status = tr(context, '已重做', 'Change restored'));
      }
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _search() async {
    var queryValue = '';
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, '搜索这份 PDF', 'Search this PDF')),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(labelText: tr(context, '关键词', 'Keyword')),
          onChanged: (value) => queryValue = value,
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(context, '取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(queryValue.trim()),
            child: Text(tr(context, '搜索', 'Search')),
          ),
        ],
      ),
    );
    if (query == null || query.isEmpty) return;
    try {
      final results = await _controller?.search(query);
      final hit = _controller?.activeHit;
      if (hit != null) {
        await _goToPage(hit.pageIndex);
        final bounds = _textBounds(hit.quads);
        if (bounds != null) {
          await _controller?.selectRect(hit.pageIndex, bounds);
        }
      }
      if (!mounted || results == null) return;
      setState(() {
        _status = results.hits.isEmpty
            ? tr(
                context,
                '没有找到。扫描件或不可映射文字可能无法搜索。',
                'No results. Scanned or unmapped text may not be searchable.',
              )
            : tr(
                context,
                '找到 ${results.hits.length} 处',
                '${results.hits.length} results found',
              );
      });
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _stepSearch({required bool next}) async {
    final hit = next ? _controller?.nextHit() : _controller?.previousHit();
    if (hit != null) await _goToPage(hit.pageIndex);
  }

  Future<void> _copySelection() async {
    final selection = _controller?.selection;
    if (selection == null || selection.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: selection.text));
    if (!mounted) return;
    setState(() {
      _status = selection.isComplete
          ? tr(
              context,
              '已复制 ${selection.text.runes.length} 个字符',
              '${selection.text.runes.length} characters copied',
            )
          : tr(
              context,
              '已复制，但当前页有无法可靠映射的文字，内容可能不完整。',
              'Copied, but some text on this page could not be mapped reliably.',
            );
    });
  }

  Future<void> _replaceSelection() async {
    final controller = _controller;
    final selection = controller?.selection;
    if (controller == null || selection == null || selection.text.isEmpty) {
      return;
    }
    if (!await _explainOverlayEditing()) return;
    if (!mounted) return;

    final replacement = await _promptText(
      title: tr(context, '替换所选文字', 'Replace selected text'),
      label: tr(context, '新文字', 'New text'),
      initial: selection.text,
      maxLines: 3,
    );
    if (replacement == null || replacement == selection.text) return;

    try {
      final font = await _fontFor(replacement);
      if (_needsEmbeddedFont(replacement) && font == null) return;
      final receipt = await controller.replaceSelectionText(
        replacement,
        font: font,
      );
      if (receipt.changed) _copySaved = false;
      if (!mounted) return;
      controller.clearSelection();
      setState(() {
        _status = receipt.changed
            ? tr(
                context,
                '文字已替换，保存副本后生效。',
                'Text replaced. Save a copy to keep the change.',
              )
            : tr(context, '文字没有变化。', 'Text was not changed.');
      });
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _deleteSelection() async {
    final controller = _controller;
    final selection = controller?.selection;
    if (controller == null || selection == null || selection.text.isEmpty) {
      return;
    }
    if (!await _explainOverlayEditing()) return;
    if (!mounted) return;
    if (!await _confirm(
      tr(context, '删除所选文字？', 'Delete selected text?'),
      tr(
        context,
        '文字会从页面上移除；原始文件保持不变。',
        'The text will be removed from the page. The original file stays unchanged.',
      ),
    )) {
      return;
    }
    try {
      final receipt = await controller.deleteSelectionText();
      if (receipt.changed) _copySaved = false;
      if (!mounted) return;
      controller.clearSelection();
      setState(() {
        _status = receipt.changed
            ? tr(
                context,
                '文字已删除，保存副本后生效。',
                'Text deleted. Save a copy to keep the change.',
              )
            : tr(context, '文字没有变化。', 'Text was not changed.');
      });
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<bool> _explainOverlayEditing() async {
    if (_editWarningShown) return true;
    final accepted = await _confirm(
      tr(context, '关于文字编辑', 'About text editing'),
      tr(
        context,
        '这个版本会在原文字位置写入新的可见内容，保存和打印结果会保留修改。'
            '由于不会改写 PDF 内部原始文字指令，其他阅读器搜索或复制时仍可能找到被替换的旧文字。',
        'This version writes new visible content over the original position, and the saved or printed result keeps the change. '
            'Because the original PDF text instructions are preserved, other readers may still find the old text when searching or copying.',
      ),
    );
    if (accepted) _editWarningShown = true;
    return accepted;
  }

  bool _needsEmbeddedFont(String value) =>
      value.runes.any((rune) => rune < 0x20 || rune > 0x7e);

  Future<Uint8List?> _fontFor(String replacement) async {
    final needsWideFont = _needsEmbeddedFont(replacement);
    final cached = needsWideFont ? _wideReplacementFont : _latinReplacementFont;
    if (cached != null) return cached;

    if (Platform.isAndroid) {
      final candidates = needsWideFont
          ? const [
              '/system/fonts/NotoSansCJK-Regular.ttc',
              '/system/fonts/NotoSansSC-Regular.ttf',
            ]
          : const [
              '/system/fonts/Roboto-Regular.ttf',
              '/system/fonts/NotoSans-Regular.ttf',
            ];
      for (final path in candidates) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (needsWideFont) {
            _wideReplacementFont = bytes;
          } else {
            _latinReplacementFont = bytes;
          }
          return bytes;
        }
      }
    }

    if (!needsWideFont) return null;

    if (!mounted) return null;
    final choose = await _confirm(
      tr(context, '需要字体文件', 'A font file is needed'),
      tr(
        context,
        '这段文字包含非英文字符。请选择一个 TTF 或 TTC 字体，字体会被精简并嵌入保存的 PDF。',
        'This text contains non-English characters. Choose a TTF or TTC font; the SDK will subset and embed it in the saved PDF.',
      ),
    );
    if (!choose) return null;
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'ttc'],
    );
    if (picked == null) return null;
    _wideReplacementFont = await picked.readAsBytes();
    return _wideReplacementFont;
  }

  Future<void> _markSelection(String markup) async {
    final controller = _controller;
    if (controller == null || !_can('pdf_annotate_markup')) return;
    try {
      final receipt = await controller.markSelection(
        markup,
        color: const DisplayColor(red: 1, green: 0.82, blue: 0.1, alpha: 1),
        opacity: 0.5,
        author: 'Waymark user',
      );
      if (receipt != null) _copySaved = false;
      if (!mounted) return;
      setState(
        () => _status = receipt == null
            ? tr(context, '请先选择文字', 'Select text first')
            : tr(context, '已添加文字标记', 'Text markup added'),
      );
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  void _toggleNote() {
    setState(() {
      _noteMode = !_noteMode;
      if (_noteMode) {
        _cancelSigning();
        _status = tr(
          context,
          '点按页面上的位置以添加便签',
          'Tap a position on the page to add a note',
        );
      }
    });
  }

  Future<void> _addNoteAt(int pageIndex, DisplayPoint point) async {
    final text = await _promptText(
      title: tr(context, '添加便签', 'Add note'),
      label: tr(context, '便签内容', 'Note'),
      maxLines: 4,
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      await _controller?.addStickyNote(
        pageIndex,
        point.x,
        point.y,
        color: const DisplayColor(red: 1, green: 0.78, blue: 0.1, alpha: 1),
        contents: text.trim(),
        author: 'Waymark user',
      );
      _copySaved = false;
      if (mounted) {
        setState(() {
          _noteMode = false;
          _status = tr(
            context,
            '已在第 ${pageIndex + 1} 页添加便签',
            'Note added to page ${pageIndex + 1}',
          );
        });
      }
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  void _toggleSigning() {
    setState(() {
      _signMode = !_signMode;
      if (_signMode) {
        _noteMode = false;
        _status = tr(
          context,
          '在同一页手写，完成后点工具栏中的勾',
          'Draw on one page, then tap the tick',
        );
      } else {
        _cancelSigning();
        _status = tr(context, '已取消本次手写', 'Drawing cancelled');
      }
    });
  }

  void _cancelSigning() {
    _signMode = false;
    _strokes.clear();
    _strokePage = null;
  }

  void _collectStroke(int pageIndex, List<DisplayPoint> stroke) {
    setState(() {
      if (_strokePage != pageIndex) {
        _strokes.clear();
        _strokePage = pageIndex;
      }
      _strokes.add(stroke);
      _status = tr(
        context,
        '已记录 ${_strokes.length} 笔，点勾写入 PDF',
        '${_strokes.length} strokes ready · tap the tick to apply',
      );
    });
  }

  Future<void> _finishSigning() async {
    final page = _strokePage;
    if (page == null || _strokes.isEmpty) return;
    try {
      await _controller?.addInk(
        page,
        List<List<DisplayPoint>>.from(_strokes),
        color: const DisplayColor(red: 0.05, green: 0.12, blue: 0.4, alpha: 1),
        width: 2,
        contents: 'handwritten mark',
        author: 'Waymark user',
      );
      _copySaved = false;
      if (mounted) {
        setState(() {
          _cancelSigning();
          _status = tr(
            context,
            '手写内容已加入第 ${page + 1} 页',
            'Drawing added to page ${page + 1}',
          );
        });
      }
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _showForms() async {
    if (!_can('pdf_fill_forms')) {
      setState(
        () => _status = tr(
          context,
          '这份 PDF 没有可填写的表单字段',
          'This PDF has no fillable form fields',
        ),
      );
      return;
    }
    try {
      final fields =
          await _controller?.formFields(_page) ?? const <PdfFormField>[];
      if (!mounted) return;
      final change = await showDialog<(int, String)>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            tr(context, '第 ${_page + 1} 页表单', 'Forms on page ${_page + 1}'),
          ),
          content: SizedBox(
            width: 460,
            child: fields.isEmpty
                ? Text(
                    tr(
                      context,
                      '当前页没有表单字段。',
                      'There are no form fields on this page.',
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final field in fields)
                        ListTile(
                          title: Text(
                            field.name.isEmpty
                                ? tr(context, '未命名字段', 'Unnamed field')
                                : field.name,
                          ),
                          subtitle: Text(
                            '${field.kind}${field.value.isEmpty ? '' : ' · ${field.value}'}'
                            '${field.required ? ' · ${tr(context, '必填', 'Required')}' : ''}'
                            '${field.fillable ? '' : ' · ${tr(context, '当前不可填写', 'Read only')}'}',
                          ),
                          trailing: field.fillable
                              ? IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () async {
                                    final value = await _promptFieldValue(
                                      field,
                                    );
                                    if (value != null && context.mounted) {
                                      Navigator.of(context)
                                          .pop((field.id, value));
                                    }
                                  },
                                )
                              : null,
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr(context, '关闭', 'Close')),
            ),
          ],
        ),
      );
      if (change == null) return;
      await _controller?.setFormField(_page, change.$1, change.$2);
      _copySaved = false;
      if (mounted) {
        setState(() => _status = tr(context, '表单字段已更新', 'Form field updated'));
      }
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<String?> _promptFieldValue(PdfFormField field) async {
    if (field.options.isNotEmpty) {
      return showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(
            field.name.isEmpty
                ? tr(context, '选择内容', 'Choose a value')
                : field.name,
          ),
          children: [
            for (final option in field.options)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(option),
                child: Text(option),
              ),
          ],
        ),
      );
    }
    return _promptText(
      title: field.name.isEmpty ? tr(context, '填写表单', 'Fill form') : field.name,
      label: tr(context, '内容', 'Value'),
      initial: field.value,
    );
  }

  Future<void> _showAnnotations() async {
    try {
      final annotations =
          await _controller?.annotations(_page) ?? const <PdfAnnotation>[];
      if (!mounted) return;
      final removed = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            tr(
              context,
              '第 ${_page + 1} 页批注',
              'Annotations on page ${_page + 1}',
            ),
          ),
          content: SizedBox(
            width: 440,
            child: annotations.isEmpty
                ? Text(
                    tr(
                      context,
                      '当前页没有批注。',
                      'There are no annotations on this page.',
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final annotation in annotations)
                        ListTile(
                          title: Text(
                            _annotationLabel(context, annotation.subtype),
                          ),
                          subtitle: Text(
                            annotation.contents.isEmpty
                                ? (annotation.author ??
                                      tr(context, '无文字内容', 'No text'))
                                : annotation.contents,
                          ),
                          trailing: _controller?.preflight.canEdit == true
                              ? IconButton(
                                  tooltip: tr(context, '删除', 'Delete'),
                                  onPressed: () =>
                                      Navigator.of(context).pop(annotation.id),
                                  icon: const Icon(Icons.delete_outline),
                                )
                              : null,
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr(context, '关闭', 'Close')),
            ),
          ],
        ),
      );
      if (removed == null) return;
      await _controller?.deleteAnnotation(_page, removed);
      _copySaved = false;
      if (mounted) {
        setState(() => _status = tr(context, '已删除一条批注', 'Annotation deleted'));
      }
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _extractCurrentPage() async {
    if (!_can('pdf_extract_pages')) {
      setState(
        () => _status = tr(
          context,
          '这份 PDF 不支持页面提取',
          'Pages cannot be exported from this PDF',
        ),
      );
      return;
    }
    try {
      final bytes = await _controller?.exportPages([_page]);
      if (bytes == null) return;
      await _deliverCopy(bytes, '${_baseName()}-page-${_page + 1}.pdf');
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _mergePdf() async {
    if (!_can('pdf_merge')) {
      setState(
        () => _status = tr(
          context,
          '这份 PDF 不支持合并',
          'Another PDF cannot be merged into this file',
        ),
      );
      return;
    }
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final count = await _controller?.mergeDocument(bytes);
      _copySaved = false;
      if (mounted) {
        setState(
          () => _status = tr(
            context,
            '合并完成，现在共 $count 页',
            'Merged successfully · $count pages total',
          ),
        );
      }
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _flatten() async {
    if (!_can('pdf_flatten')) {
      setState(
        () => _status = tr(
          context,
          '这份 PDF 不支持固定批注与表单内容',
          'Annotations and forms cannot be flattened in this PDF',
        ),
      );
      return;
    }
    if (!await _confirm(
      tr(context, '固定批注与表单内容？', 'Flatten annotations and forms?'),
      tr(
        context,
        '内容会留在页面上，但之后不能再单独修改。你仍可撤销，原件也不会改变。',
        'The content will stay visible but can no longer be edited separately. You can still undo, and the original is unchanged.',
      ),
    )) {
      return;
    }
    try {
      await _controller?.flatten();
      _copySaved = false;
      if (mounted) {
        setState(
          () => _status = tr(
            context,
            '内容已固定；另存副本后才会保留',
            'Content flattened · save a copy to keep it',
          ),
        );
      }
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _saveCopy() async {
    try {
      final bytes = await _controller?.exportCopy();
      if (bytes == null) return;
      await _deliverCopy(bytes, '${_baseName()}-edited.pdf');
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _exportToDevice() async {
    try {
      final bytes = await _controller?.exportCopy();
      if (bytes == null) return;
      await _saveWithPlatformDialog(bytes, '${_baseName()}-edited.pdf');
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _deliverCopy(Uint8List bytes, String name) async {
    final save = widget.onSaveCopy;
    if (save == null) {
      await _saveWithPlatformDialog(bytes, name);
      return;
    }
    await save(bytes, name);
    if (mounted) {
      setState(() {
        _copySaved = true;
        _status = tr(context, '已作为新文件保存：$name', 'Saved as a new file: $name');
      });
    }
  }

  Future<void> _saveWithPlatformDialog(Uint8List bytes, String name) async {
    final uri = await FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      mimeType: 'application/pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (mounted) {
      setState(() {
        if (uri != null) _copySaved = true;
        _status = uri == null
            ? tr(context, '已取消导出', 'Export cancelled')
            : tr(
                context,
                '副本已导出到所选位置',
                'Copy exported to the selected location',
              );
      });
    }
  }

  Future<void> _showCompatibility() async {
    final report = _controller?.preflight;
    if (report == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, '这份 PDF 的兼容性', 'PDF compatibility')),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                tr(
                  context,
                  '兼容等级：${_compatibilityLabel(report.compatibility, context)}',
                  'Compatibility: ${_compatibilityLabel(report.compatibility, context)}',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr(
                  context,
                  '预览器会明确显示字体、图片或不支持内容造成的显示缺口。完整表示没有内容缺失；精确还要求使用文档指定字体。',
                  'The viewer reports display gaps caused by fonts, images, or unsupported content. Complete means nothing is missing; exact also requires the document-specified font.',
                ),
              ),
              if (report.issues.isNotEmpty) ...[
                const Divider(height: 24),
                for (final issue in report.issues)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      issue.severity == IssueSeverity.error
                          ? Icons.error_outline
                          : issue.severity == IssueSeverity.warning
                          ? Icons.warning_amber
                          : Icons.info_outline,
                    ),
                    title: Text(issue.code),
                    subtitle: Text(issue.message),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(context, '知道了', 'Done')),
          ),
        ],
      ),
    );
  }

  void _runMenuAction(_PdfMenuAction action) {
    switch (action) {
      case _PdfMenuAction.forms:
        unawaited(_showForms());
      case _PdfMenuAction.annotations:
        unawaited(_showAnnotations());
      case _PdfMenuAction.moveUp:
        unawaited(_movePage(-1));
      case _PdfMenuAction.moveDown:
        unawaited(_movePage(1));
      case _PdfMenuAction.extract:
        unawaited(_extractCurrentPage());
      case _PdfMenuAction.merge:
        unawaited(_mergePdf());
      case _PdfMenuAction.flatten:
        unawaited(_flatten());
      case _PdfMenuAction.exportDevice:
        unawaited(_exportToDevice());
      case _PdfMenuAction.compatibility:
        unawaited(_showCompatibility());
    }
  }

  Future<String?> _promptPassword(bool wrong) => _promptText(
    title: wrong
        ? tr(context, '密码不正确', 'Incorrect password')
        : tr(context, '这份 PDF 已加密', 'This PDF is encrypted'),
    label: tr(context, 'PDF 密码', 'PDF password'),
    obscure: true,
  );

  Future<String?> _promptText({
    required String title,
    required String label,
    String initial = '',
    int maxLines = 1,
    bool obscure = false,
  }) async {
    var fieldValue = initial;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initial,
          autofocus: true,
          obscureText: obscure,
          maxLines: obscure ? 1 : maxLines,
          onChanged: (value) => fieldValue = value,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(context, '取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(fieldValue),
            child: Text(tr(context, '确定', 'OK')),
          ),
        ],
      ),
    );
    return value;
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr(context, '取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr(context, '继续', 'Continue')),
            ),
          ],
        ),
      ) ??
      false;

  Future<bool> _confirmDiscard() {
    if (_controller?.isDirty != true || _copySaved) return Future.value(true);
    return _confirm(
      tr(context, '放弃尚未保存的修改？', 'Discard unsaved changes?'),
      tr(
        context,
        '原始文件不会受影响，但这次编辑会丢失。',
        'The original file is safe, but this editing session will be lost.',
      ),
    );
  }

  void _setErrorStatus(Object error) {
    if (mounted) setState(() => _status = _describe(error));
  }

  String _baseName() => widget.displayName.toLowerCase().endsWith('.pdf')
      ? widget.displayName.substring(0, widget.displayName.length - 4)
      : widget.displayName;

  String _describe(Object error) => error is DocumentSdkException
      ? '${error.code}：${error.message}'
      : error.toString();
}

DisplayRect? _textBounds(List<TextQuad> quads) {
  if (quads.isEmpty) return null;
  var left = double.infinity;
  var bottom = double.infinity;
  var right = double.negativeInfinity;
  var top = double.negativeInfinity;
  for (final point in quads.expand((quad) => quad.corners)) {
    if (point.x < left) left = point.x;
    if (point.y < bottom) bottom = point.y;
    if (point.x > right) right = point.x;
    if (point.y > top) top = point.y;
  }
  if (![left, bottom, right, top].every((value) => value.isFinite)) return null;
  return DisplayRect(
    x: left,
    y: bottom,
    width: right - left,
    height: top - bottom,
  );
}

enum _PdfMenuAction {
  forms,
  annotations,
  moveUp,
  moveDown,
  extract,
  merge,
  flatten,
  exportDevice,
  compatibility,
}

class _CompatibilityStrip extends StatelessWidget {
  const _CompatibilityStrip({required this.report, required this.onTap});

  final PreflightReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final warning = report.issues.any(
      (issue) => issue.severity != IssueSeverity.info,
    );
    return Material(
      color: warning
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.primaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              Icon(
                warning ? Icons.warning_amber : Icons.verified_outlined,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_compatibilityLabel(report.compatibility, context)} · '
                  '${report.issues.isEmpty ? tr(context, '没有文件级警告', 'No file warnings') : tr(context, '${report.issues.length} 项兼容性提示', '${report.issues.length} compatibility notices')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionStrip extends StatelessWidget {
  const _SelectionStrip({
    required this.selection,
    required this.onCopy,
    required this.onReplace,
    required this.onDelete,
    required this.onMarkup,
    required this.onClear,
  });

  final TextSelectionResult selection;
  final Future<void> Function() onCopy;
  final Future<void> Function()? onReplace;
  final Future<void> Function()? onDelete;
  final Future<void> Function(String) onMarkup;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              selection.text.isEmpty
                  ? tr(context, '已选择区域', 'Area selected')
                  : selection.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: selection.text.isEmpty ? null : onCopy,
            icon: const Icon(Icons.copy, size: 17),
            label: Text(tr(context, '复制', 'Copy')),
          ),
          FilledButton.tonalIcon(
            onPressed: selection.text.isEmpty ? null : onReplace,
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: Text(tr(context, '替换文字', 'Replace text')),
          ),
          TextButton.icon(
            onPressed: selection.text.isEmpty ? null : onDelete,
            icon: const Icon(Icons.backspace_outlined, size: 17),
            label: Text(tr(context, '删除文字', 'Delete text')),
          ),
          TextButton(
            onPressed: () => onMarkup('highlight'),
            child: Text(tr(context, '高亮', 'Highlight')),
          ),
          TextButton(
            onPressed: () => onMarkup('underline'),
            child: Text(tr(context, '下划线', 'Underline')),
          ),
          TextButton(
            onPressed: () => onMarkup('strike_out'),
            child: Text(tr(context, '删除线', 'Strike through')),
          ),
          IconButton(
            tooltip: tr(context, '清除选择', 'Clear selection'),
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    ),
  );
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.dirty,
    required this.saved,
    required this.status,
  });

  final bool dirty;
  final bool saved;
  final String? status;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(dirty ? Icons.edit : Icons.check_circle_outline, size: 16),
            const SizedBox(width: 6),
            Text(
              dirty
                  ? tr(context, '有未保存修改', 'Unsaved changes')
                  : saved
                  ? tr(context, '副本已保存', 'Copy saved')
                  : tr(context, '尚未修改', 'No changes'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                status ??
                    tr(
                      context,
                      '原件不会被覆盖',
                      'The original will not be overwritten',
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _compatibilityLabel(CompatibilityLevel level, [BuildContext? context]) {
  final zh = context == null || isChineseUi(context);
  return switch (level) {
    CompatibilityLevel.fullEdit => zh ? '完整编辑' : 'Full editing',
    CompatibilityLevel.partialEdit => zh ? '部分编辑' : 'Partial editing',
    CompatibilityLevel.readOnly => zh ? '只读' : 'Read only',
    CompatibilityLevel.conversionRequired => zh ? '需要转换' : 'Conversion needed',
    CompatibilityLevel.unsupported => zh ? '不支持' : 'Unsupported',
  };
}

String _annotationLabel(BuildContext context, String subtype) =>
    switch (subtype) {
      'Text' || 'text' => tr(context, '便签', 'Note'),
      'Ink' || 'ink' => tr(context, '手写', 'Drawing'),
      'Highlight' || 'highlight' => tr(context, '高亮', 'Highlight'),
      'Underline' || 'underline' => tr(context, '下划线', 'Underline'),
      'StrikeOut' || 'strike_out' => tr(context, '删除线', 'Strike through'),
      _ => subtype,
    };
