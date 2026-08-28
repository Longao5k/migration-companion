enum NewsSourceType { official, industry, editorial, changeLog }

enum VerificationStatus { autoDetected, pendingReview, verified, corrected }

enum ChangeSeverity { critical, important, general }

enum ProjectStatus { active, paused, archived }

enum ChecklistStatus { notStarted, preparing, ready, sent, confirmed }

enum AttachmentSyncStatus { localOnly, uploading, scanning, available, failed }

enum ProjectSyncStatus { localOnly, synced, pending, conflict, error }

enum SyncOperationKind { addChecklist, updateChecklist }

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
    this.uploadSessionId,
    this.uploadSessionUploaded = false,
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
  final String? uploadSessionId;
  final bool uploadSessionUploaded;

  LocalAttachment copyWith({
    String? localPath,
    bool clearLocalPath = false,
    String? remoteId,
    bool clearRemoteId = false,
    AttachmentSyncStatus? syncStatus,
    String? uploadSessionId,
    bool clearUploadSession = false,
    bool? uploadSessionUploaded,
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
    uploadSessionId: clearUploadSession
        ? null
        : uploadSessionId ?? this.uploadSessionId,
    uploadSessionUploaded: clearUploadSession
        ? false
        : uploadSessionUploaded ?? this.uploadSessionUploaded,
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
    'uploadSessionId': uploadSessionId,
    'uploadSessionUploaded': uploadSessionUploaded,
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
        uploadSessionId: json['uploadSessionId'] as String?,
        uploadSessionUploaded: json['uploadSessionUploaded'] as bool? ?? false,
      );
}

/// 核实状态的唯一文案来源。
///
/// 冻结规则：重大/重要变化必须人工核实后才能公开，一般变化只能标为“自动发现、待核实”。
/// 任何界面都不得用严重程度或其他字段推导核实状态——那会把未经人工核实的变化说成已核实。
extension VerificationStatusLabel on VerificationStatus {
  String get label => switch (this) {
    VerificationStatus.verified => '已人工核实',
    VerificationStatus.corrected => '已更正',
    VerificationStatus.pendingReview => '待人工核实',
    VerificationStatus.autoDetected => '自动发现 · 待人工核实',
  };

  /// 是否经过人工处理。更正过的条目同样是人工处理过的，不能显示为“待核实”。
  bool get isHumanReviewed =>
      this == VerificationStatus.verified ||
      this == VerificationStatus.corrected;
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
    this.sourceTitle,
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

  /// 官方页面的原标题（英文）。中文标题是我们编辑写的，原标题是官方写的——
  /// 真正有法律效力的是后者，所以详情页要能看到它，不能只留译文。
  final String? sourceTitle;
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
    sourceTitle: sourceTitle,
    sourceUrl: sourceUrl,
    publishedAt: publishedAt,
    sourceType: sourceType,
    tags: tags,
    bookmarked: bookmarked ?? this.bookmarked,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'summary': summary,
    'sourceName': sourceName,
    'sourceTitle': sourceTitle,
    'sourceUrl': sourceUrl,
    'publishedAt': publishedAt.toIso8601String(),
    'sourceType': sourceType.name,
    'tags': tags,
    'bookmarked': bookmarked,
  };

  factory NewsItem.fromJson(Map<String, dynamic> json) => NewsItem(
    id: json['id'] as String,
    title: json['title'] as String,
    summary: json['summary'] as String,
    sourceName: json['sourceName'] as String,
    sourceTitle: (json['sourceTitle'] as String?)?.trim().isEmpty ?? true
        ? null
        : (json['sourceTitle'] as String).trim(),
    sourceUrl: json['sourceUrl'] as String,
    publishedAt: DateTime.parse(json['publishedAt'] as String),
    sourceType: NewsSourceType.values.byName(
      json['sourceType'] as String? ?? NewsSourceType.official.name,
    ),
    tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
    bookmarked: json['bookmarked'] as bool? ?? false,
  );
}

/// 官方页面的监控状态。
///
/// 变更列表为空有两种完全不同的含义：「已在监控，确实没有变化」和「根本没在监控」。
/// 对移民产品，把后者显示成前者等于告诉用户「政策没变」，因此必须区分。
/// 一个辖区的监控覆盖情况。
class JurisdictionCoverage {
  const JurisdictionCoverage({
    required this.jurisdiction,
    required this.monitoredCount,
    required this.unavailableCount,
  });

  final String jurisdiction;
  final int monitoredCount;
  final int unavailableCount;

  bool get isFullyDown => monitoredCount == 0 && unavailableCount > 0;
  bool get isPartlyDown => monitoredCount > 0 && unavailableCount > 0;

  String get label => switch (jurisdiction) {
    'AU-SA' => '南澳',
    'AU-FED' => '联邦',
    _ => jurisdiction,
  };

  Map<String, Object?> toJson() => {
    'jurisdiction': jurisdiction,
    'monitoredCount': monitoredCount,
    'unavailableCount': unavailableCount,
  };

  factory JurisdictionCoverage.fromJson(Map<String, dynamic> json) =>
      JurisdictionCoverage(
        jurisdiction: json['jurisdiction'] as String? ?? '',
        monitoredCount: json['monitoredCount'] as int? ?? 0,
        unavailableCount: json['unavailableCount'] as int? ?? 0,
      );
}

class MonitoringStatus {
  const MonitoringStatus({
    required this.monitoredCount,
    required this.unavailableCount,
    this.pendingReviewCount = 0,
    this.jurisdictions = const [],
    this.lastSuccessAt,
  });

  final int monitoredCount;
  final int unavailableCount;

  /// 已经发现、但重要到必须先人工核实才发布的改动条数。
  ///
  /// 列表为空有第三种含义：不是「没变」，是「变了，我们还在核」。对着一个正在
  /// 核实的政策改动说「暂时没有变化」，是这个产品最不能犯的错。
  final int pendingReviewCount;
  final List<JurisdictionCoverage> jurisdictions;
  final DateTime? lastSuccessAt;

  bool get hasGap => unavailableCount > 0;

  /// 完全监控不到的辖区。这些才可以说「看不到那部分的变化」。
  List<JurisdictionCoverage> get fullyDown =>
      jurisdictions.where((entry) => entry.isFullyDown).toList();

  /// 只有部分页面取不到的辖区。
  ///
  /// 联邦就是这种情况：内政部的说明页抓不到，但 Migration Act 和 Migration
  /// Regulations 一直在监控。笼统地说「联邦监控不到」会让人以为法规变动我们
  /// 也看不见——那是把话说反了。
  List<JurisdictionCoverage> get partlyDown =>
      jurisdictions.where((entry) => entry.isPartlyDown).toList();

  /// 缺口的一句话描述；没有缺口时返回 null。
  String? get gapSentence {
    final full = fullyDown.map((entry) => entry.label).toList();
    final partial = partlyDown.map((entry) => entry.label).toList();
    final parts = [
      if (full.isNotEmpty) '${full.join('、')}的页面现在监控不到',
      if (partial.isNotEmpty) '${partial.join('、')}有部分页面监控不到',
    ];
    if (parts.isEmpty) return null;
    return parts.join('，');
  }

  Map<String, Object?> toJson() => {
    'monitoredCount': monitoredCount,
    'unavailableCount': unavailableCount,
    'pendingReviewCount': pendingReviewCount,
    'jurisdictions': jurisdictions.map((entry) => entry.toJson()).toList(),
    'lastSuccessAt': lastSuccessAt?.toIso8601String(),
  };

  factory MonitoringStatus.fromJson(Map<String, dynamic> json) {
    final raw = json['jurisdictions'] as List<dynamic>?;
    return MonitoringStatus(
      monitoredCount: json['monitoredCount'] as int? ?? 0,
      unavailableCount: json['unavailableCount'] as int? ?? 0,
      pendingReviewCount: json['pendingReviewCount'] as int? ?? 0,
      jurisdictions: (raw ?? const [])
          .cast<Map<String, dynamic>>()
          .map(JurisdictionCoverage.fromJson)
          .toList(),
      lastSuccessAt: json['lastSuccessAt'] == null
          ? null
          : DateTime.tryParse(json['lastSuccessAt'] as String),
    );
  }
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

  Map<String, Object?> toJson() => {
    'id': id,
    'pageTitle': pageTitle,
    'sourceUrl': sourceUrl,
    'discoveredAt': discoveredAt.toIso8601String(),
    'summary': summary,
    'beforeText': beforeText,
    'afterText': afterText,
    'severity': severity.name,
    'verification': verification.name,
    'tags': tags,
  };

  factory PolicyChange.fromJson(Map<String, dynamic> json) => PolicyChange(
    id: json['id'] as String,
    pageTitle: json['pageTitle'] as String,
    sourceUrl: json['sourceUrl'] as String,
    discoveredAt: DateTime.parse(json['discoveredAt'] as String),
    summary: json['summary'] as String,
    beforeText: json['beforeText'] as String? ?? '',
    afterText: json['afterText'] as String? ?? '',
    severity: ChangeSeverity.values.byName(
      json['severity'] as String? ?? ChangeSeverity.general.name,
    ),
    verification: VerificationStatus.values.byName(
      json['verification'] as String? ?? VerificationStatus.pendingReview.name,
    ),
    tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
  );
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
    bool clearRemoteId = false,
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
    remoteId: clearRemoteId ? null : remoteId ?? this.remoteId,
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
    this.syncStatus = ProjectSyncStatus.localOnly,
    this.pendingSyncCount = 0,
    this.syncMessage,
    this.lastSyncedAt,
    this.cloudRole = 'OWNER',
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
  final ProjectSyncStatus syncStatus;
  final int pendingSyncCount;
  final String? syncMessage;
  final DateTime? lastSyncedAt;
  final String cloudRole;

  /// 视为「已办好」的材料项数量。
  int get doneCount => items
      .where((item) => item.status.index >= ChecklistStatus.ready.index)
      .length;

  double get completion {
    if (items.isEmpty) return 0;
    return doneCount / items.length;
  }

  /// 用户接下来该做的那一项。
  ///
  /// 进度条只回答「做了多少」，不回答「我现在干什么」。有到期日的先排到期日，
  /// 没有的按清单顺序——这样打开申请页第一眼看到的就是下一步，而不是一个百分比。
  ChecklistItem? get nextAction {
    final pending = items
        .where((item) => item.status.index < ChecklistStatus.ready.index)
        .toList();
    if (pending.isEmpty) return null;
    pending.sort((a, b) {
      final left = a.dueDate;
      final right = b.dueDate;
      if (left != null && right != null) return left.compareTo(right);
      if (left != null) return -1;
      if (right != null) return 1;
      return 0;
    });
    return pending.first;
  }

  VisaProject copyWith({
    List<ChecklistItem>? items,
    bool? isCloudSyncEnabled,
    bool? allowViewerDownload,
    String? remoteId,
    bool clearRemoteId = false,
    int? cloudVersion,
    List<ProjectActivity>? activities,
    ProjectSyncStatus? syncStatus,
    int? pendingSyncCount,
    String? syncMessage,
    bool clearSyncMessage = false,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
    String? cloudRole,
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
    remoteId: clearRemoteId ? null : remoteId ?? this.remoteId,
    cloudVersion: cloudVersion ?? this.cloudVersion,
    activities: activities ?? this.activities,
    syncStatus: syncStatus ?? this.syncStatus,
    pendingSyncCount: pendingSyncCount ?? this.pendingSyncCount,
    syncMessage: clearSyncMessage ? null : syncMessage ?? this.syncMessage,
    lastSyncedAt: clearLastSyncedAt ? null : lastSyncedAt ?? this.lastSyncedAt,
    cloudRole: cloudRole ?? this.cloudRole,
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
    'syncStatus': syncStatus.name,
    'pendingSyncCount': pendingSyncCount,
    'syncMessage': syncMessage,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    'cloudRole': cloudRole,
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
    syncStatus: ProjectSyncStatus.values.byName(
      json['syncStatus'] as String? ??
          ((json['isCloudSyncEnabled'] as bool? ?? false)
              ? ProjectSyncStatus.synced.name
              : ProjectSyncStatus.localOnly.name),
    ),
    pendingSyncCount: json['pendingSyncCount'] as int? ?? 0,
    syncMessage: json['syncMessage'] as String?,
    lastSyncedAt: json['lastSyncedAt'] == null
        ? null
        : DateTime.parse(json['lastSyncedAt'] as String),
    cloudRole: json['cloudRole'] as String? ?? 'OWNER',
  );
}

class PendingSyncOperation {
  const PendingSyncOperation({
    required this.id,
    required this.projectId,
    required this.itemId,
    required this.kind,
    required this.createdAt,
    this.title,
    this.category,
    this.status,
    this.note,
    this.dueAt,
    this.reminderAt,
  });

  final String id;
  final String projectId;
  final String itemId;
  final SyncOperationKind kind;
  final DateTime createdAt;
  final String? title;
  final String? category;
  final ChecklistStatus? status;
  final String? note;
  final DateTime? dueAt;
  final DateTime? reminderAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'projectId': projectId,
    'itemId': itemId,
    'kind': kind.name,
    'createdAt': createdAt.toIso8601String(),
    'title': title,
    'category': category,
    'status': status?.name,
    'note': note,
    'dueAt': dueAt?.toIso8601String(),
    'reminderAt': reminderAt?.toIso8601String(),
  };

  factory PendingSyncOperation.fromJson(Map<String, dynamic> json) =>
      PendingSyncOperation(
        id: json['id'] as String,
        projectId: json['projectId'] as String,
        itemId: json['itemId'] as String,
        kind: SyncOperationKind.values.byName(json['kind'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        title: json['title'] as String?,
        category: json['category'] as String?,
        status: json['status'] == null
            ? null
            : ChecklistStatus.values.byName(json['status'] as String),
        note: json['note'] as String?,
        dueAt: json['dueAt'] == null
            ? null
            : DateTime.parse(json['dueAt'] as String),
        reminderAt: json['reminderAt'] == null
            ? null
            : DateTime.parse(json['reminderAt'] as String),
      );
}
