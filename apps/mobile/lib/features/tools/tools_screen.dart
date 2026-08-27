import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/documents/document_engine.dart';
import '../../core/documents/document_engines.dart';
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
            '先判断兼容性，再动原件',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '每次编辑默认保存副本。复杂或受保护文件会明确转为只读，不会静默破坏。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SectionHeader(title: '打开文件'),
          _ToolCard(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF 查看与编辑',
            description: '表单填写、批注、签名、页面整理、扫描与安全导出',
            badge: '支持',
            onTap: () => _pickDocument(context, ['pdf']),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.description_outlined,
            title: 'Word 查看与编辑',
            description: '简单 DOCX 可编辑；DOC、宏和复杂版式只读或先转换副本',
            badge: '兼容检查',
            onTap: () => _pickDocument(context, ['doc', 'docx']),
          ),
          const SectionHeader(title: '能力边界'),
          const _CapabilityRow(
            icon: Icons.visibility_outlined,
            title: '永久免费',
            body: '查看、搜索、基础批注、表单填写、原件导出',
          ),
          const _CapabilityRow(
            icon: Icons.workspace_premium_outlined,
            title: '7 天高级试用',
            body: '高级 PDF 页面编辑与受支持 DOCX 编辑；主动开始且不自动收费',
          ),
          const _CapabilityRow(
            icon: Icons.draw_outlined,
            title: '普通手写签名',
            body: '方便填写材料，但不等同于身份认证或政府认可的数字签名',
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
    final length = await file.length();
    final isPdf = (file.extension ?? '').toLowerCase() == 'pdf';
    final PdfDocumentEngine? pdfEngine;
    final DocumentPreflightResult result;
    final String implementationName;
    if (isPdf) {
      pdfEngine = createPdfDocumentEngine();
      implementationName = pdfEngine.implementationName;
      result = await pdfEngine.preflight(
        fileName: file.name,
        localPath: file.path,
        byteSize: length,
      );
    } else {
      pdfEngine = null;
      final docxEngine = createDocxDocumentEngine();
      implementationName = docxEngine.implementationName;
      result = await docxEngine.preflight(
        fileName: file.name,
        localPath: file.path,
        byteSize: length,
      );
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SourceBadge(
              label: result.title,
              verified: result.access == DocumentAccess.editable,
            ),
            const SizedBox(height: 16),
            Text(file.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(result.message),
            const SizedBox(height: 8),
            Text(
              '当前实现：$implementationName',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: !result.canOpen
                  ? null
                  : () async {
                      Navigator.pop(context);
                      if (!isPdf || file.path == null) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('DOCX 试用会话适配器正在接入服务器端保存副本流程'),
                          ),
                        );
                        return;
                      }
                      try {
                        await pdfEngine!.openWorkingCopy(
                          sourcePath: file.path!,
                          displayName: file.name,
                        );
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('无法打开编辑副本：$error')),
                        );
                      }
                    },
              child: Text(
                result.access == DocumentAccess.editable ? '创建副本并打开' : '只读打开',
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
