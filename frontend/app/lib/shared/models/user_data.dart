/// User data models — mirrors Web SearchHistoryItem, PlayHistoryItem, FavoriteItem, etc.
library;

class SearchHistoryItem {
  final int id;
  final String keyword;
  final int updatedAt;
  const SearchHistoryItem({required this.id, required this.keyword, required this.updatedAt});
  factory SearchHistoryItem.fromJson(Map<String, dynamic> j) => SearchHistoryItem(
    id: j['id'] as int? ?? 0,
    keyword: j['keyword'] as String? ?? '',
    updatedAt: j['updated_at'] as int? ?? 0,
  );
}

class PlayHistoryItem {
  final int id;
  final int vodId;
  final String vodName;
  final String vodPic;
  final String resourceDomain;
  final String resourceName;
  final String groupKey;
  final int sourceIndex;
  final int epIndex;
  final String epName;
  /// 播放进度百分比 (0-100)，与后端/Web 端一致
  final double progress;
  final double currentTime;
  final double duration;
  final int createdAt;
  final int updatedAt;

  const PlayHistoryItem({
    required this.id,
    required this.vodId,
    required this.vodName,
    required this.vodPic,
    required this.resourceDomain,
    required this.resourceName,
    required this.groupKey,
    required this.sourceIndex,
    required this.epIndex,
    required this.epName,
    required this.progress,
    required this.currentTime,
    required this.duration,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PlayHistoryItem.fromJson(Map<String, dynamic> j) => PlayHistoryItem(
    id: (j['id'] as num?)?.toInt() ?? 0,
    vodId: (j['vod_id'] as num?)?.toInt() ?? 0,
    vodName: j['vod_name'] as String? ?? '',
    vodPic: j['vod_pic'] as String? ?? '',
    resourceDomain: j['resource_domain'] as String? ?? '',
    resourceName: j['resource_name'] as String? ?? '',
    groupKey: j['group_key'] as String? ?? '',
    sourceIndex: (j['source_index'] as num?)?.toInt() ?? 0,
    epIndex: (j['ep_index'] as num?)?.toInt() ?? 0,
    epName: j['ep_name'] as String? ?? '',
    progress: (j['progress'] as num?)?.toDouble() ?? 0.0,
    currentTime: (j['current_time'] as num?)?.toDouble() ?? 0.0,
    duration: (j['duration'] as num?)?.toDouble() ?? 0.0,
    createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
    updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
  );
}

class PlayHistoryListResponse {
  final int total;
  final List<PlayHistoryItem> items;
  const PlayHistoryListResponse({required this.total, required this.items});
  factory PlayHistoryListResponse.fromJson(Map<String, dynamic> j) => PlayHistoryListResponse(
    total: j['total'] as int? ?? 0,
    items: (j['items'] as List<dynamic>?)
            ?.map((e) => PlayHistoryItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

class FavoriteItem {
  final int id;
  final int vodId;
  final String vodName;
  final String vodPic;
  final String doubanId;
  final String groupKey;
  final String site;
  final String resourceDomain;
  final String resourceName;
  final int createdAt;

  const FavoriteItem({
    required this.id,
    required this.vodId,
    required this.vodName,
    required this.vodPic,
    required this.doubanId,
    required this.groupKey,
    required this.site,
    required this.resourceDomain,
    required this.resourceName,
    required this.createdAt,
  });

  factory FavoriteItem.fromJson(Map<String, dynamic> j) => FavoriteItem(
    id: j['id'] as int? ?? 0,
    vodId: j['vod_id'] as int? ?? 0,
    vodName: j['vod_name'] as String? ?? '',
    vodPic: j['vod_pic'] as String? ?? '',
    doubanId: j['douban_id']?.toString() ?? '',
    groupKey: j['group_key'] as String? ?? '',
    site: j['site'] as String? ?? '',
    resourceDomain: j['resource_domain'] as String? ?? '',
    resourceName: j['resource_name'] as String? ?? '',
    createdAt: j['created_at'] as int? ?? 0,
  );
}

class FavoriteListResponse {
  final int total;
  final List<FavoriteItem> items;
  const FavoriteListResponse({required this.total, required this.items});
  factory FavoriteListResponse.fromJson(Map<String, dynamic> j) => FavoriteListResponse(
    total: j['total'] as int? ?? 0,
    items: (j['items'] as List<dynamic>?)
            ?.map((e) => FavoriteItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

class FavoriteCheckResponse {
  final bool isFavorite;
  const FavoriteCheckResponse({required this.isFavorite});
  factory FavoriteCheckResponse.fromJson(Map<String, dynamic> j) => FavoriteCheckResponse(
    isFavorite: j['is_favorite'] as bool? ?? false,
  );
}
