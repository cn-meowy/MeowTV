import 'dart:async';
import 'dart:io';
import '../logger/app_logger.dart';
import 'cache_meta.dart';
import 'play_cache_service.dart';

/// 播放缓存下载服务。
///
/// 负责边播边下的后台下载逻辑，支持增量续传。
/// 支持手动/自动两种缓存来源，并发控制（最多 3 个同时下载）。
class PlayCacheDownloadService {
  PlayCacheDownloadService._();
  static final PlayCacheDownloadService instance = PlayCacheDownloadService._();

  final PlayCacheService _cacheService = PlayCacheService.instance;

  /// 最大并发下载数
  static const int maxConcurrentDownloads = 3;

  /// 正在进行的下载任务 `Map<key, HttpClient>`
  final Map<String, HttpClient> _activeClients = {};

  /// 等待队列（仅 manual 下载排队，auto 走代理不受此限制）
  final List<_PendingDownload> _pendingQueue = [];

  /// 下载进度流
  final _progressController = StreamController<CacheDownloadProgress>.broadcast();
  Stream<CacheDownloadProgress> get progressStream => _progressController.stream;

  /// 当前并发下载数（仅统计 manual 模式）
  int get currentConcurrentCount => _activeClients.length;

  /// 启动后台下载
  ///
  /// [key] 缓存键
  /// [url] 视频 URL
  /// [startOffset] 起始偏移量（用于增量下载），null 表示从头开始
  /// [cacheSource] 区分手动/自动，手动缓存不受页面生命周期影响
  /// [resourceDomain] 资源域名
  /// [vodId] 视频 ID
  /// [sourceIndex] 片源索引
  /// [epIndex] 集数索引
  Future<void> startDownload(
    String key,
    String url, {
    int? startOffset,
    CacheSource cacheSource = CacheSource.manual,
    String resourceDomain = '',
    int vodId = 0,
    int sourceIndex = 0,
    int epIndex = 0,
  }) async {
    // m3u8 是播放列表文本，不应作为视频文件缓存
    if (url.contains('.m3u8')) {
      appLogger.d('[PlayCacheDownload] 跳过 m3u8 URL 的缓存下载: $key, url=$url');
      return;
    }

    // 1. 已完整缓存 → 跳过
    final meta = await _cacheService.getCacheMeta(key);
    if (meta != null && meta.isComplete) {
      appLogger.d('[PlayCacheDownload] 缓存已完整，跳过: $key');
      return;
    }

    // 2. 代理正在缓存此 key → 跳过（Phase 2 代理上线后生效）
    // if (VideoCacheProxyServer.instance.isActivelyProxying(key)) {
    //   debugPrint('[PlayCacheDownload] 代理正在缓存此资源，跳过重复下载: $key');
    //   return;
    // }

    // 3. 已在下载队列中 → 跳过
    if (_activeClients.containsKey(key)) {
      appLogger.d('[PlayCacheDownload] 已在下载队列中，跳过: $key');
      return;
    }

    // 4. 并发控制（仅对 manual 生效，auto 走代理不受此限制）
    if (cacheSource == CacheSource.manual) {
      if (currentConcurrentCount >= maxConcurrentDownloads) {
        _pendingQueue.add(_PendingDownload(
          key: key,
          url: url,
          startOffset: startOffset,
          cacheSource: cacheSource,
          resourceDomain: resourceDomain,
          vodId: vodId,
          sourceIndex: sourceIndex,
          epIndex: epIndex,
        ));
        appLogger.d('[PlayCacheDownload] 并发满，加入等待队列: $key');
        return;
      }
    }

    // 5. 正常启动下载
    await _doDownload(
      key: key,
      url: url,
      startOffset: startOffset,
      cacheSource: cacheSource,
      resourceDomain: resourceDomain,
      vodId: vodId,
      sourceIndex: sourceIndex,
      epIndex: epIndex,
    );
  }

  /// 内部下载执行（不含并发控制逻辑）
  Future<void> _doDownload({
    required String key,
    required String url,
    int? startOffset,
    required CacheSource cacheSource,
    required String resourceDomain,
    required int vodId,
    required int sourceIndex,
    required int epIndex,
  }) async {
    // 如果已有相同 key 的下载在运行，先停止
    if (_activeClients.containsKey(key)) {
      await stopDownload(key);
    }

    // 在 try 块外声明 downloadedBytes，以便 catch 块也能访问
    int downloadedBytes = startOffset ?? 0;

    try {
      final client = HttpClient();
      _activeClients[key] = client;

      // 创建请求
      final request = await client.getUrl(Uri.parse(url));
      if (startOffset != null && startOffset > 0) {
        request.headers.set('Range', 'bytes=$startOffset-');
      }

      final response = await request.close();
      final totalBytes = response.contentLength;

      // 确定保存路径
      final savePath = startOffset != null && startOffset > 0
          ? await _cacheService.partialCacheFilePath(key)
          : await _cacheService.cacheFilePath(key);

      final file = File(savePath);
      final sink = file.openWrite(mode: startOffset != null && startOffset > 0 ? FileMode.append : FileMode.write);
      DateTime lastUpdate = DateTime.now();
      int lastBytes = downloadedBytes;

      // 流式写入
      await for (final chunk in response) {
        if (!_activeClients.containsKey(key)) {
          // 任务已被取消
          await sink.close();
          return;
        }
        sink.add(chunk);
        downloadedBytes += chunk.length;

        // 每秒更新一次进度
        final now = DateTime.now();
        if (now.difference(lastUpdate).inMilliseconds >= 500) {
          final elapsed = now.difference(lastUpdate).inMilliseconds / 1000.0;
          final speed = elapsed > 0 ? (downloadedBytes - lastBytes) / elapsed : 0.0;
          lastUpdate = now;
          lastBytes = downloadedBytes;

          _progressController.add(CacheDownloadProgress(
            key: key,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes > 0 ? totalBytes + (startOffset ?? 0) : -1,
            isComplete: false,
            speed: speed,
          ));
        }
      }

      await sink.close();

      // 下载完成，获取已有 meta（如果有）
      final existingMeta = await _cacheService.getCacheMeta(key);
      final now = DateTime.now();

      // 下载完成后保存完整 meta
      final completeMeta = CacheMeta(
        key: key,
        resourceDomain: resourceDomain,
        vodId: vodId,
        sourceIndex: sourceIndex,
        epIndex: epIndex,
        url: url,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes > 0 ? totalBytes + (startOffset ?? 0) : downloadedBytes,
        isComplete: true,
        createdAt: existingMeta?.createdAt ?? now,
        lastAccessedAt: now,
        cacheSource: cacheSource,
        taskStatus: CacheTaskStatus.complete,
      );
      await _cacheService.saveCacheMeta(completeMeta);

      _progressController.add(CacheDownloadProgress(
        key: key,
        downloadedBytes: downloadedBytes,
        totalBytes: completeMeta.totalBytes,
        isComplete: true,
        speed: 0,
      ));

      // 如果是部分下载，完成后重命名
      if (startOffset != null && startOffset > 0) {
        final partialPath = await _cacheService.partialCacheFilePath(key);
        final completePath = await _cacheService.cacheFilePath(key);
        final partialFile = File(partialPath);
        if (await partialFile.exists()) {
          await partialFile.rename(completePath);
        }
      }

      appLogger.i('[PlayCacheDownload] 下载完成: $key, 大小: $downloadedBytes');
    } catch (e) {
      appLogger.e('[PlayCacheDownload] 下载失败: $key', error: e);
      // 下载失败时更新 CacheMeta 状态为 failed，保存已下载字节数
      try {
        final existingMeta = await _cacheService.getCacheMeta(key);
        if (existingMeta != null) {
          await _cacheService.saveCacheMeta(existingMeta.copyWith(
            taskStatus: CacheTaskStatus.failed,
            downloadedBytes: downloadedBytes,
          ));
        }
      } catch (metaError) {
        appLogger.e('[PlayCacheDownload] 更新失败状态时出错: $key', error: metaError);
      }
    } finally {
      final client = _activeClients.remove(key);
      client?.close();

      // 下载完成后处理等待队列
      _processNextInQueue();
    }
  }

  /// 处理等待队列中的下一个下载
  void _processNextInQueue() {
    if (_pendingQueue.isEmpty) return;
    if (currentConcurrentCount >= maxConcurrentDownloads) return;

    final next = _pendingQueue.removeAt(0);
    _doDownload(
      key: next.key,
      url: next.url,
      startOffset: next.startOffset,
      cacheSource: next.cacheSource,
      resourceDomain: next.resourceDomain,
      vodId: next.vodId,
      sourceIndex: next.sourceIndex,
      epIndex: next.epIndex,
    );
  }

  /// 批量启动手动缓存（用于 CacheEpisodeDialog）
  Future<void> startBatchDownload(
    List<({
      String key,
      String url,
      String resourceDomain,
      int vodId,
      int sourceIndex,
      int epIndex,
    })> episodes,
  ) async {
    for (final ep in episodes) {
      await startDownload(
        ep.key,
        ep.url,
        cacheSource: CacheSource.manual,
        resourceDomain: ep.resourceDomain,
        vodId: ep.vodId,
        sourceIndex: ep.sourceIndex,
        epIndex: ep.epIndex,
      );
    }
  }

  /// 停止所有自动缓存下载（用于 PlayerScreen dispose）
  ///
  /// 注意：这一步在 Phase 2 代理上线后才有意义
  Future<void> stopAutoDownloads() async {
    // 获取所有 auto 的 meta，停止其下载任务
    final autoMetas = await _cacheService.getAutoCacheList();
    for (final meta in autoMetas) {
      if (_activeClients.containsKey(meta.key)) {
        await stopDownload(meta.key);
        appLogger.d('[PlayCacheDownload] 已停止自动缓存下载: ${meta.key}');
      }
    }
  }

  /// 停止指定缓存下载
  Future<void> stopDownload(String key) async {
    final client = _activeClients.remove(key);
    if (client != null) {
      client.close();
      appLogger.d('[PlayCacheDownload] 已停止下载: $key');
    }

    // 如果是从等待队列移除，不需要额外处理
    // _pendingQueue 的任务会在下载完成时自动触发
  }

  /// 停止所有下载
  Future<void> stopAllDownloads() async {
    // 先清空等待队列
    _pendingQueue.clear();

    // 再停止所有活跃下载
    for (final key in _activeClients.keys.toList()) {
      await stopDownload(key);
    }
    appLogger.i('[PlayCacheDownload] 已停止所有下载');
  }

  /// 检查是否有活跃的下载
  bool isDownloading(String key) => _activeClients.containsKey(key);

  /// 获取活跃下载数量
  int get activeDownloadCount => _activeClients.length;

  /// 获取等待队列长度
  int get pendingCount => _pendingQueue.length;

  void dispose() {
    stopAllDownloads();
    _progressController.close();
  }
}

/// 等待队列中的下载任务
class _PendingDownload {
  final String key;
  final String url;
  final int? startOffset;
  final CacheSource cacheSource;
  final String resourceDomain;
  final int vodId;
  final int sourceIndex;
  final int epIndex;

  const _PendingDownload({
    required this.key,
    required this.url,
    this.startOffset,
    required this.cacheSource,
    required this.resourceDomain,
    required this.vodId,
    required this.sourceIndex,
    required this.epIndex,
  });
}
