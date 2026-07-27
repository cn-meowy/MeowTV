import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/logger/app_logger.dart';
import '../../shared/models/douban.dart';
import '../settings/douban_image_proxy_provider.dart';

/// Sentinel for copyWith nullable fields that need to be cleared.
const _homeUnset = Object();

/// Home page state.
class HomeState {
  final List<DoubanSubject> bannerSubjects;
  final List<DoubanSubject> hotMovies;
  final List<DoubanSubject> hotTvSeries;
  final List<String> tags;
  final String currentTag;
  final bool isLoading;
  final String? error;

  const HomeState({
    this.bannerSubjects = const [],
    this.hotMovies = const [],
    this.hotTvSeries = const [],
    this.tags = const [],
    this.currentTag = '热门',
    this.isLoading = false,
    this.error,
  });

  HomeState copyWith({
    List<DoubanSubject>? bannerSubjects,
    List<DoubanSubject>? hotMovies,
    List<DoubanSubject>? hotTvSeries,
    List<String>? tags,
    String? currentTag,
    bool? isLoading,
    Object? error = _homeUnset,
  }) =>
      HomeState(
        bannerSubjects: bannerSubjects ?? this.bannerSubjects,
        hotMovies: hotMovies ?? this.hotMovies,
        hotTvSeries: hotTvSeries ?? this.hotTvSeries,
        tags: tags ?? this.tags,
        currentTag: currentTag ?? this.currentTag,
        isLoading: isLoading ?? this.isLoading,
        error: identical(error, _homeUnset) ? this.error : error as String?,
      );
}

class HomeNotifier extends StateNotifier<HomeState> {
  final ApiClient _api;
  final Ref _ref;
  HomeNotifier(this._api, this._ref) : super(const HomeState());

  /// Guard against concurrent loads.
  bool _isLoadingData = false;

  Future<void> loadData({String tag = '热门'}) async {
    if (!mounted || _isLoadingData) return;
    _isLoadingData = true;
    state = state.copyWith(isLoading: true, error: null, currentTag: tag);

    // 初始化图片代理（加载模式 + 确保 token 就绪）- 失败不应阻塞数据获取。
    // 必须在获取 subjects 之前完成，否则 buildImageUrl 会因 token 为空
    // 静默回退到原始豆瓣 URL，导致后端代理请求不发起。
    try {
      final proxyNotifier = _ref.read(doubanImageProxyProvider.notifier);
      await proxyNotifier.init();
    } catch (e) {
      appLogger.w('Failed to init image proxy, continuing: $e');
    }

    // Fetch each data source independently so that a single failure
    // does not discard the results of the other two.
    List<DoubanSubject> movies = [];
    List<DoubanSubject> tvSeries = [];
    List<String> tags = [];
    String? firstError;

    // Movie subjects
    try {
      final resp = await _api.post<Map<String, dynamic>>(
        ApiConstants.doubanSubjects,
        data: {'type': 'movie', 'tag': tag, 'page_start': 0, 'page_limit': 10},
      );
      final data = resp.data?['data'] ?? resp.data;
      movies = (data['subjects'] as List<dynamic>?)
              ?.map((e) => DoubanSubject.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
    } catch (e) {
      appLogger.w('Failed to load movie subjects: $e');
      firstError ??= e.toString();
    }

    // TV subjects
    try {
      final resp = await _api.post<Map<String, dynamic>>(
        ApiConstants.doubanSubjects,
        data: {'type': 'tv', 'tag': '热门', 'page_start': 0, 'page_limit': 20},
      );
      final data = resp.data?['data'] ?? resp.data;
      tvSeries = (data['subjects'] as List<dynamic>?)
              ?.map((e) => DoubanSubject.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
    } catch (e) {
      appLogger.w('Failed to load TV subjects: $e');
      firstError ??= e.toString();
    }

    // Tags
    try {
      final resp = await _api.post<Map<String, dynamic>>(
        ApiConstants.doubanTags,
        data: {'type': 'movie'},
      );
      tags = (resp.data?['data']?['tags'] as List<dynamic>?)?.cast<String>() ?? [];
    } catch (e) {
      appLogger.w('Failed to load tags: $e');
      firstError ??= e.toString();
    }

    if (!mounted) {
      _isLoadingData = false;
      return;
    }

    state = state.copyWith(
      bannerSubjects: movies.take(5).toList(),
      hotMovies: movies,
      hotTvSeries: tvSeries,
      tags: tags,
      isLoading: false,
      error: firstError,
    );
    _isLoadingData = false;
  }
}

final homeProvider = StateNotifierProvider<HomeNotifier, HomeState>((ref) {
  // Use ref.read instead of ref.watch — ApiClient is a singleton Provider
  // that never rebuilds; using ref.watch would cause this StateNotifier
  // to be disposed & recreated whenever the dependency graph is re-evaluated,
  // resetting state and triggering an infinite data-reload loop.
  final api = ref.read(apiClientProvider);
  return HomeNotifier(api, ref);
});
