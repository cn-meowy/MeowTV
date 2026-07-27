import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../shared/models/resource_detail.dart';

/// Sentinel for copyWith nullable fields that need to be cleared.
const _detailUnset = Object();

/// Detail page state.
class DetailState {
  final ResourceDetailResponse? detail;
  final bool isLoading;
  final String? error;
  final bool isFavorite;
  final int selectedSourceIndex;
  final String activeDomain;

  const DetailState({
    this.detail,
    this.isLoading = false,
    this.error,
    this.isFavorite = false,
    this.selectedSourceIndex = 0,
    this.activeDomain = '',
  });

  DetailState copyWith({
    ResourceDetailResponse? detail,
    bool? isLoading,
    Object? error = _detailUnset,
    bool? isFavorite,
    int? selectedSourceIndex,
    String? activeDomain,
  }) =>
      DetailState(
        detail: detail ?? this.detail,
        isLoading: isLoading ?? this.isLoading,
        error: identical(error, _detailUnset) ? this.error : error as String?,
        isFavorite: isFavorite ?? this.isFavorite,
        selectedSourceIndex: selectedSourceIndex ?? this.selectedSourceIndex,
        activeDomain: activeDomain ?? this.activeDomain,
      );
}

class DetailNotifier extends StateNotifier<DetailState> {
  final ApiClient _api;
  DetailNotifier(this._api) : super(const DetailState());

  /// Fetch resource detail.
  Future<void> fetchDetail(String resourceDomain, int vodId) async {
    if (!mounted) return;
    state = state.copyWith(
      isLoading: true,
      error: null,
      selectedSourceIndex: 0,
      activeDomain: resourceDomain,
    );
    try {
      final resp = await _api.post<Map<String, dynamic>>(
        ApiConstants.resourceDetail,
        data: {'site': resourceDomain, 'vod_id': vodId},
      );
      if (!mounted) return;
      final body = resp.data!;
      final detail = ResourceDetailResponse.fromJson(
        (body['data'] ?? body) as Map<String, dynamic>,
      );
      state = state.copyWith(detail: detail, isLoading: false);
      // Check favorite
      await checkFavorite(resourceDomain, vodId);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Check if current resource is favorited.
  Future<void> checkFavorite(String resourceDomain, int vodId) async {
    try {
      final resp = await _api.post<Map<String, dynamic>>(
        ApiConstants.favoritesCheck,
        data: {'resource_domain': resourceDomain, 'vod_id': vodId},
      );
      if (!mounted) return;
      final body = resp.data!;
      state = state.copyWith(
        isFavorite: (body['data']?['is_favorite'] ?? body['is_favorite']) as bool? ?? false,
      );
    } catch (_) {}
  }

  /// Toggle favorite using the backend toggle endpoint.
  Future<void> toggleFavorite() async {
    final d = state.detail;
    if (d == null) return;

    try {
      final resp = await _api.post<Map<String, dynamic>>(
        ApiConstants.favoritesToggle,
        data: {
          'resource_domain': d.resourceDomain,
          'vod_id': d.vodId,
          'vod_name': d.vodName,
          'vod_pic': d.vodPic ?? '',
          'group_key': '',
        },
      );
      if (!mounted) return;
      final body = resp.data!;
      final isFav = (body['data']?['is_favorite'] ?? !state.isFavorite) as bool;
      state = state.copyWith(isFavorite: isFav);
    } catch (_) {
      if (!mounted) return;
      // Fallback: optimistic toggle
      state = state.copyWith(isFavorite: !state.isFavorite);
    }
  }

  /// Select a play source.
  void selectSource(int index) {
    state = state.copyWith(selectedSourceIndex: index);
  }
}

final detailProvider = StateNotifierProvider<DetailNotifier, DetailState>((ref) {
  final api = ref.read(apiClientProvider);
  return DetailNotifier(api);
});
