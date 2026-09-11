import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/documents/document_engine.dart';
import '../../core/documents/document_engines.dart';
import '../../core/documents/docx_editor_screen.dart';
import '../../core/documents/pdf_editor_screen.dart';
import '../../shared/widgets/common.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文档工具')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            '在副本上编辑，原件不动',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '每份 PDF 都先做兼容性检查，只开放它确实支持的工具。保存会生成新文件。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SectionHeader(title: '打开文件'),
          _ToolCard(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF',
            description: '改名字日期、填写表单、添加少量文字',
            badge: '可编辑',
            onTap: () => _pickDocument(context, ['pdf']),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.description_outlined,
            title: 'Word 文档',
            description: '修改普通段落，复杂排版可转到其他应用',
            badge: '简单编辑',
            onTap: () => _pickDocument(context, ['doc', 'docx']),
          ),
          const SectionHeader(title: '这个版本能做什么'),
          const _CapabilityRow(
            icon: Icons.draw_outlined,
            title: '批注与签名',
            body: '修改 PDF 已有文字，或添加名字、日期和少量说明',
          ),
          const _CapabilityRow(
            icon: Icons.view_carousel_outlined,
            title: '页面与表单',
            body: '填写 PDF 表单，给普通 Word 段落改字或补一段内容',
          ),
          const _CapabilityRow(
            icon: Icons.shield_outlined,
            title: '复杂文件仍可继续处理',
            body: '遇到复杂排版时可以直接交给手机上的 Word 或 PDF 应用',
          ),
        ],
      ),
    );
  }

  Future<void> _pickDocument(
    BuildContext context,
    List<String> extensions,
  ) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (file == null) return;
    final pageContext = context;
    final length = await file.length();
    final extension = (file.extension ?? '').toLowerCase();
    final isPdf = extension == 'pdf';
    // 两种引擎的调用形状一样，这里只挑一个，后面的 UI 不再分叉——
    // 之前 DOCX 分支只会弹一句提示，卡片却说「可以查看」，是自相矛盾的。
    final Future<DocumentPreflightResult> Function() preflight;
    final Future<void> Function() open;
    if (isPdf) {
      final engine = createPdfDocumentEngine();
      preflight = () => engine.preflight(
        fileName: file.name,
        localPath: file.path,
        byteSize: length,
      );
      open = () async {
        final workingPath = await engine.createWorkingCopy(
          sourcePath: file.path!,
          displayName: file.name,
        );
        if (!pageContext.mounted) return;
        await Navigator.of(pageContext).push(
          MaterialPageRoute<void>(
            builder: (_) => PdfEditorScreen(
              sourcePath: workingPath,
              displayName: file.name,
            ),
          ),
        );
      };
    } else {
      final engine = createDocxDocumentEngine();
      preflight = () => engine.preflight(
        fileName: file.name,
        localPath: file.path,
        byteSize: length,
      );
      open = () async {
        if (extension == 'docx') {
          final workingPath = await engine.createWorkingCopy(
            sourcePath: file.path!,
            displayName: file.name,
          );
          if (!pageContext.mounted) return;
          await Navigator.of(pageContext).push(
            MaterialPageRoute<void>(
              builder: (_) => DocxEditorScreen(
                sourcePath: workingPath,
                displayName: file.name,
              ),
            ),
          );
        } else {
          await engine.openExternalCopy(
            sourcePath: file.path!,
            displayName: file.name,
          );
        }
      };
    }
    final result = await preflight();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SourceBadge(label: result.title, verified: result.canOpen),
            const SizedBox(height: 16),
            Text(file.name, style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(result.message),
            if (result.canOpen) ...[
              const SizedBox(height: 8),
              Text(
                isPdf
                    ? 'PDF 会在 Waymark 内打开。逐页提示代表实际兼容性缺口；保存只会生成新副本。'
                    : extension == 'docx'
                    ? '普通段落会在 Waymark 内编辑；复杂排版可以再交给其他应用。保存始终生成新副本。'
                    : '旧版 Word 文件会交给手机上的其他应用；该应用可能把文件同步到自己的云端。',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: !result.canOpen || file.path == null
                  ? null
                  : () async {
                      Navigator.pop(sheetContext);
                      try {
                        await open();
                      } catch (error) {
                        if (!pageContext.mounted) return;
                        ScaffoldMessenger.of(
                          pageContext,
                        ).showSnackBar(SnackBar(content: Text('打不开：$error')));
                      }
                    },
              child: Text(
                result.access == DocumentAccess.editable ? '打开编辑' : '打开查看',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String description;
  final String badge;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      SourceBadge(label: badge),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(description),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 4),
    leading: Icon(icon),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(body),
  );
}
