import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logger/app_logger.dart';
import '../../core/network/m3u8_client_checker.dart';
import '../../shared/models/m3u8_check_result.dart';

/// M3u8 check state
class M3u8CheckState {
  /// URL -> 检测状态映射
  final Map<String, UrlCheckStatus> statusMap;

  /// URL -> 错误信息映射（仅不可用时）
  final Map<String, String> errorMap;

  /// 是否正在检测中
  final bool checking;

  const M3u8CheckState({
    this.statusMap = const {},
    this.errorMap = const {},
    this.checking = false,
  });

  M3u8CheckState copyWith({
    Map<String, UrlCheckStatus>? statusMap,
    Map<String, String>? errorMap,
    bool? checking,
  }) {
    return M3u8CheckState(
      statusMap: statusMap ?? this.statusMap,
      errorMap: errorMap ?? this.errorMap,
      checking: checking ?? this.checking,
    );
  }
}

/// SharedPreferences cache key prefix
const _kCachePrefix = 'meowtv_m3u8_check:';
/// Cache TTL: 30 minutes
const _kCacheTtlMs = 30 * 60 * 1000;

String _cacheKey(String url) {
  // Simple hash for cache key
  var hash = 0;
  for (var i = 0; i < url.length; i++) {
    final char = url.codeUnitAt(i);
    hash = (hash << 5) - hash + char;
    hash = hash & hash;
  }
  return '$_kCachePrefix${hash.abs()}';
}

class M3u8CheckNotifier extends StateNotifier<M3u8CheckState> {
  final M3u8ClientChecker _clientChecker;
  int _seq = 0;

  M3u8CheckNotifier() : _clientChecker = M3u8ClientChecker(), super(const M3u8CheckState());

  /// 获取 URL 的缓存状态
  Future<_CachedResult?> _readCache(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(url));
      if (raw == null) return null;

      final data = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = data['cachedAt'] as int;
      if (DateTime.now().millisecondsSinceEpoch - cachedAt > _kCacheTtlMs) {
        await prefs.remove(_cacheKey(url));
        return null;
      }

      return _CachedResult(
        status: UrlCheckStatus.values.firstWhere(
          (e) => e.name == data['status'],
          orElse: () => UrlCheckStatus.unchecked,
        ),
        error: data['error'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// 写入缓存
  Future<void> _writeCache(String url, UrlCheckStatus status, String? error) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey(url), jsonEncode({
        'status': status.name,
        'error': error,
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {
      // SharedPreferences full or unavailable, ignore silently
    }
  }

  /// 批量检测 m3u8 链接（使用客户端本地检测）
  ///
  /// [urls] 要检测的 URL 列表
  /// 分批检测，每批最多 20 个
  Future<void> checkUrls(List<String> urls) async {
    if (urls.isEmpty) {
      appLogger.w('[M3u8Check] checkUrls called with empty list, skipping');
      return;
    }

    appLogger.i('[M3u8Check] checkUrls called with ${urls.length} URLs: ${urls.take(3).join(", ")}...');

    final seq = ++_seq;

    // 过滤出需要检测的 URL（从缓存中读取）
    final toCheck = <String>[];
    final cachedResults = <String, _CachedResult>{};

    for (final url in urls) {
      final cached = await _readCache(url);
      if (cached != null) {
        cachedResults[url] = cached;
      } else {
        toCheck.add(url);
      }
    }

    appLogger.i('[M3u8Check] ${cachedResults.length} cached, ${toCheck.length} to check');

    // 立即更新已缓存的状态
    if (cachedResults.isNotEmpty) {
      state = state.copyWith(
        statusMap: Map.from(state.statusMap)
          ..addEntries(cachedResults.entries.map((e) => MapEntry(e.key, e.value.status))),
        errorMap: Map.from(state.errorMap)
          ..addEntries(cachedResults.entries
              .where((e) => e.value.status == UrlCheckStatus.unavailable && e.value.error != null)
              .map((e) => MapEntry(e.key, e.value.error!))),
      );
    }

    if (toCheck.isEmpty) {
      appLogger.i('[M3u8Check] all URLs cached, skipping check');
      return;
    }

    // 分批检测，每批最多 20 个（客户端并发控制为 5）
    const batchSize = 20;
    final batches = <List<String>>[];
    for (var i = 0; i < toCheck.length; i += batchSize) {
      batches.add(toCheck.sublist(i, i + batchSize > toCheck.length ? toCheck.length : i + batchSize));
    }

    appLogger.i('[M3u8Check] starting check with ${batches.length} batches');

    // 标记为检测中
    state = state.copyWith(
      checking: true,
      statusMap: Map.from(state.statusMap)
        ..addEntries(toCheck.map((url) => MapEntry(url, UrlCheckStatus.checking))),
    );

    try {
      // 使用客户端检测（并发 5）
      final allResults = await Future.wait(
        batches.map((batch) => _clientChecker.checkUrls(batch, concurrency: 5)),
      );

      if (seq != _seq) return; // 序列号已过期，跳过

      final newStatusMap = <String, UrlCheckStatus>{};
      final newErrorMap = <String, String>{};

      for (final results in allResults) {
        for (final result in results) {
          final status = result.available ? UrlCheckStatus.available : UrlCheckStatus.unavailable;
          newStatusMap[result.url] = status;
          if (!result.available && result.error.isNotEmpty) {
            newErrorMap[result.url] = result.error;
          }
          // 写入缓存
          await _writeCache(result.url, status, result.error.isNotEmpty ? result.error : null);
        }
      }

      appLogger.i('[M3u8Check] check complete: ${newStatusMap.values.where((s) => s == UrlCheckStatus.available).length} available, ${newStatusMap.values.where((s) => s == UrlCheckStatus.unavailable).length} unavailable');

      state = state.copyWith(
        statusMap: Map.from(state.statusMap)..addEntries(newStatusMap.entries),
        errorMap: Map.from(state.errorMap)..addEntries(newErrorMap.entries),
        checking: false,
      );
    } catch (e) {
      appLogger.e('[M3u8Check] check failed', error: e);
      if (seq != _seq) return;
      // 检测失败的 URL 标记为 unchecked（下次会重新检测）
      state = state.copyWith(
        checking: false,
        statusMap: Map.from(state.statusMap)
          ..removeWhere((url, status) => status == UrlCheckStatus.checking),
      );
    }
  }

  /// 检测单个 URL（使用客户端本地检测，返回 Promise）
  Future<M3u8CheckResult> checkSingle(String url) async {
    // 先检查缓存
    final cached = await _readCache(url);
    if (cached != null) {
      final result = M3u8CheckResult(
        url: url,
        available: cached.status == UrlCheckStatus.available,
        statusCode: cached.status == UrlCheckStatus.available ? 200 : 0,
        error: cached.error ?? '',
      );
      state = state.copyWith(
        statusMap: Map.from(state.statusMap)..[url] = cached.status,
        errorMap: cached.status == UrlCheckStatus.unavailable && cached.error != null
            ? (Map.from(state.errorMap)..[url] = cached.error!)
            : state.errorMap,
      );
      return result;
    }

    state = state.copyWith(
      statusMap: Map.from(state.statusMap)..[url] = UrlCheckStatus.checking,
    );

    try {
      // 使用客户端检测
      final result = await _clientChecker.checkUrl(url);

      final status = result.available ? UrlCheckStatus.available : UrlCheckStatus.unavailable;
      state = state.copyWith(
        statusMap: Map.from(state.statusMap)..[url] = status,
        errorMap: !result.available && result.error.isNotEmpty
            ? (Map.from(state.errorMap)..[url] = result.error)
            : state.errorMap,
      );
      await _writeCache(url, status, result.error.isNotEmpty ? result.error : null);

      return result;
    } catch (e) {
      state = state.copyWith(
        statusMap: Map.from(state.statusMap)..[url] = UrlCheckStatus.unchecked,
      );
      return M3u8CheckResult(url: url, available: false, statusCode: 0, error: e.toString());
    }
  }

  /// 获取 URL 的检测状态
  UrlCheckStatus getStatus(String url) {
    return state.statusMap[url] ?? UrlCheckStatus.unchecked;
  }

  /// 获取 URL 的错误信息
  String? getError(String url) {
    return state.errorMap[url];
  }
}

class _CachedResult {
  final UrlCheckStatus status;
  final String? error;
  const _CachedResult({required this.status, this.error});
}

/// Provider for M3u8CheckNotifier
final m3u8CheckProvider = StateNotifierProvider<M3u8CheckNotifier, M3u8CheckState>((ref) {
  return M3u8CheckNotifier();
});

/// Helper extension to get URL status from provider
extension M3u8CheckStateX on M3u8CheckState {
  UrlCheckStatus statusOf(String url) => statusMap[url] ?? UrlCheckStatus.unchecked;
  String? errorOf(String url) => errorMap[url];
}
