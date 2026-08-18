import 'package:shared_preferences/shared_preferences.dart';

/// 流代理缓存配置 — 持久化到 shared_preferences
class StreamCacheConfig {
  /// 最大缓存容量（MB），默认 2048 MB = 2 GB
  final int maxCacheSizeMB;

  static const _keyMaxCacheSizeMB = 'stream_cache_max_size_mb';
  // 默认 2 GB：匹配 8GB+ 设备普及现状。
  // 注意：load() 仅在 shared_preferences 无该键时使用默认值，
  // 已设置过缓存上限的老用户不受影响（不会覆盖其已保存的值）。
  static const int defaultMaxCacheSizeMB = 2048; // 2 GB
  static const int minCacheSizeMB = 1024; // 1 GB
  static const int maxCacheSizeMBLimit = 20480; // 20 GB

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
