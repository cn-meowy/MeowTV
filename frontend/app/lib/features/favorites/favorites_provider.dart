import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../shared/models/user_data.dart';

class FavoritesState {
  final List<FavoriteItem> items;
  final int total;
  final bool isLoading;
  final String? error;

  const FavoritesState({this.items = const [], this.total = 0, this.isLoading = false, this.error});

  FavoritesState copyWith({List<FavoriteItem>? items, int? total, bool? isLoading, String? error}) =>
      FavoritesState(items: items ?? this.items, total: total ?? this.total, isLoading: isLoading ?? this.isLoading, error: error);
}

class FavoritesNotifier extends StateNotifier<FavoritesState> {
  final ApiClient _api;
  FavoritesNotifier(this._api) : super(const FavoritesState());

  Future<void> loadFavorites({int limit = 50, int offset = 0, String? keyword}) async {
    if (!mounted) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _api.post<Map<String, dynamic>>(ApiConstants.favoritesList, data: {
        'limit': limit,
        'offset': offset,
        'keyword': ?keyword,
      });
      final body = resp.data!;
      final data = body['data'] ?? body;
      final listResp = FavoriteListResponse.fromJson(data as Map<String, dynamic>);
      if (!mounted) return;
      state = state.copyWith(items: listResp.items, total: listResp.total, isLoading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> removeFavorite(FavoriteItem item) async {
    try {
      await _api.post(ApiConstants.favoritesRemove, data: {
        'vod_id': item.vodId,
        'resource_domain': item.resourceDomain,
      });
      if (!mounted) return;
      state = state.copyWith(items: state.items.where((i) => i.id != item.id).toList(), total: state.total - 1);
    } catch (_) {}
  }

  Future<void> clearFavorites() async {
    try {
      await _api.post(ApiConstants.favoritesClear);
      if (!mounted) return;
      state = state.copyWith(items: [], total: 0);
    } catch (_) {}
  }
}

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, FavoritesState>((ref) {
  final api = ref.read(apiClientProvider);
  return FavoritesNotifier(api);
});
