import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:migration_companion/core/models/material_library.dart';
import 'package:migration_companion/core/state/app_store.dart';
import 'package:migration_companion/core/state/material_library_store.dart';

import 'support/store_fakes.dart';

void main() {
  test('library persists people, folders and documents', () async {
    final repository = InMemoryRepository();
    final storage = RecordingAttachmentStorage();
    final store = MaterialLibraryStore(repository, storage);
    await store.ready;

    final person = await store.addPerson('A');
    final folder = await store.addFolder(
      personId: person.id,
      categoryId: 'identity',
    );
    await store.addDocument(
      personId: person.id,
      folderId: folder.id,
      name: 'passport.pdf',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    final restored = MaterialLibraryStore(repository, storage);
    await restored.ready;
    expect(restored.state.people.single.name, 'A');
    expect(
      restored.state.people.single.folders.single.documents.single.name,
      'passport.pdf',
    );
  });

  test('a mutation waits for hydration before persisting', () async {
    final repository = _DelayedReadRepository();
    final storage = RecordingAttachmentStorage();
    repository.values['migration_companion.material_library.v1'] = jsonEncode([
      PersonMaterialProfile(id: 'existing', name: 'Existing').toJson(),
    ]);
    final store = MaterialLibraryStore(repository, storage);

    final adding = store.addPerson('New');
    await Future<void>.delayed(Duration.zero);
    expect(store.state.isHydrated, isFalse);

    repository.allowRead.complete();
    await adding;

    expect(store.state.people.map((person) => person.name), [
      'Existing',
      'New',
    ]);
    final restored = MaterialLibraryStore(repository, storage);
    await restored.ready;
    expect(restored.state.people.map((person) => person.name), [
      'Existing',
      'New',
    ]);
  });

  test(
    'unlinking an application attachment does not delete its library file',
    () async {
      final repository = InMemoryRepository();
      final storage = RecordingAttachmentStorage();
      final store = AppStore(repository, storage, SilentNotificationService());
      await store.ready;
      final project = await store.addProject(
        name: 'Test',
        visaType: '189',
        applicant: 'A',
      );
      final item = project.items.first;
      final linked = LibraryDocument(
        id: 'library-doc',
        name: 'passport.pdf',
        contentType: 'application/pdf',
        byteSize: 3,
        sha256: 'abc',
        localPath: '/private/person/passport.pdf',
        createdAt: DateTime(2026),
      );
      storage.paths[linked.localPath] = Uint8List.fromList([1, 2, 3]);

      final attachment = await store.linkLibraryAttachment(
        projectId: project.id,
        itemId: item.id,
        document: linked,
      );
      await store.removeAttachment(
        projectId: project.id,
        itemId: item.id,
        attachmentId: attachment.id,
      );

      expect(storage.paths[linked.localPath], isNotNull);
    },
  );
}

class _DelayedReadRepository extends InMemoryRepository {
  final allowRead = Completer<void>();

  @override
  Future<String?> read(String key) async {
    await allowRead.future;
    return super.read(key);
  }
}
