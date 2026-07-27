import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../logger/app_logger.dart';
import 'cache_meta.dart';

/// 播放缓存管理服务。
///
/// 负责 play_cache/ 目录管理、缓存状态查询、缓存清理。
class PlayCacheService {
  PlayCacheService._();
  static final PlayCacheService instance = PlayCacheService._();

  static const String _cacheDirName = 'play_cache';
  static const String _metaDirName = '.meta';

  Directory? _cacheDir;
  Directory? _metaDir;

  /// 已缓存的缓存总大小（增量维护，避免每次遍历文件系统）
  int _cachedSize = -1;

  /// 获取/创建缓存目录
  Future<Directory> get cacheDir async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${appDir.path}/$_cacheDirName');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  /// 获取/创建元数据目录
  Future<Directory> get metaDir async {
    if (_metaDir != null) return _metaDir!;
    final cache = await cacheDir;
    _metaDir = Directory('${cache.path}/$_metaDirName');
    if (!await _metaDir!.exists()) {
      await _metaDir!.create(recursive: true);
    }
    return _metaDir!;
  }

  /// 生成缓存键
  String cacheKey(String resourceDomain, int vodId, int sourceIndex, int epIndex) {
    return '${resourceDomain}_${vodId}_s${sourceIndex}_e$epIndex';
  }

  /// 获取缓存文件路径（完整缓存）
  Future<String> cacheFilePath(String key) async {
    final cache = await cacheDir;
    return '${cache.path}/$key.mp4';
  }

  /// 获取部分缓存文件路径
  Future<String> partialCacheFilePath(String key) async {
    final cache = await cacheDir;
    return '${cache.path}/${key}_partial.mp4';
  }

  /// 获取元数据文件路径
  Future<String> metaFilePath(String key) async {
    final meta = await metaDir;
    return '${meta.path}/$key.json';
  }

  /// 读取缓存元数据
  Future<CacheMeta?> getCacheMeta(String key) async {
    try {
      final path = await metaFilePath(key);
      final file = File(path);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return CacheMeta.fromJson(json);
    } catch (e) {
      appLogger.e('[PlayCache] getCacheMeta 失败', error: e);
      return null;
    }
  }

  /// 保存缓存元数据
  Future<void> saveCacheMeta(CacheMeta meta) async {
    try {
      final path = await metaFilePath(meta.key);
      final file = File(path);
      await file.writeAsString(jsonEncode(meta.toJson()));
    } catch (e) {
      appLogger.e('[PlayCache] saveCacheMeta 失败', error: e);
    }
  }

  /// 检查缓存是否存在
  Future<bool> cacheExists(String key) async {
    final path = await cacheFilePath(key);
    return File(path).exists();
  }

  /// 检查部分缓存是否存在
  Future<bool> partialCacheExists(String key) async {
    final path = await partialCacheFilePath(key);
    return File(path).exists();
  }

  /// 获取缓存文件
  Future<File?> getCacheFile(String key) async {
    // 优先完整缓存
    final completePath = await cacheFilePath(key);
    final completeFile = File(completePath);
    if (await completeFile.exists()) return completeFile;

    // 其次部分缓存
    final partialPath = await partialCacheFilePath(key);
    final partialFile = File(partialPath);
    if (await partialFile.exists()) return partialFile;

    return null;
  }

  /// 缓存是否完整
  Future<bool> isCacheComplete(String key) async {
    final meta = await getCacheMeta(key);
    return meta?.isComplete ?? false;
  }

  /// 删除缓存元数据
  Future<void> deleteCacheMeta(String key) async {
    try {
      final path = await metaFilePath(key);
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      appLogger.e('[PlayCache] deleteCacheMeta 失败', error: e);
    }
  }

  /// 获取缓存状态
  Future<String> getCacheStatus(String key) async {
    final meta = await getCacheMeta(key);
    if (meta == null) return 'none';
    if (meta.isComplete) return 'complete';
    if (meta.downloadedBytes > 0) return 'partial';
    return 'none';
  }

  /// 更新最后访问时间
  Future<void> updateLastAccessed(String key) async {
    final meta = await getCacheMeta(key);
    if (meta != null) {
      await saveCacheMeta(meta.copyWith(lastAccessedAt: DateTime.now()));
    }
  }

  /// 计算总缓存大小。
  ///
  /// 首次调用遍历文件系统并缓存结果，后续调用直接返回缓存值。
  /// 调用 [invalidateCacheSize] 可使缓存失效，下次调用时重新计算。
  Future<int> getCacheSize() async {
    if (_cachedSize >= 0) return _cachedSize;
    int total = 0;
    try {
      final cache = await cacheDir;
      await for (final entity in cache.list(recursive: true)) {
        // 只统计文件，跳过 .meta 目录内的元数据文件
        if (entity is File && !entity.path.contains('/$_metaDirName/')) {
          total += await entity.length();
        }
      }
    } catch (e) {
      appLogger.e('[PlayCache] getCacheSize 失败', error: e);
    }
    _cachedSize = total;
    return total;
  }

  /// 使缓存大小缓存失效。
  ///
  /// 在文件增删后调用，下次 [getCacheSize] 时会重新遍历计算。
  void invalidateCacheSize() {
    _cachedSize = -1;
  }

  /// 清除所有缓存
  Future<void> clearAllCache() async {
    try {
      final cache = await cacheDir;
      await for (final entity in cache.list(recursive: true)) {
        if (entity is File) {
          await entity.delete();
        }
      }
      invalidateCacheSize();
      appLogger.i('[PlayCache] 已清除所有缓存');
    } catch (e) {
      appLogger.e('[PlayCache] clearAllCache 失败', error: e);
    }
  }

  /// 获取缓存文件数量
  Future<int> getCacheCount() async {
    int count = 0;
    try {
      final cache = await cacheDir;
      await for (final entity in cache.list(recursive: false)) {
        if (entity is File && !entity.path.contains('/$_metaDirName/') && entity.path.endsWith('.mp4')) {
          count++;
        }
      }
    } catch (e) {
      appLogger.e('[PlayCache] getCacheCount 失败', error: e);
    }
    return count;
  }

  /// 删除单个缓存
  Future<void> deleteCache(String key) async {
    try {
      final completePath = await cacheFilePath(key);
      final completeFile = File(completePath);
      if (await completeFile.exists()) {
        await completeFile.delete();
      }

      final partialPath = await partialCacheFilePath(key);
      final partialFile = File(partialPath);
      if (await partialFile.exists()) {
        await partialFile.delete();
      }

      final metaPath = await metaFilePath(key);
      final metaFile = File(metaPath);
      if (await metaFile.exists()) {
        await metaFile.delete();
      }

      invalidateCacheSize();
    } catch (e) {
      appLogger.e('[PlayCache] deleteCache 失败', error: e);
    }
  }

  // ==================== 自动缓存暂停/恢复 ====================

  /// 暂停自动缓存（退出播放页时调用）
  ///
  /// 仅对 auto 缓存且未完成的任务生效。
  Future<void> pauseAutoCache(String key) async {
    final meta = await getCacheMeta(key);
    if (meta != null && meta.cacheSource == CacheSource.auto && !meta.isComplete) {
      await saveCacheMeta(meta.copyWith(
        taskStatus: CacheTaskStatus.paused,
      ));
      appLogger.d('[PlayCache] 已暂停自动缓存: $key');
    }
  }

  /// 恢复自动缓存（进入播放页时调用）
  ///
  /// 仅对 auto 缓存且状态为 paused 的任务生效。
  Future<void> resumeAutoCache(String key) async {
    final meta = await getCacheMeta(key);
    if (meta != null &&
        meta.cacheSource == CacheSource.auto &&
        meta.taskStatus == CacheTaskStatus.paused) {
      await saveCacheMeta(meta.copyWith(
        taskStatus: CacheTaskStatus.caching,
        lastAccessedAt: DateTime.now(),
      ));
      appLogger.d('[PlayCache] 已恢复自动缓存: $key');
    }
  }

  // ==================== LRU 清理（仅自动缓存） ====================

  /// LRU 清理自动缓存（仅清理 auto 缓存，不影响 manual）
  ///
  /// 当总 auto 缓存大小超过 [maxSizeBytes] 时，
  /// 按 lastAccessedAt 从旧到新删除，直到大小低于限制。
  ///
  /// 返回清理的条目数量。
  Future<int> evictAutoCache({required int maxSizeBytes}) async {
    int evictedCount = 0;
    try {
      final autoList = await getAutoCacheList();
      if (autoList.isEmpty) return 0;

      // 计算每个 auto 缓存的物理文件大小
      final List<_CacheWithSize> cachesWithSize = [];
      int totalSize = 0;

      for (final meta in autoList) {
        final cacheFile = File(await cacheFilePath(meta.key));
        int fileSize = 0;
        if (await cacheFile.exists()) {
          fileSize = await cacheFile.length();
        }
        // 同时检查部分缓存
        if (fileSize == 0) {
          final partialFile = File(await partialCacheFilePath(meta.key));
          if (await partialFile.exists()) {
            fileSize = await partialFile.length();
          }
        }
        cachesWithSize.add(_CacheWithSize(meta: meta, size: fileSize));
        totalSize += fileSize;
      }

      // 如果总大小未超过限制，无需清理
      if (totalSize <= maxSizeBytes) {
        return 0;
      }

      // 按 lastAccessedAt 排序（旧的在前）
      cachesWithSize.sort((a, b) => a.meta.lastAccessedAt.compareTo(b.meta.lastAccessedAt));

      // 从最旧的开始删除，直到大小低于限制
      for (final cacheWithSize in cachesWithSize) {
        if (totalSize <= maxSizeBytes) break;

        // 优先删除未完成的缓存；已完成缓存仅在空间仍然超限时才清理
        if (cacheWithSize.meta.isComplete) {
          // 如果清理未完成缓存后空间已足够，跳过已完成缓存
          final remainingUnfinishedSize = cachesWithSize
              .where((c) => !c.meta.isComplete && c != cacheWithSize)
              .fold<int>(0, (sum, c) => sum + c.size);
          if (totalSize - remainingUnfinishedSize <= maxSizeBytes) continue;
        }

        await deleteCache(cacheWithSize.meta.key);
        totalSize -= cacheWithSize.size;
        evictedCount++;
        appLogger.d('[PlayCache] LRU 清理自动缓存: ${cacheWithSize.meta.key}, 大小: ${cacheWithSize.size}');
      }

      appLogger.i('[PlayCache] LRU 清理完成，共删除 $evictedCount 个自动缓存');
    } catch (e) {
      appLogger.e('[PlayCache] evictAutoCache 失败', error: e);
    }
    return evictedCount;
  }

  // ==================== 分区查询 ====================

  /// 获取自动缓存总大小
  Future<int> getAutoCacheSize() async {
    int total = 0;
    try {
      final metaDir = await this.metaDir;
      await for (final entity in metaDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          final content = await entity.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          if (json['cacheSource'] == 'auto') {
            // 获取对应缓存文件大小
            final key = json['key'] as String;
            final cacheFile = File(await cacheFilePath(key));
            int fileSize = 0;
            if (await cacheFile.exists()) {
              fileSize = await cacheFile.length();
            }
            // 同时检查部分缓存
            if (fileSize == 0) {
              final partialFile = File(await partialCacheFilePath(key));
              if (await partialFile.exists()) {
                fileSize = await partialFile.length();
              }
            }
            total += fileSize;
          }
        }
      }
    } catch (e) {
      appLogger.e('[PlayCache] getAutoCacheSize 失败', error: e);
    }
    return total;
  }

  /// 获取手动缓存总大小
  Future<int> getManualCacheSize() async {
    int total = 0;
    try {
      final metaDir = await this.metaDir;
      await for (final entity in metaDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          final content = await entity.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          if (json['cacheSource'] == 'manual') {
            final key = json['key'] as String;
            final cacheFile = File(await cacheFilePath(key));
            int fileSize = 0;
            if (await cacheFile.exists()) {
              fileSize = await cacheFile.length();
            }
            // 同时检查部分缓存
            if (fileSize == 0) {
              final partialFile = File(await partialCacheFilePath(key));
              if (await partialFile.exists()) {
                fileSize = await partialFile.length();
              }
            }
            total += fileSize;
          }
        }
      }
    } catch (e) {
      appLogger.e('[PlayCache] getManualCacheSize 失败', error: e);
    }
    return total;
  }

  /// 获取所有手动缓存列表（用于缓存管理 UI 展示）
  Future<List<CacheMeta>> getManualCacheList() async {
    final list = <CacheMeta>[];
    try {
      final metaDir = await this.metaDir;
      await for (final entity in metaDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          final content = await entity.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          if (json['cacheSource'] == 'manual') {
            list.add(CacheMeta.fromJson(json));
          }
        }
      }
    } catch (e) {
      appLogger.e('[PlayCache] getManualCacheList 失败', error: e);
    }
    // 按最后访问时间倒序（最近访问的在前）
    list.sort((a, b) => b.lastAccessedAt.compareTo(a.lastAccessedAt));
    return list;
  }

  /// 获取所有自动缓存列表
  Future<List<CacheMeta>> getAutoCacheList() async {
    final list = <CacheMeta>[];
    try {
      final metaDir = await this.metaDir;
      await for (final entity in metaDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          final content = await entity.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          if (json['cacheSource'] == 'auto') {
            list.add(CacheMeta.fromJson(json));
          }
        }
      }
    } catch (e) {
      appLogger.e('[PlayCache] getAutoCacheList 失败', error: e);
    }
    // 按最后访问时间倒序（最近访问的在前）
    list.sort((a, b) => b.lastAccessedAt.compareTo(a.lastAccessedAt));
    return list;
  }

  /// 删除手动缓存（用户主动操作）
  Future<void> deleteManualCache(String key) async {
    final meta = await getCacheMeta(key);
    if (meta != null && meta.cacheSource == CacheSource.manual) {
      await deleteCache(key);
      appLogger.d('[PlayCache] 已删除手动缓存: $key');
    }
  }

  // ==================== HLS 分片缓存支持 ====================

  /// HLS 分片缓存目录
  Future<Directory> hlsCacheDir(String cacheKey) async {
    final cache = await cacheDir;
    final hlsDir = Directory('${cache.path}/hls/$cacheKey');
    if (!await hlsDir.exists()) {
      await hlsDir.create(recursive: true);
    }
    return hlsDir;
  }

  /// HLS 分片文件路径
  Future<String> hlsSegmentPath(String cacheKey, int segIndex) async {
    final hlsDir = await hlsCacheDir(cacheKey);
    return '${hlsDir.path}/seg_$segIndex.ts';
  }

  /// 检查 HLS 分片是否存在
  Future<bool> hlsSegmentExists(String cacheKey, int segIndex) async {
    final path = await hlsSegmentPath(cacheKey, segIndex);
    return File(path).exists();
  }

  /// 删除单个 HLS 视频的所有分片缓存
  Future<void> deleteHlsCache(String cacheKey) async {
    try {
      final hlsDir = await hlsCacheDir(cacheKey);
      if (await hlsDir.exists()) {
        await hlsDir.delete(recursive: true);
        invalidateCacheSize();
        appLogger.d('[PlayCache] 已删除 HLS 缓存: $cacheKey');
      }
    } catch (e) {
      appLogger.e('[PlayCache] deleteHlsCache 失败', error: e);
    }
  }

  // ==================== 增强的过期清理 ====================

  /// 清除过期缓存（仅清理 auto 缓存，manual 缓存不受影响）
  ///
  /// 通过检查 meta.json 中的 cacheSource 字段来区分。
  Future<void> clearExpiredCache({Duration maxAge = const Duration(days: 7)}) async {
    try {
      final metaDir = await this.metaDir;
      final now = DateTime.now();

      await for (final entity in metaDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          final content = await entity.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;

          // 仅处理 auto 缓存
          if (json['cacheSource'] != 'auto') continue;

          final lastAccessed = DateTime.parse(json['lastAccessedAt'] as String);
          if (now.difference(lastAccessed) > maxAge) {
            final key = json['key'] as String;
            await deleteCache(key);
            appLogger.d('[PlayCache] 已删除过期自动缓存: $key');
          }
        }
      }
    } catch (e) {
      appLogger.e('[PlayCache] clearExpiredCache 失败', error: e);
    }
  }
}

/// 内部类：缓存条目及其文件大小
class _CacheWithSize {
  final CacheMeta meta;
  final int size;

  const _CacheWithSize({required this.meta, required this.size});
}