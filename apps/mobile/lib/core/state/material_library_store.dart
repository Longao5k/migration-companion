import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/material_library.dart';
import '../storage/attachment_storage.dart';
import '../storage/local_repository.dart';

class MaterialLibraryState {
  const MaterialLibraryState({this.people = const [], this.isHydrated = false});

  final List<PersonMaterialProfile> people;
  final bool isHydrated;

  MaterialLibraryState copyWith({
    List<PersonMaterialProfile>? people,
    bool? isHydrated,
  }) => MaterialLibraryState(
    people: people ?? this.people,
    isHydrated: isHydrated ?? this.isHydrated,
  );
}

class MaterialLibraryStore extends StateNotifier<MaterialLibraryState> {
  MaterialLibraryStore(this._repository, [AttachmentStorage? storage])
    : _storage = storage ?? createAttachmentStorage(),
      super(const MaterialLibraryState()) {
    ready = _hydrate();
  }

  static const _key = 'migration_companion.material_library.v1';
  final LocalRepository _repository;
  final AttachmentStorage _storage;
  final _uuid = const Uuid();
  late final Future<void> ready;

  Future<void> _hydrate() async {
    final raw = await _repository.read(_key);
    var people = <PersonMaterialProfile>[];
    if (raw != null) {
      try {
        people = (jsonDecode(raw) as List<dynamic>)
            .map(
              (item) =>
                  PersonMaterialProfile.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      } catch (_) {
        people = <PersonMaterialProfile>[];
      }
    }
    state = state.copyWith(people: people, isHydrated: true);
  }

  Future<void> _persist() => _repository.write(
    _key,
    jsonEncode(state.people.map((person) => person.toJson()).toList()),
  );

  Future<PersonMaterialProfile> addPerson(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const FormatException('Name cannot be empty');
    final person = PersonMaterialProfile(id: _uuid.v4(), name: trimmed);
    state = state.copyWith(people: [...state.people, person]);
    await _persist();
    return person;
  }

  Future<void> removePerson(String personId) async {
    final person = state.people.firstWhere((item) => item.id == personId);
    for (final folder in person.folders) {
      for (final document in folder.documents) {
        await _storage.remove(document.localPath);
      }
    }
    state = state.copyWith(
      people: state.people.where((item) => item.id != personId).toList(),
    );
    await _persist();
  }

  Future<MaterialFolder> addFolder({
    required String personId,
    required String categoryId,
    String customName = '',
  }) async {
    final name = customName.trim();
    if (categoryId == 'custom' && name.isEmpty) {
      throw const FormatException('Custom folder name cannot be empty');
    }
    final folder = MaterialFolder(
      id: _uuid.v4(),
      categoryId: categoryId,
      customName: name,
    );
    state = state.copyWith(
      people: state.people.map((person) {
        if (person.id != personId) return person;
        return person.copyWith(folders: [...person.folders, folder]);
      }).toList(),
    );
    await _persist();
    return folder;
  }

  Future<LibraryDocument> addDocument({
    required String personId,
    required String folderId,
    required String name,
    required Uint8List bytes,
    String? contentType,
  }) async {
    if (bytes.isEmpty) throw const FormatException('The file is empty');
    if (bytes.length > 50 * 1024 * 1024) {
      throw const FormatException('A file cannot exceed 50 MB');
    }
    final id = _uuid.v4();
    final localPath = await _storage.persist(
      projectId: 'person-$personId',
      attachmentId: id,
      originalName: name,
      bytes: bytes,
    );
    if (localPath == null) {
      throw const FormatException(
        'Please add files in the Android or iPhone app',
      );
    }
    final document = LibraryDocument(
      id: id,
      name: name,
      contentType: contentType ?? _contentType(name),
      byteSize: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      localPath: localPath,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      people: state.people.map((person) {
        if (person.id != personId) return person;
        return person.copyWith(
          folders: person.folders.map((folder) {
            if (folder.id != folderId) return folder;
            return folder.copyWith(documents: [...folder.documents, document]);
          }).toList(),
        );
      }).toList(),
    );
    await _persist();
    return document;
  }

  Future<void> removeDocument({
    required String personId,
    required String folderId,
    required String documentId,
  }) async {
    final person = state.people.firstWhere((item) => item.id == personId);
    final folder = person.folders.firstWhere((item) => item.id == folderId);
    final document = folder.documents.firstWhere(
      (item) => item.id == documentId,
    );
    await _storage.remove(document.localPath);
    state = state.copyWith(
      people: state.people.map((candidate) {
        if (candidate.id != personId) return candidate;
        return candidate.copyWith(
          folders: candidate.folders.map((candidateFolder) {
            if (candidateFolder.id != folderId) return candidateFolder;
            return candidateFolder.copyWith(
              documents: candidateFolder.documents
                  .where((item) => item.id != documentId)
                  .toList(),
            );
          }).toList(),
        );
      }).toList(),
    );
    await _persist();
  }
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

final materialLibraryProvider =
    StateNotifierProvider<MaterialLibraryStore, MaterialLibraryState>(
      (ref) => MaterialLibraryStore(createLocalRepository()),
    );
