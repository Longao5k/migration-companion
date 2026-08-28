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
          // 界面不得出现当前构建做不到的能力词。编辑能力随评估版文档 SDK 一并移出
          // 发布构建（ADR-011），订阅入口也已关闭——继续挂着「编辑」「试用」
          // 既是对用户的虚假陈述，也过不了商店审核。
          Text(
            '打开前先看清楚，原件不动',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '打开的始终是副本，原件留在原处。文件对不上类型时我们不会打开它。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SectionHeader(title: '打开文件'),
          _ToolCard(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF',
            description: '用手机自带的阅读器打开',
            badge: '可查看',
            onTap: () => _pickDocument(context, ['pdf']),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.description_outlined,
            title: 'Word 文档',
            description: '用手机上能打开 Word 的应用查看',
            badge: '可查看',
            onTap: () => _pickDocument(context, ['doc', 'docx']),
          ),
          const SectionHeader(title: '这个版本能做什么'),
          const _CapabilityRow(
            icon: Icons.visibility_outlined,
            title: '查看和整理',
            body: '把材料放进清单、查看、导出原件',
          ),
          const _CapabilityRow(
            icon: Icons.open_in_new,
            title: '交给其他应用打开',
            body: '文件副本会交给你手机上的阅读器，请留意那个应用是否会同步到云端',
          ),
          const _CapabilityRow(
            icon: Icons.construction_outlined,
            title: '编辑还在做',
            body: '批注、签名、表单填写和页面整理都还没上线',
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
    // 两种引擎的调用形状一样，这里只挑一个，后面的 UI 不再分叉——
    // 之前 DOCX 分支只会弹一句提示，卡片却说「可以查看」，是自相矛盾的。
    final Future<DocumentPreflightResult> Function() preflight;
    final Future<String> Function() open;
    if (isPdf) {
      final engine = createPdfDocumentEngine();
      preflight = () => engine.preflight(
        fileName: file.name,
        localPath: file.path,
        byteSize: length,
      );
      open = () => engine.openWorkingCopy(
        sourcePath: file.path!,
        displayName: file.name,
      );
    } else {
      final engine = createDocxDocumentEngine();
      preflight = () => engine.preflight(
        fileName: file.name,
        localPath: file.path,
        byteSize: length,
      );
      open = () => engine.openWorkingCopy(
        sourcePath: file.path!,
        displayName: file.name,
      );
    }
    final result = await preflight();
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
            SourceBadge(label: result.title, verified: result.canOpen),
            const SizedBox(height: 16),
            Text(file.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(result.message),
            if (result.canOpen) ...[
              const SizedBox(height: 8),
              // 交给外部应用是一次真实的数据流出，用户有权在点开之前知道。
              Text(
                '文件副本会交给你手机上的其他应用打开。那个应用可能会把它同步到自己的云端。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: !result.canOpen || file.path == null
                  ? null
                  : () async {
                      Navigator.pop(context);
                      try {
                        await open();
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('打不开：$error')));
                      }
                    },
              child: const Text('打开查看'),
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
