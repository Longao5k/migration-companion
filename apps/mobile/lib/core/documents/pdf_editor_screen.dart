import 'dart:async';
import 'dart:io';

import 'package:document_sdk/document_sdk_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      canPop: _allowPop || controller?.isDirty != true,
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
              const Text(
                '编辑副本 · 原件不动',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '搜索文字',
              onPressed: controller == null ? null : _search,
              icon: const Icon(Icons.search),
            ),
            IconButton(
              tooltip: '撤销',
              onPressed: controller?.canUndo == true ? _undo : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: '重做',
              onPressed: controller?.canRedo == true ? _redo : null,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              tooltip: widget.onSaveCopy == null ? '另存到设备' : '另存到项目',
              onPressed:
                  controller != null && !controller.isBusy && _can('save_copy')
                  ? _saveCopy
                  : null,
              icon: const Icon(Icons.save_outlined),
            ),
            PopupMenuButton<_PdfMenuAction>(
              tooltip: '更多工具',
              onSelected: _runMenuAction,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _PdfMenuAction.forms,
                  child: Text('填写当前页表单'),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.annotations,
                  child: Text('管理当前页批注'),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.moveUp,
                  child: Text('当前页向前移动'),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.moveDown,
                  child: Text('当前页向后移动'),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.extract,
                  child: Text('导出当前页'),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.merge,
                  child: Text('合并另一份 PDF'),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.flatten,
                  child: Text('扁平化批注与表单'),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.exportDevice,
                  child: Text('导出副本到设备'),
                ),
                PopupMenuItem(
                  value: _PdfMenuAction.compatibility,
                  child: Text('兼容性说明'),
                ),
              ],
            ),
          ],
        ),
        body: _buildBody(controller),
        bottomNavigationBar: controller == null
            ? null
            : _StatusBar(dirty: controller.isDirty, status: _status),
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
                child: const Text('返回'),
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
            _buildToolbar(controller),
            if (controller.selection case final selection?)
              _SelectionStrip(
                selection: selection,
                onCopy: _copySelection,
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
              tooltip: '上一页',
              onPressed: _page > 0 ? () => _goToPage(_page - 1) : null,
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            Text(
              '${controller.pageCount == 0 ? 0 : _page + 1}/${controller.pageCount}',
            ),
            IconButton(
              tooltip: '下一页',
              onPressed: _page + 1 < controller.pageCount
                  ? () => _goToPage(_page + 1)
                  : null,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: '缩小',
              onPressed: _zoom > 0.3
                  ? () => setState(() => _zoom = (_zoom / 1.25).clamp(0.25, 6))
                  : null,
              icon: const Icon(Icons.zoom_out),
            ),
            Text('${(_zoom * 100).round()}%'),
            IconButton(
              tooltip: '放大',
              onPressed: _zoom < 6
                  ? () => setState(() => _zoom = (_zoom * 1.25).clamp(0.25, 6))
                  : null,
              icon: const Icon(Icons.zoom_in),
            ),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              tooltip: '旋转当前页',
              onPressed: canEdit && _can('pdf_rotate_pages') ? _rotate : null,
              icon: const Icon(Icons.rotate_right),
            ),
            IconButton(
              tooltip: '删除当前页',
              onPressed:
                  canEdit &&
                      controller.pageCount > 1 &&
                      _can('pdf_delete_pages')
                  ? _deletePage
                  : null,
              icon: const Icon(Icons.delete_outline),
            ),
            IconButton(
              tooltip: _noteMode ? '点按页面放置便签' : '添加便签',
              isSelected: _noteMode,
              onPressed: canEdit && _can('pdf_annotate_text')
                  ? _toggleNote
                  : null,
              icon: const Icon(Icons.add_comment_outlined),
              selectedIcon: const Icon(Icons.add_comment),
            ),
            IconButton(
              tooltip: _signMode ? '正在手写；完成后点勾' : '手写签名或批注',
              isSelected: _signMode,
              onPressed: canEdit && _can('pdf_annotate_ink')
                  ? _toggleSigning
                  : null,
              icon: const Icon(Icons.draw_outlined),
              selectedIcon: const Icon(Icons.draw),
            ),
            if (_signMode)
              IconButton.filled(
                tooltip: _strokes.isEmpty ? '请先在页面上书写' : '写入 PDF',
                onPressed: _strokes.isEmpty ? null : _finishSigning,
                icon: const Icon(Icons.check),
              ),
            if (controller.searchResults?.hits.isNotEmpty == true) ...[
              IconButton(
                tooltip: '上一个搜索结果',
                onPressed: () => _stepSearch(next: false),
                icon: const Icon(Icons.navigate_before),
              ),
              Text(
                '${controller.activeHitIndex + 1}/${controller.searchResults!.hits.length}',
              ),
              IconButton(
                tooltip: '下一个搜索结果',
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
          _error = '读取工作副本失败：$error';
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
              ? '拖选文字可复制或标记；每项能力按当前文件开放。'
              : '已用密码打开；若 SDK 判为只读，将不会允许保存修改。';
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
              _error = '这份 PDF 需要密码才能打开。';
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
  );

  Future<void> _deletePage() async {
    if (!await _confirm('删除当前页？', '只会从编辑副本中删除，原始 PDF 不受影响。')) return;
    await _execute(PdfDeletePagesCommand(pages: [_page]), '已删除一页');
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
      setState(() => _status = delta < 0 ? '已经是第一页' : '已经是最后一页');
      return;
    }
    final order = List<int>.generate(controller.pageCount, (index) => index);
    final moving = order.removeAt(_page);
    order.insert(target, moving);
    await _execute(PdfReorderPagesCommand(order: order), '已移动当前页');
    await _goToPage(target);
  }

  Future<void> _execute(DocumentCommand command, String success) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final receipt = await controller.execute(command);
      if (!mounted) return;
      setState(() {
        _status = receipt.changed ? '$success；另存副本后才会保留。' : '没有内容发生变化。';
      });
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _undo() async {
    try {
      await _controller?.undo();
      if (mounted) setState(() => _status = '已撤销上一步');
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _redo() async {
    try {
      await _controller?.redo();
      if (mounted) setState(() => _status = '已重做');
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _search() async {
    var queryValue = '';
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('搜索这份 PDF'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(labelText: '关键词'),
          onChanged: (value) => queryValue = value,
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(queryValue.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    if (query == null || query.isEmpty) return;
    try {
      final results = await _controller?.search(query);
      final hit = _controller?.activeHit;
      if (hit != null) await _goToPage(hit.pageIndex);
      if (!mounted || results == null) return;
      setState(() {
        _status = results.hits.isEmpty
            ? '没有找到。扫描件或不可映射文字可能无法搜索。'
            : '找到 ${results.hits.length} 处';
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
          ? '已复制 ${selection.text.runes.length} 个字符'
          : '已复制，但当前页有无法可靠映射的文字，内容可能不完整。';
    });
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
      if (!mounted) return;
      setState(() => _status = receipt == null ? '请先拖选文字' : '已添加文字标记');
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  void _toggleNote() {
    setState(() {
      _noteMode = !_noteMode;
      if (_noteMode) {
        _cancelSigning();
        _status = '点按页面上的位置以添加便签';
      }
    });
  }

  Future<void> _addNoteAt(int pageIndex, DisplayPoint point) async {
    final text = await _promptText(title: '添加便签', label: '便签内容', maxLines: 4);
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
      if (mounted) {
        setState(() {
          _noteMode = false;
          _status = '已在第 ${pageIndex + 1} 页添加便签';
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
        _status = '在同一页手写，完成后点工具栏中的勾';
      } else {
        _cancelSigning();
        _status = '已取消本次手写';
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
      _status = '已记录 ${_strokes.length} 笔，点勾写入 PDF';
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
      if (mounted) {
        setState(() {
          _cancelSigning();
          _status = '手写内容已加入第 ${page + 1} 页';
        });
      }
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _showForms() async {
    if (!_can('pdf_fill_forms')) {
      setState(() => _status = '这份 PDF 没有开放可填写表单能力');
      return;
    }
    try {
      final fields =
          await _controller?.formFields(_page) ?? const <PdfFormField>[];
      if (!mounted) return;
      final change = await showDialog<(int, String)>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('第 ${_page + 1} 页表单'),
          content: SizedBox(
            width: 460,
            child: fields.isEmpty
                ? const Text('当前页没有表单字段。')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final field in fields)
                        ListTile(
                          title: Text(
                            field.name.isEmpty ? '未命名字段' : field.name,
                          ),
                          subtitle: Text(
                            '${field.kind}${field.value.isEmpty ? '' : ' · ${field.value}'}'
                            '${field.required ? ' · 必填' : ''}'
                            '${field.fillable ? '' : ' · 当前不可填写'}',
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
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      if (change == null) return;
      await _controller?.setFormField(_page, change.$1, change.$2);
      if (mounted) setState(() => _status = '表单字段已更新');
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<String?> _promptFieldValue(PdfFormField field) async {
    if (field.options.isNotEmpty) {
      return showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(field.name.isEmpty ? '选择内容' : field.name),
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
      title: field.name.isEmpty ? '填写表单' : field.name,
      label: '内容',
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
          title: Text('第 ${_page + 1} 页批注'),
          content: SizedBox(
            width: 440,
            child: annotations.isEmpty
                ? const Text('当前页没有批注。')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final annotation in annotations)
                        ListTile(
                          title: Text(_annotationLabel(annotation.subtype)),
                          subtitle: Text(
                            annotation.contents.isEmpty
                                ? (annotation.author ?? '无文字内容')
                                : annotation.contents,
                          ),
                          trailing: _controller?.preflight.canEdit == true
                              ? IconButton(
                                  tooltip: '删除',
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
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      if (removed == null) return;
      await _controller?.deleteAnnotation(_page, removed);
      if (mounted) setState(() => _status = '已删除一条批注');
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _extractCurrentPage() async {
    if (!_can('pdf_extract_pages')) {
      setState(() => _status = '这份 PDF 不支持页面提取');
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
      setState(() => _status = '这份 PDF 不支持合并');
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
      if (mounted) setState(() => _status = '合并完成，现在共 $count 页');
    } on Object catch (error) {
      _setErrorStatus(error);
    }
  }

  Future<void> _flatten() async {
    if (!_can('pdf_flatten')) {
      setState(() => _status = '这份 PDF 不支持扁平化');
      return;
    }
    if (!await _confirm('扁平化批注与表单？', '内容会留在页面上，但之后不能再单独修改。你仍可撤销，原件也不会改变。')) {
      return;
    }
    try {
      await _controller?.flatten();
      if (mounted) setState(() => _status = '已扁平化；另存副本后才会保留');
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
    if (mounted) setState(() => _status = '已作为新附件保存：$name');
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
      setState(() => _status = uri == null ? '已取消导出' : '副本已导出到所选位置');
    }
  }

  Future<void> _showCompatibility() async {
    final report = _controller?.preflight;
    if (report == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('这份 PDF 的兼容性'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text('兼容等级：${_compatibilityLabel(report.compatibility)}'),
              const SizedBox(height: 10),
              const Text(
                '预览器会明确显示未内嵌字体、图片或不支持内容造成的缺口。'
                '若以后将页面栅格化：complete 表示内容没有缺失；exact 还要求字形来自文档指定字体。'
                '使用替代字体可能 complete，但不会 exact。',
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
            child: const Text('知道了'),
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
    title: wrong ? '密码不正确' : '这份 PDF 已加密',
    label: 'PDF 密码',
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
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(fieldValue),
            child: const Text('确定'),
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
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续'),
            ),
          ],
        ),
      ) ??
      false;

  Future<bool> _confirmDiscard() {
    if (_controller?.isDirty != true) return Future.value(true);
    return _confirm('放弃尚未保存的修改？', '原始文件不会受影响，但这次编辑会丢失。');
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
                  '${_compatibilityLabel(report.compatibility)} · '
                  '${report.issues.isEmpty ? '没有文件级警告' : '${report.issues.length} 项兼容性提示'}',
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
    required this.onMarkup,
    required this.onClear,
  });

  final TextSelectionResult selection;
  final Future<void> Function() onCopy;
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
              selection.text.isEmpty ? '已选择区域' : selection.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: selection.text.isEmpty ? null : onCopy,
            icon: const Icon(Icons.copy, size: 17),
            label: const Text('复制'),
          ),
          TextButton(
            onPressed: () => onMarkup('highlight'),
            child: const Text('高亮'),
          ),
          TextButton(
            onPressed: () => onMarkup('underline'),
            child: const Text('下划线'),
          ),
          TextButton(
            onPressed: () => onMarkup('strike_out'),
            child: const Text('删除线'),
          ),
          IconButton(
            tooltip: '清除选择',
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    ),
  );
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.dirty, required this.status});

  final bool dirty;
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
            Text(dirty ? '有未保存修改' : '尚未修改'),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                status ?? '原件不会被覆盖',
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

String _compatibilityLabel(CompatibilityLevel level) => switch (level) {
  CompatibilityLevel.fullEdit => '完整编辑',
  CompatibilityLevel.partialEdit => '部分编辑',
  CompatibilityLevel.readOnly => '只读',
  CompatibilityLevel.conversionRequired => '需要转换',
  CompatibilityLevel.unsupported => '不支持',
};

String _annotationLabel(String subtype) => switch (subtype) {
  'Text' || 'text' => '便签',
  'Ink' || 'ink' => '手写',
  'Highlight' || 'highlight' => '高亮',
  'Underline' || 'underline' => '下划线',
  'StrikeOut' || 'strike_out' => '删除线',
  _ => subtype,
};
