import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger/app_logger.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../shared/models/user_data.dart';

class HistoryState {
  final List<PlayHistoryItem> items;
  final int total;
  final bool isLoading;
  final String? error;

  const HistoryState({this.items = const [], this.total = 0, this.isLoading = false, this.error});

  HistoryState copyWith({List<PlayHistoryItem>? items, int? total, bool? isLoading, String? error}) =>
      HistoryState(items: items ?? this.items, total: total ?? this.total, isLoading: isLoading ?? this.isLoading, error: error);
}

class HistoryNotifier extends StateNotifier<HistoryState> {
  final ApiClient _api;
  HistoryNotifier(this._api) : super(const HistoryState());

  Future<void> loadHistory({int limit = 50, int offset = 0}) async {
    if (!mounted) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _api.post<Map<String, dynamic>>(ApiConstants.playHistoryList, data: {
        'limit': limit,
        'offset': offset,
      });
      final body = resp.data!;
      final data = body['data'] ?? body;
      final listResp = PlayHistoryListResponse.fromJson(data as Map<String, dynamic>);
      if (!mounted) return;
      state = state.copyWith(items: listResp.items, total: listResp.total, isLoading: false);
    } catch (e, st) {
      appLogger.e('加载播放历史失败', error: e, stackTrace: st);
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> deleteItem(int id) async {
    try {
      await _api.post(ApiConstants.playHistoryDelete, data: {'id': id});
      if (!mounted) return;
      state = state.copyWith(items: state.items.where((i) => i.id != id).toList(), total: state.total - 1);
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    try {
      await _api.post(ApiConstants.playHistoryClear);
      if (!mounted) return;
      state = state.copyWith(items: [], total: 0);
    } catch (_) {}
  }

  /// Report play progress (called every 30s during playback).
  Future<void> reportProgress({
    required int vodId,
    required String vodName,
    required String vodPic,
    required String resourceDomain,
    required String resourceName,
    required String groupKey,
    required int sourceIndex,
    required int epIndex,
    required String epName,
    required double progress,
    required int currentTime,
    required int duration,
  }) async {
    try {
      await _api.post(ApiConstants.playHistoryProgress, data: {
        'vod_id': vodId,
        'vod_name': vodName,
        'vod_pic': vodPic,
        'resource_domain': resourceDomain,
        'resource_name': resourceName,
        'group_key': groupKey,
        'source_index': sourceIndex,
        'ep_index': epIndex,
        'ep_name': epName,
        'progress': progress,
        'current_time': currentTime,
        'duration': duration,
      });
    } catch (_) {}
  }

  /// Upsert play history (called when starting playback).
  Future<void> upsertHistory({
    required int vodId,
    required String vodName,
    required String vodPic,
    required String resourceDomain,
    required String resourceName,
    required String groupKey,
    required int sourceIndex,
    required int epIndex,
    required String epName,
  }) async {
    try {
      await _api.post(ApiConstants.playHistoryUpsert, data: {
        'vod_id': vodId,
        'vod_name': vodName,
        'vod_pic': vodPic,
        'resource_domain': resourceDomain,
        'resource_name': resourceName,
        'group_key': groupKey,
        'source_index': sourceIndex,
        'ep_index': epIndex,
        'ep_name': epName,
      });
    } catch (_) {}
  }

  /// 获取单条播放记录（用于播放前续播）。
  /// 记录不存在时返回 null（后端返回 data: null）。
  /// 请求失败时静默返回 null，保证续播失败不影响正常播放。
  Future<PlayHistoryItem?> getPlayHistory({
    required int vodId,
    required String resourceDomain,
    required int epIndex,
  }) async {
    try {
      final resp = await _api.post<Map<String, dynamic>>(
        ApiConstants.playHistoryGet,
        data: {
          'vod_id': vodId,
          'resource_domain': resourceDomain,
          'ep_index': epIndex,
        },
      );
      final body = resp.data!;
      final data = body['data'];
      if (data == null) return null;
      return PlayHistoryItem.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      appLogger.w('获取播放历史失败，将从开头播放', error: e);
      return null;
    }
  }
}

final historyProvider = StateNotifierProvider<HistoryNotifier, HistoryState>((ref) {
  final api = ref.read(apiClientProvider);
  return HistoryNotifier(api);
});
