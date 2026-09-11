import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/data/material_catalog.dart';
import '../../core/documents/document_engines.dart';
import '../../core/documents/docx_editor_screen.dart';
import '../../core/documents/pdf_editor_screen.dart';
import '../../core/i18n/app_language.dart';
import '../../core/models/material_library.dart';
import '../../core/state/material_library_store.dart';

class MaterialLibraryScreen extends ConsumerWidget {
  const MaterialLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(materialLibraryProvider);
    final zh = isChineseUi(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(zh ? '我的资料' : 'My documents'),
        actions: [
          IconButton(
            tooltip: zh ? '添加人员' : 'Add person',
            onPressed: () => _addPerson(context, ref),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
      ),
      body: !state.isHydrated
          ? const Center(child: CircularProgressIndicator())
          : state.people.isEmpty
          ? _EmptyLibrary(onAdd: () => _addPerson(context, ref))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              itemCount: state.people.length,
              itemBuilder: (_, index) =>
                  _PersonCard(person: state.people[index]),
            ),
      floatingActionButton: state.people.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addPerson(context, ref),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(zh ? '添加人员' : 'Add person'),
            ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_copy_outlined, size: 64),
          const SizedBox(height: 20),
          Text(
            tr(
              context,
              '先按人整理，再把材料关联到申请',
              'Organise by person, then link documents to applications',
            ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              '为自己、伴侣或家人建立资料夹。一个文件只需保存一次。',
              'Create a library for yourself, a partner or family. Save each file once.',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_alt_1),
            label: Text(tr(context, '添加第一个人', 'Add first person')),
          ),
        ],
      ),
    ),
  );
}

class _PersonCard extends ConsumerWidget {
  const _PersonCard({required this.person});
  final PersonMaterialProfile person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zh = isChineseUi(context);
    final fileCount = person.folders.fold<int>(
      0,
      (sum, folder) => sum + folder.documents.length,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: CircleAvatar(
          child: Text(person.name.characters.first.toUpperCase()),
        ),
        title: Text(
          person.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          zh
              ? '${person.folders.length} 个分类 · $fileCount 个文件'
              : '${person.folders.length} folders · $fileCount files',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          for (final folder in person.folders)
            _FolderTile(person: person, folder: folder),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addFolder(context, ref, person),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(zh ? '添加材料分类' : 'Add document folder'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderTile extends ConsumerWidget {
  const _FolderTile({required this.person, required this.folder});
  final PersonMaterialProfile person;
  final MaterialFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zh = isChineseUi(context);
    final category = materialCategoryById(folder.categoryId);
    final name = folder.customName.isNotEmpty
        ? folder.customName
        : category?.label(zh) ?? (zh ? '其他材料' : 'Other documents');
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ExpansionTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(name),
        subtitle: Text(
          zh
              ? '${folder.documents.length} 个文件'
              : '${folder.documents.length} files',
        ),
        children: [
          for (final document in folder.documents)
            ListTile(
              leading: Icon(_fileIcon(document.name)),
              title: Text(
                document.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(_size(document.byteSize)),
              onTap: () =>
                  _openDocument(context, ref, person, folder, document),
              trailing: PopupMenuButton<String>(
                onSelected: (action) => _documentAction(
                  context,
                  ref,
                  person,
                  folder,
                  document,
                  action,
                ),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'open',
                    child: Text(zh ? '打开 / 编辑' : 'Open / edit'),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: Text(zh ? '分享文件' : 'Share file'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(zh ? '删除' : 'Delete'),
                  ),
                ],
              ),
            ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: Text(zh ? '从设备导入文件' : 'Import from device'),
            onTap: () => _importFile(context, ref, person, folder),
          ),
        ],
      ),
    );
  }
}

Future<void> _addPerson(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr(context, '添加人员', 'Add person')),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: tr(context, '姓名或称呼', 'Name or label'),
        ),
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
  if (name == null || name.trim().isEmpty) return;
  final person = await ref
      .read(materialLibraryProvider.notifier)
      .addPerson(name);
  if (!context.mounted) return;
  await _addFolder(context, ref, person, firstFolder: true);
}

Future<void> _addFolder(
  BuildContext context,
  WidgetRef ref,
  PersonMaterialProfile person, {
  bool firstFolder = false,
}) async {
  final zh = isChineseUi(context);
  String selected = materialCategoryCatalog.first.id;
  final custom = TextEditingController();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          firstFolder
              ? (zh ? '选择第一个材料分类' : 'Choose first folder')
              : (zh ? '添加材料分类' : 'Add document folder'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selected,
              items: [
                for (final category in materialCategoryCatalog)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.label(zh)),
                  ),
                DropdownMenuItem(
                  value: 'custom',
                  child: Text(zh ? '自定义名称' : 'Custom name'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => selected = value ?? selected),
            ),
            if (selected == 'custom') ...[
              const SizedBox(height: 12),
              TextField(
                controller: custom,
                decoration: InputDecoration(
                  labelText: zh ? '文件夹名称' : 'Folder name',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(zh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(zh ? '创建' : 'Create'),
          ),
        ],
      ),
    ),
  );
  if (accepted != true) return;
  try {
    await ref
        .read(materialLibraryProvider.notifier)
        .addFolder(
          personId: person.id,
          categoryId: selected,
          customName: custom.text,
        );
  } on FormatException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

Future<void> _importFile(
  BuildContext context,
  WidgetRef ref,
  PersonMaterialProfile person,
  MaterialFolder folder,
) async {
  final picked = await FilePicker.pickFile();
  if (picked == null) return;
  try {
    await ref
        .read(materialLibraryProvider.notifier)
        .addDocument(
          personId: person.id,
          folderId: folder.id,
          name: picked.name,
          bytes: await picked.readAsBytes(),
        );
  } on FormatException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

Future<void> _documentAction(
  BuildContext context,
  WidgetRef ref,
  PersonMaterialProfile person,
  MaterialFolder folder,
  LibraryDocument document,
  String action,
) async {
  if (action == 'open') {
    return _openDocument(context, ref, person, folder, document);
  }
  if (action == 'share') {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            document.localPath,
            name: document.name,
            mimeType: document.contentType,
          ),
        ],
      ),
    );
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr(context, '删除这个文件？', 'Delete this file?')),
      content: Text(document.name),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr(context, '取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(tr(context, '删除', 'Delete')),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref
        .read(materialLibraryProvider.notifier)
        .removeDocument(
          personId: person.id,
          folderId: folder.id,
          documentId: document.id,
        );
  }
}

Future<void> _openDocument(
  BuildContext context,
  WidgetRef ref,
  PersonMaterialProfile person,
  MaterialFolder folder,
  LibraryDocument document,
) async {
  final lower = document.name.toLowerCase();
  if (lower.endsWith('.pdf')) {
    final engine = createPdfDocumentEngine();
    final preflight = await engine.preflight(
      fileName: document.name,
      localPath: document.localPath,
      byteSize: document.byteSize,
    );
    if (!context.mounted) return;
    if (!preflight.canOpen) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(preflight.message)));
      return;
    }
    final copy = await engine.createWorkingCopy(
      sourcePath: document.localPath,
      displayName: document.name,
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfEditorScreen(
          sourcePath: copy,
          displayName: document.name,
          onSaveCopy: (bytes, suggestedName) => ref
              .read(materialLibraryProvider.notifier)
              .addDocument(
                personId: person.id,
                folderId: folder.id,
                name: suggestedName,
                bytes: bytes,
              ),
        ),
      ),
    );
    return;
  }
  if (lower.endsWith('.docx')) {
    final copy = await createDocxDocumentEngine().createWorkingCopy(
      sourcePath: document.localPath,
      displayName: document.name,
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocxEditorScreen(
          sourcePath: copy,
          displayName: document.name,
          onSaveCopy: (bytes, suggestedName) => ref
              .read(materialLibraryProvider.notifier)
              .addDocument(
                personId: person.id,
                folderId: folder.id,
                name: suggestedName,
                bytes: bytes,
              ),
        ),
      ),
    );
    return;
  }
  if (lower.endsWith('.doc')) {
    await createDocxDocumentEngine().openExternalCopy(
      sourcePath: document.localPath,
      displayName: document.name,
    );
    return;
  }
  await OpenFilex.open(document.localPath);
}

IconData _fileIcon(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
  if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
    return Icons.description_outlined;
  }
  if (lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png')) {
    return Icons.image_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
