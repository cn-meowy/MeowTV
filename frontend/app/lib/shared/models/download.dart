import 'enums.dart';

/// Download task item — mirrors Web DownloadTaskItem.
class DownloadTaskItem {
  final int id;
  final int vodId;
  final String vodName;
  final String vodPic;
  final String epName;
  final String resourceDomain;
  final String resourceName;
  final String groupKey;
  final int sourceIndex;
  final int epIndex;
  final DownloadStatus status;
  final double progress;
  final int totalSegments;
  final int downloadedSegments;
  final int fileSize;
  final String errorMsg;
  final int createdAt;
  final int updatedAt;

  const DownloadTaskItem({
    required this.id,
    required this.vodId,
    required this.vodName,
    required this.vodPic,
    required this.epName,
    required this.resourceDomain,
    required this.resourceName,
    required this.groupKey,
    required this.sourceIndex,
    required this.epIndex,
    required this.status,
    required this.progress,
    required this.totalSegments,
    required this.downloadedSegments,
    required this.fileSize,
    required this.errorMsg,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DownloadTaskItem.fromJson(Map<String, dynamic> j) => DownloadTaskItem(
    id: j['id'] as int? ?? 0,
    vodId: j['vod_id'] as int? ?? 0,
    vodName: j['vod_name'] as String? ?? '',
    vodPic: j['vod_pic'] as String? ?? '',
    epName: j['ep_name'] as String? ?? '',
    resourceDomain: j['resource_domain'] as String? ?? '',
    resourceName: j['resource_name'] as String? ?? '',
    groupKey: j['group_key'] as String? ?? '',
    sourceIndex: j['source_index'] as int? ?? 0,
    epIndex: j['ep_index'] as int? ?? 0,
    status: _parseStatus(j['status'] as int? ?? 0),
    progress: ((j['progress'] as num?)?.toDouble() ?? 0.0) / 100.0,
    totalSegments: j['total_segments'] as int? ?? 0,
    downloadedSegments: j['downloaded_segments'] as int? ?? 0,
    fileSize: j['file_size'] as int? ?? 0,
    errorMsg: j['error_msg'] as String? ?? '',
    createdAt: j['created_at'] as int? ?? 0,
    updatedAt: j['updated_at'] as int? ?? 0,
  );

  /// 优化：为 ListView diff 性能，只比较 id 和 status。
  /// 其它字段（如 progress）变化不应触发整个列表重建。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadTaskItem &&
          id == other.id &&
          status == other.status;

  /// 优化：只 hash id，避免 progress 变化导致 hash 变化触发重建。
  @override
  int get hashCode => Object.hash(id, status);

  static DownloadStatus _parseStatus(int v) {
    switch (v) {
      case 0: return DownloadStatus.queued;
      case 1: return DownloadStatus.parsing;
      case 2: return DownloadStatus.downloading;
      case 3: return DownloadStatus.merging;
      case 4: return DownloadStatus.completed;
      case 5: return DownloadStatus.failed;
      case 6: return DownloadStatus.cancelled;
      default: return DownloadStatus.failed;
    }
  }
}

class DownloadListResponse {
  final int total;
  final List<DownloadTaskItem> items;
  const DownloadListResponse({required this.total, required this.items});
  factory DownloadListResponse.fromJson(Map<String, dynamic> j) => DownloadListResponse(
    total: j['total'] as int? ?? 0,
    items: (j['items'] as List<dynamic>?)
            ?.map((e) => DownloadTaskItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

class DownloadCheckResponse {
  final bool found;
  final int taskId;
  final String fileUrl;
  final String fileFormat;
  const DownloadCheckResponse({required this.found, required this.taskId, required this.fileUrl, required this.fileFormat});
  factory DownloadCheckResponse.fromJson(Map<String, dynamic> j) => DownloadCheckResponse(
    found: j['found'] as bool? ?? false,
    taskId: j['task_id'] as int? ?? 0,
    fileUrl: j['file_url'] as String? ?? '',
    fileFormat: j['file_format'] as String? ?? 'mp4',
  );
}
