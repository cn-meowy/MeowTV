import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'cache_meta.dart';
import 'play_cache_service.dart';
import 'play_cache_download_service.dart';
import '../../shared/models/resource_detail.dart';

/// 单个剧集的缓存状态
class EpisodeCacheStatus {
  final String key;
  final String url;
  final String epName;
  final CacheSource cacheSource;   // auto / manual
  final CacheTaskStatus taskStatus; // caching / paused / complete / failed / none
  final double progress;           // 0.0 - 1.0
  final int downloadedBytes;
  final int totalBytes;

  const EpisodeCacheStatus({
    required this.key,
    required this.url,
    this.epName = '',
    this.cacheSource = CacheSource.auto,
    this.taskStatus = CacheTaskStatus.none,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = -1,
  });

  /// 是否已完整缓存
  bool get isComplete => taskStatus == CacheTaskStatus.complete;

  /// 是否正在缓存中
  bool get isCaching => taskStatus == CacheTaskStatus.caching;

  /// 是否有缓存（完整或部分）
  bool get hasCache =>
    taskStatus == CacheTaskStatus.complete ||
    taskStatus == CacheTaskStatus.paused ||
    (downloadedBytes > 0 && !isComplete);
}

/// 缓存状态 Notifier
class CacheStatusNotifier extends StateNotifier<Map<String, EpisodeCacheStatus>> {
  final PlayCacheService _cacheService;
  StreamSubscription? _progressSub;

  CacheStatusNotifier(this._cacheService) : super({}) {
    _listenProgress();
  }

  /// 监听下载进度流
  void _listenProgress() {
    _progressSub = PlayCacheDownloadService.instance.progressStream.listen((progress) {
      if (!mounted) return;
      final current = state[progress.key];
      if (current == null) return;

      final newStatus = EpisodeCacheStatus(
        key: progress.key,
        url: current.url,
        epName: current.epName,
        cacheSource: current.cacheSource,
        taskStatus: progress.isComplete ? CacheTaskStatus.complete : CacheTaskStatus.caching,
        progress: progress.progress,
        downloadedBytes: progress.downloadedBytes,
        totalBytes: progress.totalBytes > 0 ? progress.totalBytes : current.totalBytes,
      );

      state = {...state, progress.key: newStatus};
    });
  }

  /// 批量查询剧集缓存状态
  Future<void> checkStatuses(
    List<PlayEpisode> episodes,
    int sourceIndex,
    String resourceDomain,
    int vodId,
  ) async {
    final newState = Map<String, EpisodeCacheStatus>.from(state);

    for (var i = 0; i < episodes.length; i++) {
      final ep = episodes[i];
      final key = PlayCacheService.instance.cacheKey(resourceDomain, vodId, sourceIndex, i);

      // 检查是否已有状态
      if (newState.containsKey(key)) continue;

      // 查询缓存元数据
      final cacheMeta = await _cacheService.getCacheMeta(key);

      if (cacheMeta != null) {
        newState[key] = EpisodeCacheStatus(
          key: key,
          url: ep.url,
          epName: ep.name,
          cacheSource: cacheMeta.cacheSource,
          taskStatus: cacheMeta.isComplete
              ? CacheTaskStatus.complete
              : (cacheMeta.taskStatus == CacheTaskStatus.paused
                  ? CacheTaskStatus.paused
                  : (cacheMeta.downloadedBytes > 0
                      ? CacheTaskStatus.caching
                      : CacheTaskStatus.none)),
          progress: cacheMeta.progress,
          downloadedBytes: cacheMeta.downloadedBytes,
          totalBytes: cacheMeta.totalBytes > 0 ? cacheMeta.totalBytes : -1,
        );
      } else {
        // 无缓存
        newState[key] = EpisodeCacheStatus(
          key: key,
          url: ep.url,
          epName: ep.name,
        );
      }
    }

    state = newState;
  }

  /// 获取单个剧集缓存状态
  EpisodeCacheStatus? getStatus(String key) => state[key];

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }
}

/// Provider
final cacheStatusProvider =
    StateNotifierProvider<CacheStatusNotifier, Map<String, EpisodeCacheStatus>>((ref) {
  return CacheStatusNotifier(PlayCacheService.instance);
});
