enum NewsSourceType { official, industry, editorial, changeLog }

enum VerificationStatus { autoDetected, pendingReview, verified, corrected }

enum ChangeSeverity { critical, important, general }

enum ProjectStatus { active, paused, archived }

enum ChecklistStatus { notStarted, preparing, ready, sent, confirmed }

enum AttachmentSyncStatus { localOnly, uploading, scanning, available, failed }

class ProjectActivity {
  const ProjectActivity({
    required this.id,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String message;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'message': message,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ProjectActivity.fromJson(Map<String, dynamic> json) =>
      ProjectActivity(
        id: json['id'] as String,
        message: json['message'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class LocalAttachment {
  const LocalAttachment({
    required this.id,
    required this.name,
    required this.contentType,
    required this.byteSize,
    required this.sha256,
    required this.createdAt,
    this.localPath,
    this.remoteId,
    this.syncStatus = AttachmentSyncStatus.localOnly,
  });

  final String id;
  final String name;
  final String contentType;
  final int byteSize;
  final String sha256;
  final DateTime createdAt;
  final String? localPath;
  final String? remoteId;
  final AttachmentSyncStatus syncStatus;

  LocalAttachment copyWith({
    String? localPath,
    bool clearLocalPath = false,
    String? remoteId,
    bool clearRemoteId = false,
    AttachmentSyncStatus? syncStatus,
  }) => LocalAttachment(
    id: id,
    name: name,
    contentType: contentType,
    byteSize: byteSize,
    sha256: sha256,
    createdAt: createdAt,
    localPath: clearLocalPath ? null : localPath ?? this.localPath,
    remoteId: clearRemoteId ? null : remoteId ?? this.remoteId,
    syncStatus: syncStatus ?? this.syncStatus,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'contentType': contentType,
    'byteSize': byteSize,
    'sha256': sha256,
    'createdAt': createdAt.toIso8601String(),
    'localPath': localPath,
    'remoteId': remoteId,
    'syncStatus': syncStatus.name,
  };

  factory LocalAttachment.fromJson(Map<String, dynamic> json) =>
      LocalAttachment(
        id: json['id'] as String,
        name: json['name'] as String,
        contentType:
            json['contentType'] as String? ?? 'application/octet-stream',
        byteSize: json['byteSize'] as int? ?? 0,
        sha256: json['sha256'] as String? ?? '',
        createdAt: json['createdAt'] == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.parse(json['createdAt'] as String),
        localPath: json['localPath'] as String?,
        remoteId: json['remoteId'] as String?,
        syncStatus: AttachmentSyncStatus.values.byName(
          json['syncStatus'] as String? ?? AttachmentSyncStatus.localOnly.name,
        ),
      );
}

extension ChecklistStatusLabel on ChecklistStatus {
  String get label => switch (this) {
    ChecklistStatus.notStarted => '未准备',
    ChecklistStatus.preparing => '准备中',
    ChecklistStatus.ready => '已准备',
    ChecklistStatus.sent => '已发送',
    ChecklistStatus.confirmed => '已确认',
  };

  ChecklistStatus get next =>
      ChecklistStatus.values[(index + 1) % ChecklistStatus.values.length];
}

class NewsItem {
  const NewsItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.sourceName,
    required this.sourceUrl,
    required this.publishedAt,
    required this.sourceType,
    required this.tags,
    this.bookmarked = false,
  });

  final String id;
  final String title;
  final String summary;
  final String sourceName;
  final String sourceUrl;
  final DateTime publishedAt;
  final NewsSourceType sourceType;
  final List<String> tags;
  final bool bookmarked;

  NewsItem copyWith({bool? bookmarked}) => NewsItem(
    id: id,
    title: title,
    summary: summary,
    sourceName: sourceName,
    sourceUrl: sourceUrl,
    publishedAt: publishedAt,
    sourceType: sourceType,
    tags: tags,
    bookmarked: bookmarked ?? this.bookmarked,
  );
}

class PolicyChange {
  const PolicyChange({
    required this.id,
    required this.pageTitle,
    required this.sourceUrl,
    required this.discoveredAt,
    required this.summary,
    required this.beforeText,
    required this.afterText,
    required this.severity,
    required this.verification,
    required this.tags,
  });

  final String id;
  final String pageTitle;
  final String sourceUrl;
  final DateTime discoveredAt;
  final String summary;
  final String beforeText;
  final String afterText;
  final ChangeSeverity severity;
  final VerificationStatus verification;
  final List<String> tags;
}

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.title,
    required this.owner,
    required this.category,
    required this.status,
    this.dueDate,
    this.reminderAt,
    this.note = '',
    this.attachments = const [],
    this.remoteId,
  });

  final String id;
  final String title;
  final String owner;
  final String category;
  final ChecklistStatus status;
  final DateTime? dueDate;
  final DateTime? reminderAt;
  final String note;
  final List<LocalAttachment> attachments;
  final String? remoteId;

  int get attachmentCount => attachments.length;

  ChecklistItem copyWith({
    ChecklistStatus? status,
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? reminderAt,
    bool clearReminderAt = false,
    String? note,
    List<LocalAttachment>? attachments,
    String? remoteId,
  }) => ChecklistItem(
    id: id,
    title: title,
    owner: owner,
    category: category,
    status: status ?? this.status,
    dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
    reminderAt: clearReminderAt ? null : reminderAt ?? this.reminderAt,
    note: note ?? this.note,
    attachments: attachments ?? this.attachments,
    remoteId: remoteId ?? this.remoteId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'owner': owner,
    'category': category,
    'status': status.name,
    'dueDate': dueDate?.toIso8601String(),
    'reminderAt': reminderAt?.toIso8601String(),
    'note': note,
    'attachments': attachments
        .map((attachment) => attachment.toJson())
        .toList(),
    'remoteId': remoteId,
  };

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
    id: json['id'] as String,
    title: json['title'] as String,
    owner: json['owner'] as String? ?? '主申请人',
    category: json['category'] as String? ?? '其他',
    status: ChecklistStatus.values.byName(json['status'] as String),
    dueDate: json['dueDate'] == null
        ? null
        : DateTime.parse(json['dueDate'] as String),
    reminderAt: json['reminderAt'] == null
        ? null
        : DateTime.parse(json['reminderAt'] as String),
    note: json['note'] as String? ?? '',
    attachments: (json['attachments'] as List<dynamic>? ?? const [])
        .map(
          (attachment) =>
              LocalAttachment.fromJson(attachment as Map<String, dynamic>),
        )
        .toList(),
    remoteId: json['remoteId'] as String?,
  );
}

class VisaProject {
  const VisaProject({
    required this.id,
    required this.name,
    required this.visaType,
    required this.applicant,
    required this.status,
    required this.items,
    this.targetDate,
    this.isCloudSyncEnabled = false,
    this.allowViewerDownload = false,
    this.remoteId,
    this.cloudVersion = 1,
    this.activities = const [],
  });

  final String id;
  final String name;
  final String visaType;
  final String applicant;
  final ProjectStatus status;
  final List<ChecklistItem> items;
  final DateTime? targetDate;
  final bool isCloudSyncEnabled;
  final bool allowViewerDownload;
  final String? remoteId;
  final int cloudVersion;
  final List<ProjectActivity> activities;

  double get completion {
    if (items.isEmpty) return 0;
    final done = items
        .where((item) => item.status.index >= ChecklistStatus.ready.index)
        .length;
    return done / items.length;
  }

  VisaProject copyWith({
    List<ChecklistItem>? items,
    bool? isCloudSyncEnabled,
    bool? allowViewerDownload,
    String? remoteId,
    int? cloudVersion,
    List<ProjectActivity>? activities,
  }) => VisaProject(
    id: id,
    name: name,
    visaType: visaType,
    applicant: applicant,
    status: status,
    items: items ?? this.items,
    targetDate: targetDate,
    isCloudSyncEnabled: isCloudSyncEnabled ?? this.isCloudSyncEnabled,
    allowViewerDownload: allowViewerDownload ?? this.allowViewerDownload,
    remoteId: remoteId ?? this.remoteId,
    cloudVersion: cloudVersion ?? this.cloudVersion,
    activities: activities ?? this.activities,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'visaType': visaType,
    'applicant': applicant,
    'status': status.name,
    'items': items.map((item) => item.toJson()).toList(),
    'targetDate': targetDate?.toIso8601String(),
    'isCloudSyncEnabled': isCloudSyncEnabled,
    'allowViewerDownload': allowViewerDownload,
    'remoteId': remoteId,
    'cloudVersion': cloudVersion,
    'activities': activities.map((activity) => activity.toJson()).toList(),
  };

  factory VisaProject.fromJson(Map<String, dynamic> json) => VisaProject(
    id: json['id'] as String,
    name: json['name'] as String,
    visaType: json['visaType'] as String,
    applicant: json['applicant'] as String,
    status: ProjectStatus.values.byName(json['status'] as String),
    items: (json['items'] as List<dynamic>)
        .map((item) => ChecklistItem.fromJson(item as Map<String, dynamic>))
        .toList(),
    targetDate: json['targetDate'] == null
        ? null
        : DateTime.parse(json['targetDate'] as String),
    isCloudSyncEnabled: json['isCloudSyncEnabled'] as bool? ?? false,
    allowViewerDownload: json['allowViewerDownload'] as bool? ?? false,
    remoteId: json['remoteId'] as String?,
    cloudVersion: json['cloudVersion'] as int? ?? 1,
    activities: (json['activities'] as List<dynamic>? ?? const [])
        .map(
          (activity) =>
              ProjectActivity.fromJson(activity as Map<String, dynamic>),
        )
        .toList(),
  );
}
