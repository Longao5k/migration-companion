class LibraryDocument {
  const LibraryDocument({
    required this.id,
    required this.name,
    required this.contentType,
    required this.byteSize,
    required this.sha256,
    required this.localPath,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String contentType;
  final int byteSize;
  final String sha256;
  final String localPath;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'contentType': contentType,
    'byteSize': byteSize,
    'sha256': sha256,
    'localPath': localPath,
    'createdAt': createdAt.toIso8601String(),
  };

  factory LibraryDocument.fromJson(Map<String, dynamic> json) =>
      LibraryDocument(
        id: json['id'] as String,
        name: json['name'] as String,
        contentType:
            json['contentType'] as String? ?? 'application/octet-stream',
        byteSize: json['byteSize'] as int? ?? 0,
        sha256: json['sha256'] as String? ?? '',
        localPath: json['localPath'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class MaterialFolder {
  const MaterialFolder({
    required this.id,
    required this.categoryId,
    required this.customName,
    this.documents = const [],
  });

  final String id;
  final String categoryId;
  final String customName;
  final List<LibraryDocument> documents;

  MaterialFolder copyWith({List<LibraryDocument>? documents}) => MaterialFolder(
    id: id,
    categoryId: categoryId,
    customName: customName,
    documents: documents ?? this.documents,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'categoryId': categoryId,
    'customName': customName,
    'documents': documents.map((item) => item.toJson()).toList(),
  };

  factory MaterialFolder.fromJson(Map<String, dynamic> json) => MaterialFolder(
    id: json['id'] as String,
    categoryId: json['categoryId'] as String? ?? 'other',
    customName: json['customName'] as String? ?? '',
    documents: (json['documents'] as List<dynamic>? ?? const [])
        .map((item) => LibraryDocument.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class PersonMaterialProfile {
  const PersonMaterialProfile({
    required this.id,
    required this.name,
    this.folders = const [],
  });

  final String id;
  final String name;
  final List<MaterialFolder> folders;

  PersonMaterialProfile copyWith({List<MaterialFolder>? folders}) =>
      PersonMaterialProfile(
        id: id,
        name: name,
        folders: folders ?? this.folders,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'folders': folders.map((item) => item.toJson()).toList(),
  };

  factory PersonMaterialProfile.fromJson(Map<String, dynamic> json) =>
      PersonMaterialProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        folders: (json['folders'] as List<dynamic>? ?? const [])
            .map(
              (item) => MaterialFolder.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
}
