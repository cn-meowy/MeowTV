import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../shared/models/download.dart';
import '../../shared/models/enums.dart';
import '../settings/douban_image_proxy_provider.dart';

class DownloadState {
  final List<DownloadTaskItem> items;
  final int total;
  final bool isLoading;
  final String? error;
  final DownloadStatus? filterStatus;

  const DownloadState({this.items = const [], this.total = 0, this.isLoading = false, this.error, this.filterStatus});

  DownloadState copyWith({List<DownloadTaskItem>? items, int? total, bool? isLoading, String? error, DownloadStatus? filterStatus}) =>
      DownloadState(items: items ?? this.items, total: total ?? this.total, isLoading: isLoading ?? this.isLoading, error: error, filterStatus: filterStatus ?? this.filterStatus);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadState &&
          _listEquals(items, other.items) &&
          total == other.total &&
          isLoading == other.isLoading &&
          error == other.error &&
          filterStatus == other.filterStatus;

  @override
  int get hashCode => Object.hash(items, total, isLoading, error, filterStatus);

  static bool _listEquals(List<DownloadTaskItem> a, List<DownloadTaskItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class DownloadNotifier extends StateNotifier<DownloadState> {
  final ApiClient _api;
  /// 获取临时 Token 的回调，用于构建 `download/file/:id?token=...` URL。
  ///
  /// 后端 `/api/download/file/:id` 路由使用 `TempTokenAuth` 中间件，
  /// 只接受临时 Token（query param `token`），不接受 JWT。
  /// iOS AVPlayer 通过 `video.src` 加载，无法注入 Authorization header，
  /// 因此必须使用临时 Token 而非 JWT。
  final Future<String> Function()? _tempTokenProvider;
  Timer? _pollTimer;
  /// 追踪上一次请求的 filterStatus，避免竞态条件覆盖新 filter 的结果。
  int? _pendingFilterIndex;

  DownloadNotifier(this._api, {Future<String> Function()? tempTokenProvider})
      : _tempTokenProvider = tempTokenProvider,
        super(const DownloadState());

  /// Load download list with loading state (for initial load and filter switch).
  Future<void> loadDownloads({DownloadStatus? status}) async {
    if (!mounted) return;
    _pendingFilterIndex = status?.index;
    state = state.copyWith(isLoading: true, error: null, filterStatus: status);
    try {
      final resp = await _api.post<Map<String, dynamic>>(ApiConstants.downloadList, data: {
        if (status != null) 'status': status.index,
        'limit': 100,
        'offset': 0,
      });
      if (!mounted) return;
      // 竞态保护：只有当返回的 filter 与当前请求的一致时才更新
      if (_pendingFilterIndex != status?.index) return;
      final body = resp.data!;
      final data = body['data'] ?? body;
      final listResp = DownloadListResponse.fromJson(data as Map<String, dynamic>);
      if (!mounted) return;
      if (_pendingFilterIndex != status?.index) return;
      state = state.copyWith(items: listResp.items, total: listResp.total, isLoading: false);
      // filter 切换后重启轮询，确保使用正确的间隔
      restartPolling();
    } catch (e) {
      if (!mounted) return;
      if (_pendingFilterIndex != status?.index) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Silent refresh without loading state (for polling and post-action refresh).
  /// Uses diff comparison to avoid triggering rebuilds when data hasn't actually changed.
  Future<void> silentRefresh() async {
    if (!mounted) return;
    try {
      final resp = await _api.post<Map<String, dynamic>>(ApiConstants.downloadList, data: {
        if (state.filterStatus != null) 'status': state.filterStatus!.index,
        'limit': 100,
        'offset': 0,
      });
      if (!mounted) return;
      final body = resp.data!;
      final data = body['data'] ?? body;
      final listResp = DownloadListResponse.fromJson(data as Map<String, dynamic>);
      if (!mounted) return;

      // Diff comparison: skip state update if nothing actually changed
      final newItems = listResp.items;
      final oldItems = state.items;

      if (newItems.length == oldItems.length) {
        bool hasChange = false;
        for (int i = 0; i < newItems.length; i++) {
          if (newItems[i] != oldItems[i]) {
            hasChange = true;
            break;
          }
        }
        if (!hasChange && listResp.total == state.total) {
          return; // No actual change, skip state update to avoid rebuild
        }
      }

      state = state.copyWith(items: newItems, total: listResp.total);
    } catch (_) {
      // Silent: ignore errors during background refresh
    }
  }

  /// 根据当前 filter 状态返回合适的轮询间隔。
  /// 下载中/排队中: 1 秒（需要快速更新进度）
  /// 其它状态: 5 秒（静态数据无需频繁刷新）
  Duration _getPollInterval() {
    switch (state.filterStatus) {
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
      case DownloadStatus.parsing:
      case DownloadStatus.merging:
        return const Duration(seconds: 1);
      case DownloadStatus.completed:
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
      case null: // 全部
        return const Duration(seconds: 5);
    }
  }

  /// 启动轮询，自动根据 filter 调整间隔。
  void startPolling() {
    if (_pollTimer?.isActive == true) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_getPollInterval(), (_) {
      if (!mounted) {
        _pollTimer?.cancel();
        _pollTimer = null;
        return;
      }
      silentRefresh();
    });
  }

  /// 重启轮询（filter 切换后调用）。
  void restartPolling() {
    stopPolling();
    startPolling();
  }

  /// Stop polling.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> cancelTask(int id) async {
    try {
      await _api.post(ApiConstants.downloadCancel, data: {'task_id': id});
      if (!mounted) return;
      await silentRefresh();
    } catch (_) {}
  }

  Future<void> deleteTask(int id) async {
    try {
      await _api.post(ApiConstants.downloadDelete, data: {'task_id': id});
      if (!mounted) return;
      await silentRefresh();
    } catch (_) {}
  }

  Future<void> retryTask(int id) async {
    try {
      await _api.post(ApiConstants.downloadRetry, data: {'task_id': id});
      if (!mounted) return;
      await silentRefresh();
    } catch (_) {}
  }

  /// Check if a local download exists.
  Future<DownloadCheckResponse?> checkDownload({
    required String resourceDomain,
    required int vodId,
    required int sourceIndex,
    required int epIndex,
  }) async {
    try {
      final resp = await _api.post<Map<String, dynamic>>(ApiConstants.downloadCheck, data: {
        'resource_domain': resourceDomain,
        'vod_id': vodId,
        'source_index': sourceIndex,
        'ep_index': epIndex,
      });
      final body = resp.data!;
      return DownloadCheckResponse.fromJson((body['data'] ?? body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 构建已下载文件的播放 URL，附加临时 Token 用于认证。
  ///
  /// 后端 `/api/download/file/:id` 路由使用 `TempTokenAuth` 中间件，
  /// 只接受临时 Token（query param `token`），不接受 JWT。
  /// iOS AVPlayer 通过 `video.src` 加载，无法注入 Authorization header，
  /// 因此必须使用临时 Token。若临时 Token 不可用则抛出 [StateError]，
  /// 由调用方（如 PlayerScreen）捕获并回退到远程播放。
  ///
  /// 生成形如 `{baseUrl}/api/download/file/{taskId}?token={tempToken}` 的 URL，
  /// 供 video_player / Chewie 直接打开服务器流式播放。
  Future<String> getDownloadFileUrl(int taskId) async {
    final baseUrl = _api.baseUrl;
    final tempToken = _tempTokenProvider != null ? await _tempTokenProvider() : '';
    if (tempToken.isEmpty) {
      throw StateError('temp_token_unavailable');
    }
    return '$baseUrl${ApiConstants.downloadFile}/$taskId?token=${Uri.encodeComponent(tempToken)}';
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    super.dispose();
  }
}

final downloadProvider = StateNotifierProvider<DownloadNotifier, DownloadState>((ref) {
  final api = ref.read(apiClientProvider);
  // 传入临时 Token 获取回调，供 getDownloadFileUrl 构建带 token 的播放 URL。
  // 后端 download/file 路由只接受临时 Token，不接受 JWT。
  final notifier = DownloadNotifier(
    api,
    tempTokenProvider: () => ref.read(doubanImageProxyProvider.notifier).getCachedToken(),
  );

  // 当没有任何 Widget watch 此 provider 时，自动停止轮询，
  // 避免在 Element 已 defunct 后仍通过 state= 触发通知导致崩溃。
  ref.onCancel(() {
    notifier.stopPolling();
  });

  // 当有 Widget 重新 watch 此 provider 时，自动恢复轮询并静默刷新数据。
  // 使用 restartPolling 确保轮询间隔根据当前 filter 正确调整。
  ref.onResume(() {
    notifier.restartPolling();
    notifier.silentRefresh();
  });

  return notifier;
});
