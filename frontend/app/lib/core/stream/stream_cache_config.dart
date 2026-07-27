import 'package:shared_preferences/shared_preferences.dart';

/// 流代理缓存配置 — 持久化到 shared_preferences
class StreamCacheConfig {
  /// 最大缓存容量（MB），默认 1024 MB = 1 GB
  final int maxCacheSizeMB;

  static const _keyMaxCacheSizeMB = 'stream_cache_max_size_mb';
  static const int defaultMaxCacheSizeMB = 1024; // 1 GB
  static const int minCacheSizeMB = 512; // 0.5 GB
  static const int maxCacheSizeMBLimit = 10240; // 10 GB

  const StreamCacheConfig({
    this.maxCacheSizeMB = defaultMaxCacheSizeMB,
  });

  /// 从 shared_preferences 加载
  static Future<StreamCacheConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final maxMB = prefs.getInt(_keyMaxCacheSizeMB) ?? defaultMaxCacheSizeMB;
    return StreamCacheConfig(maxCacheSizeMB: maxMB);
  }

  /// 保存最大缓存容量
  Future<void> saveMaxCacheSizeMB(int mb) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMaxCacheSizeMB, mb);
  }

  /// 最大缓存容量（字节）
  int get maxCacheSizeBytes => maxCacheSizeMB * 1024 * 1024;
}
