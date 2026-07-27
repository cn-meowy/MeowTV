import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../shared/models/douban.dart';

class DoubanState {
  final List<DoubanSubject> subjects;
  final List<String> movieTags;
  final List<String> tvTags;
  final bool isLoading;
  final String? error;

  const DoubanState({
    this.subjects = const [],
    this.movieTags = const [],
    this.tvTags = const [],
    this.isLoading = false,
    this.error,
  });

  DoubanState copyWith({
    List<DoubanSubject>? subjects,
    List<String>? movieTags,
    List<String>? tvTags,
    bool? isLoading,
    String? error,
  }) =>
      DoubanState(
        subjects: subjects ?? this.subjects,
        movieTags: movieTags ?? this.movieTags,
        tvTags: tvTags ?? this.tvTags,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class DoubanNotifier extends StateNotifier<DoubanState> {
  final ApiClient _api;
  DoubanNotifier(this._api) : super(const DoubanState());

  Future<void> loadTags() async {
    try {
      final results = await Future.wait([
        _api.post<Map<String, dynamic>>(ApiConstants.doubanTags, data: {'type': 'movie'}),
        _api.post<Map<String, dynamic>>(ApiConstants.doubanTags, data: {'type': 'tv'}),
      ]);
      if (!mounted) return;
      final movieData = results[0].data!;
      final tvData = results[1].data!;
      state = state.copyWith(
        movieTags: (movieData['data']?['tags'] as List<dynamic>?)?.cast<String>() ?? [],
        tvTags: (tvData['data']?['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(error: e.toString());
    }
  }

  Future<List<DoubanSubject>> fetchSubjects({
    String type = 'movie',
    String tag = '最新',
    int pageLimit = 20,
  }) async {
    try {
      final resp = await _api.post<Map<String, dynamic>>(ApiConstants.doubanSubjects, data: {
        'type': type,
        'tag': tag,
        'page_start': 0,
        'page_limit': pageLimit,
      });
      final data = resp.data!;
      final subjectsResp = DoubanSubjectsResponse.fromJson(
        (data['data'] ?? data) as Map<String, dynamic>,
      );
      return subjectsResp.subjects;
    } catch (_) {
      return [];
    }
  }
}

final doubanProvider = StateNotifierProvider<DoubanNotifier, DoubanState>((ref) {
  // Use ref.read — ApiClient is a stable singleton; ref.watch would cause
  // unnecessary dispose/recreate of this StateNotifier, resetting state.
  final api = ref.read(apiClientProvider);
  return DoubanNotifier(api);
});
