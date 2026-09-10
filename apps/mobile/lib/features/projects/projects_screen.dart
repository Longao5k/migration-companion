import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/data/visa_route_catalog.dart';
import '../../core/i18n/app_language.dart';
import '../../core/models/material_library.dart';
import '../../core/models/models.dart';
import '../../core/state/app_store.dart';
import '../../core/state/material_library_store.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStoreProvider);
    final zh = isChineseUi(context);
    return Scaffold(
      appBar: AppBar(title: Text(zh ? '我的申请' : 'My applications')),
      body: state.projects.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.route_outlined, size: 64),
                    const SizedBox(height: 18),
                    Text(
                      zh
                          ? '把每个申请变成一张简单清单'
                          : 'Turn each application into a simple checklist',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      zh ? '这里只记录材料是否完成，不判断你的签证资格。' : 'This tracks document completion only. It does not assess visa eligibility.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: () => _newProject(context, ref),
                      icon: const Icon(Icons.add),
                      label: Text(zh ? '创建申请' : 'Create application'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                Text(
                  zh ? '只保留完成与未完成。文件可以直接从“我的资料”关联。' : 'Only complete and incomplete are shown. Link files directly from My documents.',
                ),
                const SizedBox(height: 14),
                for (final project in state.projects)
                  _ProjectCard(project: project),
              ],
            ),
      floatingActionButton: state.projects.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _newProject(context, ref),
              icon: const Icon(Icons.add),
              label: Text(zh ? '创建申请' : 'New application'),
            ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});
  final VisaProject project;
  @override
  Widget build(BuildContext context) {
    final zh = isChineseUi(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProjectDetailScreen(projectId: project.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      project.name,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 4),
              Text('${project.visaType} · ${project.applicant}'),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: project.completion,
                minHeight: 7,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 8),
              Text(
                zh
                    ? '${project.doneCount}/${project.items.length} 项已完成'
                    : '${project.doneCount}/${project.items.length} complete',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({required this.projectId, super.key});
  final String projectId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStoreProvider);
    final project = state.projects.firstWhere((item) => item.id == projectId);
    final zh = isChineseUi(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        actions: [
          IconButton(
            tooltip: zh ? '分享全部附件压缩包' : 'Share all attachments as ZIP',
            onPressed: () => _shareApplicationPackage(context, project),
            icon: const Icon(Icons.folder_zip_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          Text(
            '${project.visaType} · ${project.applicant}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: project.completion,
            minHeight: 9,
            borderRadius: BorderRadius.circular(10),
          ),
          const SizedBox(height: 8),
          Text(
            zh
                ? '${project.doneCount}/${project.items.length} 项已完成'
                : '${project.doneCount}/${project.items.length} complete',
          ),
          const SizedBox(height: 20),
          for (final item in project.items)
            _ChecklistCard(project: project, item: item),
          OutlinedButton.icon(
            onPressed: () => _addChecklistItem(context, ref, project),
            icon: const Icon(Icons.add),
            label: Text(zh ? '添加自定义材料' : 'Add custom document item'),
          ),
        ],
      ),
    );
  }
}

class _ChecklistCard extends ConsumerWidget {
  const _ChecklistCard({required this.project, required this.item});
  final VisaProject project;
  final ChecklistItem item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = item.status.index >= ChecklistStatus.ready.index;
    final zh = isChineseUi(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          children: [
            CheckboxListTile(
              value: done,
              onChanged: (value) => ref
                  .read(appStoreProvider.notifier)
                  .setChecklistCompleted(project.id, item.id, value ?? false),
              title: Text(
                item.title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
              subtitle: Text(
                done ? (zh ? '已完成' : 'Complete') : (zh ? '未完成' : 'Incomplete'),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _pickPlanDate(context, ref, project, item),
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(
                        item.dueDate == null
                            ? (zh ? '设置计划日期' : 'Set plan date')
                            : DateFormat.yMMMd().format(item.dueDate!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          _attachDocument(context, ref, project, item),
                      icon: const Icon(Icons.attach_file, size: 18),
                      label: Text(zh ? '关联材料' : 'Link file'),
                    ),
                  ),
                ],
              ),
            ),
            for (final attachment in item.attachments)
              ListTile(
                dense: true,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  attachment.libraryDocumentId == null
                      ? (zh ? '来自设备' : 'From device')
                      : (zh ? '来自我的资料' : 'From My documents'),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'share' && attachment.localPath != null) {
                      await SharePlus.instance.share(
                        ShareParams(
                          files: [
                            XFile(
                              attachment.localPath!,
                              name: attachment.name,
                              mimeType: attachment.contentType,
                            ),
                          ],
                        ),
                      );
                    } else if (action == 'remove') {
                      await ref
                          .read(appStoreProvider.notifier)
                          .removeAttachment(
                            projectId: project.id,
                            itemId: item.id,
                            attachmentId: attachment.id,
                          );
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'share',
                      child: Text(zh ? '分享文件' : 'Share file'),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(zh ? '从申请移除' : 'Remove from application'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _newProject(BuildContext context, WidgetRef ref) async {
  final zh = isChineseUi(context);
  final people = ref.read(materialLibraryProvider).people;
  final nameController = TextEditingController();
  final customRouteController = TextEditingController();
  String route = '190';
  String jurisdiction = 'AU-SA';
  String applicant = people.isEmpty
      ? (zh ? '主申请人' : 'Primary applicant')
      : people.first.name;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(zh ? '创建申请' : 'Create application'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: zh ? '申请名称' : 'Application name',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: route,
                decoration: InputDecoration(
                  labelText: zh ? '申请路线' : 'Visa route',
                ),
                isExpanded: true,
                items: visaRouteCatalog
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.code,
                        child: Text(
                          item.label(zh),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => route = value ?? route),
              ),
              if (route == '190' || route == '491') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: jurisdiction,
                  decoration: InputDecoration(
                    labelText: zh ? '州或领地' : 'State or territory',
                  ),
                  items: stateJurisdictions
                      .map(
                        (code) => DropdownMenuItem(
                          value: code,
                          child: Text(jurisdictionLabel(code, zh: zh)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => jurisdiction = value ?? jurisdiction),
                ),
              ],
              if (route == 'Custom') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: customRouteController,
                  decoration: InputDecoration(
                    labelText: zh ? '自定义路线名称' : 'Custom route name',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (people.isEmpty)
                TextField(
                  decoration: InputDecoration(
                    labelText: zh ? '主申请人' : 'Primary applicant',
                    hintText: applicant,
                  ),
                  onChanged: (value) => applicant = value.trim().isEmpty
                      ? applicant
                      : value.trim(),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: applicant,
                  decoration: InputDecoration(
                    labelText: zh ? '主申请人' : 'Primary applicant',
                  ),
                  items: people
                      .map(
                        (person) => DropdownMenuItem(
                          value: person.name,
                          child: Text(person.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => applicant = value ?? applicant,
                ),
            ],
          ),
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
  final routeLabel = route == 'Custom'
      ? customRouteController.text.trim()
      : ((route == '190' || route == '491')
            ? '${jurisdictionLabel(jurisdiction, zh: zh)} $route'
            : route);
  final name = nameController.text.trim().isEmpty
      ? routeLabel
      : nameController.text.trim();
  await ref
      .read(appStoreProvider.notifier)
      .addProject(name: name, visaType: routeLabel, applicant: applicant);
}

Future<void> _addChecklistItem(
  BuildContext context,
  WidgetRef ref,
  VisaProject project,
) async {
  final controller = TextEditingController();
  final title = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr(context, '添加材料', 'Add document item')),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: tr(context, '材料名称', 'Document name'),
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
  if (title != null && title.trim().isNotEmpty) {
    await ref
        .read(appStoreProvider.notifier)
        .addChecklistItem(project.id, title.trim());
  }
}

Future<void> _pickPlanDate(
  BuildContext context,
  WidgetRef ref,
  VisaProject project,
  ChecklistItem item,
) async {
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: item.dueDate ?? now.add(const Duration(days: 7)),
    firstDate: now,
    lastDate: DateTime(now.year + 5),
  );
  if (picked == null) return;
  final scheduled = DateTime(picked.year, picked.month, picked.day, 9);
  await ref
      .read(appStoreProvider.notifier)
      .setChecklistPlanDate(
        projectId: project.id,
        itemId: item.id,
        date: scheduled,
      );
}

Future<void> _attachDocument(
  BuildContext context,
  WidgetRef ref,
  VisaProject project,
  ChecklistItem item,
) async {
  final zh = isChineseUi(context);
  final docs = <({String person, String folder, LibraryDocument document})>[];
  for (final person in ref.read(materialLibraryProvider).people) {
    for (final folder in person.folders) {
      for (final document in folder.documents) {
        docs.add((
          person: person.name,
          folder: folder.customName,
          document: document,
        ));
      }
    }
  }
  final choice = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            ListTile(
              title: Text(
                zh ? '关联材料' : 'Link a document',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              subtitle: Text(
                zh
                    ? '优先使用“我的资料”中已经保存的文件'
                    : 'Choose a file already saved in My documents',
              ),
            ),
            Expanded(
              child: docs.isEmpty
                  ? Center(
                      child: Text(
                        zh ? '“我的资料”中还没有文件' : 'No files in My documents yet',
                      ),
                    )
                  : ListView(
                      children: [
                        for (final entry in docs)
                          ListTile(
                            leading: const Icon(
                              Icons.insert_drive_file_outlined,
                            ),
                            title: Text(entry.document.name),
                            subtitle: Text(entry.person),
                            onTap: () => Navigator.pop(context, entry.document),
                          ),
                      ],
                    ),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: Text(zh ? '改为从设备导入' : 'Import from device instead'),
              onTap: () => Navigator.pop(context, 'device'),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice is LibraryDocument) {
    await ref
        .read(appStoreProvider.notifier)
        .linkLibraryAttachment(
          projectId: project.id,
          itemId: item.id,
          document: choice,
        );
  } else if (choice == 'device') {
    final picked = await FilePicker.pickFile();
    if (picked == null) return;
    await ref
        .read(appStoreProvider.notifier)
        .addAttachment(
          projectId: project.id,
          itemId: item.id,
          name: picked.name,
          contentType: _contentType(picked.name),
          bytes: await picked.readAsBytes(),
        );
  }
}

Future<void> _shareApplicationPackage(
  BuildContext context,
  VisaProject project,
) async {
  final archive = Archive();
  var count = 0;
  for (final item in project.items) {
    for (final attachment in item.attachments) {
      final path = attachment.localPath;
      if (path == null) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      final safeFolder = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      archive.addFile(
        ArchiveFile.bytes(
          '$safeFolder/${attachment.name}',
          await file.readAsBytes(),
        ),
      );
      count++;
    }
  }
  if (count == 0) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              '这个申请还没有可分享的附件',
              'This application has no shareable attachments',
            ),
          ),
        ),
      );
    }
    return;
  }
  final bytes = ZipEncoder().encodeBytes(archive);
  await SharePlus.instance.share(
    ShareParams(
      subject: project.name,
      files: [
        XFile.fromData(
          bytes,
          mimeType: 'application/zip',
          name: '${project.name.replaceAll(' ', '_')}.zip',
        ),
      ],
    ),
  );
}

String _contentType(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (lower.endsWith('.doc')) return 'application/msword';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  return 'application/octet-stream';
}
