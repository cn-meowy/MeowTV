/// 缓存来源
enum CacheSource {
  auto, // 方案B播放自动触发
  manual; // 用户手动触发

  static CacheSource fromString(String? value) {
    switch (value) {
      case 'manual':
        return CacheSource.manual;
      default:
        return CacheSource.auto;
    }
  }

  String toStorageString() => name;
}

/// 缓存任务状态（区分 auto 的 paused 状态）
enum CacheTaskStatus {
  none,   // 无缓存
  caching, // 缓存中
  paused, // 已暂停（仅 auto）
  complete, // 已完成
  failed; // 失败

  static CacheTaskStatus fromString(String? value) {
    switch (value) {
      case 'none':
        return CacheTaskStatus.none;
      case 'paused':
        return CacheTaskStatus.paused;
      case 'complete':
        return CacheTaskStatus.complete;
      case 'failed':
        return CacheTaskStatus.failed;
      case 'caching':
      default:
        return CacheTaskStatus.caching;
    }
  }

  String toStorageString() => name;
}

/// 播放缓存元数据
class CacheMeta {
  final String key;
  final String resourceDomain;
  final int vodId;
  final int sourceIndex;
  final int epIndex;
  final String url;
  final int downloadedBytes;
  final int totalBytes;
  final bool isComplete;
  final DateTime createdAt;
  final DateTime lastAccessedAt;

  // === 新增字段 ===
  final CacheSource cacheSource; // 缓存来源，默认为 auto
  final CacheTaskStatus taskStatus; // 任务状态，默认为 caching
  final String? contentType; // 视频 MIME type
  final Map<String, String>? sourceHeaders; // 远程请求需要携带的 headers
  final bool isHls; // 是否为 HLS 流，默认为 false
  final int? cachedSegments; // 已缓存的 TS 分片数
  final int? totalSegments; // 总 TS 分片数

  const CacheMeta({
    required this.key,
    required this.resourceDomain,
    required this.vodId,
    required this.sourceIndex,
    required this.epIndex,
    required this.url,
    this.downloadedBytes = 0,
    this.totalBytes = -1,
    this.isComplete = false,
    required this.createdAt,
    required this.lastAccessedAt,
    // === 新增字段 ===
    this.cacheSource = CacheSource.auto,
    this.taskStatus = CacheTaskStatus.caching,
    this.contentType,
    this.sourceHeaders,
    this.isHls = false,
    this.cachedSegments,
    this.totalSegments,
  });

  CacheMeta copyWith({
    String? key,
    String? resourceDomain,
    int? vodId,
    int? sourceIndex,
    int? epIndex,
    String? url,
    int? downloadedBytes,
    int? totalBytes,
    bool? isComplete,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
    // === 新增字段 ===
    CacheSource? cacheSource,
    CacheTaskStatus? taskStatus,
    String? contentType,
    Map<String, String>? sourceHeaders,
    bool? isHls,
    int? cachedSegments,
    int? totalSegments,
  }) =>
      CacheMeta(
        key: key ?? this.key,
        resourceDomain: resourceDomain ?? this.resourceDomain,
        vodId: vodId ?? this.vodId,
        sourceIndex: sourceIndex ?? this.sourceIndex,
        epIndex: epIndex ?? this.epIndex,
        url: url ?? this.url,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        isComplete: isComplete ?? this.isComplete,
        createdAt: createdAt ?? this.createdAt,
        lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
        // === 新增字段 ===
        cacheSource: cacheSource ?? this.cacheSource,
        taskStatus: taskStatus ?? this.taskStatus,
        contentType: contentType ?? this.contentType,
        sourceHeaders: sourceHeaders ?? this.sourceHeaders,
        isHls: isHls ?? this.isHls,
        cachedSegments: cachedSegments ?? this.cachedSegments,
        totalSegments: totalSegments ?? this.totalSegments,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'resourceDomain': resourceDomain,
        'vodId': vodId,
        'sourceIndex': sourceIndex,
        'epIndex': epIndex,
        'url': url,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        'isComplete': isComplete,
        'createdAt': createdAt.toIso8601String(),
        'lastAccessedAt': lastAccessedAt.toIso8601String(),
        // === 新增字段 ===
        'cacheSource': cacheSource.toStorageString(),
        'taskStatus': taskStatus.toStorageString(),
        'contentType': contentType,
        'sourceHeaders': sourceHeaders,
        'isHls': isHls,
        'cachedSegments': cachedSegments,
        'totalSegments': totalSegments,
      };

  factory CacheMeta.fromJson(Map<String, dynamic> json) => CacheMeta(
        key: json['key'] as String,
        resourceDomain: json['resourceDomain'] as String,
        vodId: json['vodId'] as int,
        sourceIndex: json['sourceIndex'] as int,
        epIndex: json['epIndex'] as int,
        url: json['url'] as String,
        downloadedBytes: json['downloadedBytes'] as int? ?? 0,
        totalBytes: json['totalBytes'] as int? ?? -1,
        isComplete: json['isComplete'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastAccessedAt: DateTime.parse(json['lastAccessedAt'] as String),
        // === 新增字段（向后兼容） ===
        cacheSource: CacheSource.fromString(json['cacheSource'] as String?),
        taskStatus: CacheTaskStatus.fromString(json['taskStatus'] as String?),
        contentType: json['contentType'] as String?,
        sourceHeaders: (json['sourceHeaders'] as Map<String, dynamic>?)?.cast<String, String>(),
        isHls: json['isHls'] as bool? ?? false,
        cachedSegments: json['cachedSegments'] as int?,
        totalSegments: json['totalSegments'] as int?,
      );

  /// 计算下载进度百分比（0.0 - 1.0）
  double get progress {
    if (totalBytes <= 0) return 0.0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  /// 缓存状态：none / partial / complete
  String get status {
    if (isComplete) return 'complete';
    if (downloadedBytes > 0) return 'partial';
    return 'none';
  }
}

/// 缓存下载进度
class CacheDownloadProgress {
  final String key;
  final int downloadedBytes;
  final int totalBytes;
  final bool isComplete;
  final double speed; // bytes/s

  const CacheDownloadProgress({
    required this.key,
    this.downloadedBytes = 0,
    this.totalBytes = -1,
    this.isComplete = false,
    this.speed = 0.0,
  });

  double get progress {
    if (totalBytes <= 0) return 0.0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }
}
