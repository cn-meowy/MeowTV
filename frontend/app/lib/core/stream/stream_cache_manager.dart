import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../logger/app_logger.dart';
import 'stream_cache_config.dart';

/// 流代理缓存条目信息
class StreamCacheEntry {
  final String cacheKey;
  final String path;
  final int sizeBytes;
  final DateTime lastModified;

  const StreamCacheEntry({
    required this.cacheKey,
    required this.path,
    required this.sizeBytes,
    required this.lastModified,
  });
}

/// 流代理缓存管理服务
///
/// 负责：
/// - 计算 play_cache/stream/ 目录总大小
/// - 列出所有 session 缓存条目
/// - 缓存到达上限时自动清理最早的 session
/// - 手工清理所有流代理缓存
class StreamCacheManager {
  StreamCacheManager._();
  static final StreamCacheManager instance = StreamCacheManager._();

  /// 获取流代理缓存根目录
  Future<Directory> get streamCacheDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/play_cache/stream');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 计算流代理缓存总大小（字节）
  Future<int> getTotalCacheSize() async {
    final dir = await streamCacheDir;
    if (!await dir.exists()) return 0;

    var totalSize = 0;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
          } catch (_) {}
        }
      }
    } catch (e) {
      appLogger.e('[StreamCacheManager] 计算缓存大小失败', error: e);
    }
    return totalSize;
  }

  /// 列出所有 session 缓存条目（每个 cacheKey 对应一个子目录）
  Future<List<StreamCacheEntry>> getCacheEntries() async {
    final dir = await streamCacheDir;
    if (!await dir.exists()) return [];

    final entries = <StreamCacheEntry>[];
    try {
      await for (final entity in dir.list(recursive: false)) {
        if (entity is Directory) {
          final cacheKey = entity.path.split('/').last;
          var sizeBytes = 0;
          DateTime? lastModified;

          await for (final file in entity.list(recursive: true)) {
            if (file is File) {
              try {
                sizeBytes += await file.length();
                final stat = await file.stat();
                if (lastModified == null || stat.modified.isAfter(lastModified)) {
                  lastModified = stat.modified;
                }
              } catch (_) {}
            }
          }

          if (sizeBytes > 0) {
            entries.add(StreamCacheEntry(
              cacheKey: cacheKey,
              path: entity.path,
              sizeBytes: sizeBytes,
              lastModified: lastModified ?? DateTime.now(),
            ));
          }
        }
      }
    } catch (e) {
      appLogger.e('[StreamCacheManager] 列出缓存条目失败', error: e);
    }

    // 按最后修改时间排序（最早的在前）
    entries.sort((a, b) => a.lastModified.compareTo(b.lastModified));
    return entries;
  }

  /// 自动清理：如果缓存超过上限，删除最早的 session 缓存直到低于上限
  /// 返回被清理的条目数量
  Future<int> autoEvictIfNeeded() async {
    final config = await StreamCacheConfig.load();
    final maxSizeBytes = config.maxCacheSizeBytes;
    final currentSize = await getTotalCacheSize();

    if (currentSize <= maxSizeBytes) return 0;

    appLogger.i('[StreamCacheManager] 缓存超限: current=${_formatSize(currentSize)}, max=${_formatSize(maxSizeBytes)}，开始自动清理');

    final entries = await getCacheEntries();
    var evicted = 0;
    var freedSize = 0;

    for (final entry in entries) {
      if (currentSize - freedSize <= maxSizeBytes) break;

      try {
        final dir = Directory(entry.path);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          freedSize += entry.sizeBytes;
          evicted++;
          appLogger.d('[StreamCacheManager] 自动清理: key=${entry.cacheKey}, size=${_formatSize(entry.sizeBytes)}');
        }
      } catch (e) {
        appLogger.e('[StreamCacheManager] 自动清理失败: key=${entry.cacheKey}', error: e);
      }
    }

    if (evicted > 0) {
      appLogger.i('[StreamCacheManager] 自动清理完成: evicted=$evicted, freed=${_formatSize(freedSize)}');
    }
    return evicted;
  }

  /// 手工清理：删除所有流代理缓存
  /// 同时清理 VideoCacheProxyServer 中的 session
  Future<void> clearAllCache() async {
    final dir = await streamCacheDir;
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
        appLogger.i('[StreamCacheManager] 已清除所有流代理缓存');
      } catch (e) {
        appLogger.e('[StreamCacheManager] 清除缓存失败', error: e);
      }
    }
  }

  /// 删除单个 session 缓存
  Future<bool> deleteSessionCache(String cacheKey) async {
    final dir = await streamCacheDir;
    final sessionDir = Directory('${dir.path}/$cacheKey');
    if (await sessionDir.exists()) {
      try {
        await sessionDir.delete(recursive: true);
        appLogger.i('[StreamCacheManager] 已删除 session 缓存: $cacheKey');
        return true;
      } catch (e) {
        appLogger.e('[StreamCacheManager] 删除 session 缓存失败: $cacheKey', error: e);
        return false;
      }
    }
    return false;
  }

  /// 格式化文件大小
  static String formatSize(int bytes) => _formatSize(bytes);
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
