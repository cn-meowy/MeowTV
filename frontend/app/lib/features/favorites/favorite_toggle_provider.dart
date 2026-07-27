import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import 'favorites_provider.dart';

/// Global favorite toggle state — caches favorite status by key.
/// Key format: "resourceDomain_vodId" or "db_doubanId".
class FavoriteToggleState {
  final Map<String, bool> cache;
  final bool isLoading;

  const FavoriteToggleState({this.cache = const {}, this.isLoading = false});

  FavoriteToggleState copyWith({Map<String, bool>? cache, bool? isLoading}) =>
      FavoriteToggleState(cache: cache ?? this.cache, isLoading: isLoading ?? this.isLoading);

  /// Check if a key is favorited (returns null if unknown).
  bool? isFavorite(String key) => cache[key];
}

class FavoriteToggleNotifier extends StateNotifier<FavoriteToggleState> {
  final ApiClient _api;
  final Ref _ref;

  FavoriteToggleNotifier(this._api, this._ref) : super(const FavoriteToggleState()) {
    _initFromFavorites();
  }

  /// Seed cache from favorites list.
  void _initFromFavorites() {
    final items = _ref.read(favoritesProvider).items;
    if (items.isEmpty) return;
    final newCache = Map<String, bool>.from(state.cache);
    for (final item in items) {
      final key = '${item.resourceDomain}_${item.vodId}';
      newCache[key] = true;
    }
    state = state.copyWith(cache: newCache);
  }

  /// Build cache key.
  ///
  /// [isNameGroup] — when true, prefix key with "name_" so NameGroupedCard
  /// and VideoCard use different cache entries and won't interfere with
  /// each other.
  static String buildKey({
    String? resourceDomain,
    int? vodId,
    String? doubanId,
    bool isNameGroup = false,
  }) {
    final prefix = isNameGroup ? 'name_' : '';
    if (doubanId != null) return '${prefix}db_$doubanId';
    if (resourceDomain != null && vodId != null) return '$prefix${resourceDomain}_$vodId';
    return '';
  }

  /// Check favorite status from backend and update cache.
  ///
  /// [isNameGroup] — when true, uses "name_" prefixed cache key for
  /// NameGroupedCard so it doesn't conflict with VideoCard keys.
  Future<void> checkFavorite({
    String? resourceDomain,
    int? vodId,
    String? doubanId,
    bool isNameGroup = false,
  }) async {
    final key = buildKey(
      resourceDomain: resourceDomain,
      vodId: vodId,
      doubanId: doubanId,
      isNameGroup: isNameGroup,
    );
    if (key.isEmpty) return;
    try {
      final resp = await _api.post<Map<String, dynamic>>(
        ApiConstants.favoritesCheck,
        data: {
          'resource_domain': resourceDomain,
          'vod_id': vodId,
          'douban_id': doubanId,
        },
      );
      if (!mounted) return;
      final body = resp.data!;
      final isFav = (body['data']?['is_favorite'] ?? body['is_favorite']) as bool? ?? false;
      final newCache = Map<String, bool>.from(state.cache);
      newCache[key] = isFav;
      state = state.copyWith(cache: newCache);
    } catch (_) {}
  }

  /// Toggle favorite and update cache.
  ///
  /// [isNameGroup] — when true, uses "name_" prefixed cache key for
  /// NameGroupedCard so it doesn't conflict with VideoCard keys.
  Future<void> toggleFavorite({
    required String vodName,
    String? vodPic,
    String? resourceDomain,
    String? resourceName,
    String? groupKey,
    int? vodId,
    String? doubanId,
    bool isNameGroup = false,
  }) async {
    final key = buildKey(resourceDomain: resourceDomain, vodId: vodId, doubanId: doubanId, isNameGroup: isNameGroup);
    if (key.isEmpty) return;

    // Optimistic update
    final currentFav = state.cache[key] ?? false;
    final newCache = Map<String, bool>.from(state.cache);
    newCache[key] = !currentFav;
    state = state.copyWith(cache: newCache);

    try {
      final resp = await _api.post<Map<String, dynamic>>(
        ApiConstants.favoritesToggle,
        data: {
          'resource_domain': resourceDomain,
          'vod_id': vodId,
          'vod_name': vodName,
          'vod_pic': vodPic,
          'douban_id': doubanId,
          'resource_name': resourceName,
          'group_key': groupKey,
        },
      );
      if (!mounted) return;
      final body = resp.data!;
      final isFav = (body['data']?['is_favorite'] ?? !currentFav) as bool;
      final updatedCache = Map<String, bool>.from(state.cache);
      updatedCache[key] = isFav;
      state = state.copyWith(cache: updatedCache);

      // Refresh favorites list so favorites page stays in sync
      _ref.read(favoritesProvider.notifier).loadFavorites();
    } catch (_) {
      if (!mounted) return;
      // Revert on error
      final revertCache = Map<String, bool>.from(state.cache);
      revertCache[key] = currentFav;
      state = state.copyWith(cache: revertCache);
    }
  }
}

final favoriteToggleProvider =
    StateNotifierProvider<FavoriteToggleNotifier, FavoriteToggleState>((ref) {
  final api = ref.read(apiClientProvider);
  return FavoriteToggleNotifier(api, ref);
});
