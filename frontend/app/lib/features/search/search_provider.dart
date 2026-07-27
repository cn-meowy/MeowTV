import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger/app_logger.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/sse_client.dart';
import '../../shared/models/search_result.dart';
import '../../shared/models/resource_site.dart';

/// Grouping mode for search results.
enum SearchGroupMode { bySite, byName }

/// Sentinel for copyWith nullable fields that need to be cleared.
const _searchUnset = Object();

/// Search page state.
class SearchState {
  final String query;
  final List<SearchResultItem> results;
  final Map<String, String> siteDoneMap; // domain -> status
  final int totalResults;
  final int siteTotalCount; // Cumulative count from onDone events
  final bool isSearching;
  final SearchGroupMode groupMode;
  final List<ResourceSiteItem> sites;
  final List<String> selectedResources;
  final List<String> searchHistory;
  final String? doubanId; // Douban ID for precise search
  final String? error;
  final bool isExpanded; // Whether the resource dropdown panel is expanded
  final Map<String, List<SearchResultItem>> groupedResults; // groupKey -> items

  const SearchState({
    this.query = '',
    this.results = const [],
    this.siteDoneMap = const {},
    this.totalResults = 0,
    this.siteTotalCount = 0,
    this.isSearching = false,
    this.groupMode = SearchGroupMode.bySite,
    this.sites = const [],
    this.selectedResources = const [],
    this.searchHistory = const [],
    this.doubanId,
    this.error,
    this.isExpanded = false,
    this.groupedResults = const {},
  });

  SearchState copyWith({
    String? query,
    List<SearchResultItem>? results,
    Map<String, String>? siteDoneMap,
    int? totalResults,
    int? siteTotalCount,
    bool? isSearching,
    SearchGroupMode? groupMode,
    List<ResourceSiteItem>? sites,
    List<String>? selectedResources,
    List<String>? searchHistory,
    String? doubanId,
    bool clearDoubanId = false,
    Object? error = _searchUnset,
    bool? isExpanded,
    Map<String, List<SearchResultItem>>? groupedResults,
  }) => SearchState(
    query: query ?? this.query,
    results: results ?? this.results,
    siteDoneMap: siteDoneMap ?? this.siteDoneMap,
    totalResults: totalResults ?? this.totalResults,
    siteTotalCount: siteTotalCount ?? this.siteTotalCount,
    isSearching: isSearching ?? this.isSearching,
    groupMode: groupMode ?? this.groupMode,
    sites: sites ?? this.sites,
    selectedResources: selectedResources ?? this.selectedResources,
    searchHistory: searchHistory ?? this.searchHistory,
    doubanId: clearDoubanId ? null : (doubanId ?? this.doubanId),
    error: identical(error, _searchUnset) ? this.error : error as String?,
    isExpanded: isExpanded ?? this.isExpanded,
    groupedResults: groupedResults ?? this.groupedResults,
  );

  /// Whether there are any adult sites.
  bool get hasAdultSites => sites.any((s) => s.isAdult);

  /// Whether all sites are selected.
  bool get isAllSelected =>
      sites.isNotEmpty && selectedResources.length == sites.length;

  /// Whether all adult sites are selected.
  bool get isAdultAllSelected {
    final adultSites = sites.where((s) => s.isAdult);
    return adultSites.isNotEmpty &&
        adultSites.every((s) => selectedResources.contains(s.domain));
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  final ApiClient _api;
  final SseClient _sse;

  SearchNotifier(this._api, this._sse) : super(const SearchState());

  CancelToken? _cancelToken;

  /// Load available resource sites.
  Future<void> loadSites() async {
    try {
      final resp = await _api.post<Map<String, dynamic>>(
        ApiConstants.resourceSites,
      );
      if (!mounted) return;
      final data = resp.data!;
      final items =
          (data['data'] as List<dynamic>?)
              ?.map((e) => ResourceSiteItem.fromJson(e as Map<String, dynamic>))
              .where((s) => s.isEnabled && s.searchable)
              .toList() ??
          [];
      // Default: select non-adult sites
      final defaultSelected = items
          .where((s) => !s.isAdult)
          .map((s) => s.domain)
          .toList();
      state = state.copyWith(sites: items, selectedResources: defaultSelected);
    } catch (_) {}
  }

  /// Load search history from backend.
  Future<void> loadSearchHistory() async {
    try {
      final resp = await _api.post<Map<String, dynamic>>(
        ApiConstants.searchHistoryList,
        data: {"limit": 10},
      );
      if (!mounted) return;
      final data = resp.data!;
      // Backend returns data as a flat array: {"code":200,"data":[{...}]}
      final rawItems = data['data'] as List<dynamic>?;
      final items =
          rawItems
              ?.map((e) => e['keyword'] as String? ?? '')
              .where((k) => k.isNotEmpty)
              .toList() ??
          [];
      appLogger.d('[SearchNotifier] loadSearchHistory: got ${items.length} items');
      state = state.copyWith(searchHistory: items);
    } catch (e) {
      appLogger.e('[SearchNotifier] loadSearchHistory FAILED', error: e);
    }
  }

  /// Execute SSE search.
  Future<void> search(String query, {String? doubanId}) async {
    if (query.trim().isEmpty) return;

    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    state = state.copyWith(
      query: query,
      results: [],
      siteDoneMap: {},
      totalResults: 0,
      siteTotalCount: 0,
      isSearching: true,
      doubanId: doubanId,
      error: null,
      groupedResults: {},
    );

    // Save search history (backend + local state)
    try {
      await _api.post(ApiConstants.searchHistoryAdd, data: {'keyword': query});
    } catch (_) {}
    // Update local searchHistory so chips reflect the new keyword immediately
    if (mounted && !state.searchHistory.contains(query)) {
      final updated = [query, ...state.searchHistory.where((k) => k != query)];
      state = state.copyWith(searchHistory: updated);
    }

    await _sse.searchSSE(
      query: query,
      doubanId: doubanId,
      resources: state.selectedResources.isNotEmpty
          ? state.selectedResources
          : null,
      callbacks: SearchCallbacks(
        onResult: (item) {
          if (!mounted) return;
          final newResults = [...state.results, item];
          final newTotal = newResults.length > state.siteTotalCount
              ? newResults.length
              : state.siteTotalCount;
          // Sync groupedResults: add item by its raw groupKey, then merge
          // name-based groups into matching doubanId-based groups to avoid
          // duplicate cards when the same movie has mixed doubanId presence
          // across different resource sites.
          final newGrouped = Map<String, List<SearchResultItem>>.from(
            state.groupedResults,
          );
          newGrouped.putIfAbsent(item.groupKey, () => []).add(item);
          final mergedGrouped = mergeNameGroups(newGrouped);
          state = state.copyWith(
            results: newResults,
            totalResults: newTotal,
            groupedResults: mergedGrouped,
          );
        },
        onDone: (data) {
          if (!mounted) return;
          final newSiteTotal = state.siteTotalCount + data.count;
          final newTotal = state.results.length > newSiteTotal
              ? state.results.length
              : newSiteTotal;
          state = state.copyWith(
            siteDoneMap: {
              ...state.siteDoneMap,
              data.resourceDomain: 'done (${data.count})',
            },
            siteTotalCount: newSiteTotal,
            totalResults: newTotal,
          );
        },
        onComplete: (data) {
          if (!mounted) return;
          final newTotal = [
            state.results.length,
            state.siteTotalCount,
            data.total,
          ].reduce((a, b) => a > b ? a : b);
          state = state.copyWith(totalResults: newTotal, isSearching: false);
        },
        onError: (data) {
          if (!mounted) return;
          state = state.copyWith(
            siteDoneMap: {
              ...state.siteDoneMap,
              data.resourceDomain: 'error: ${data.message}',
            },
          );
        },
      ),
      cancelToken: _cancelToken,
    );

    if (state.isSearching) {
      state = state.copyWith(isSearching: false);
    }
  }

  /// Clear doubanId (e.g. when user modifies search text).
  void clearDoubanId() {
    state = state.copyWith(clearDoubanId: true);
  }

  /// Cancel current search.
  void cancelSearch() {
    _cancelToken?.cancel();
    _cancelToken = null;
    state = state.copyWith(isSearching: false);
  }

  /// Toggle a resource filter.
  void toggleResource(String domain) {
    final current = List<String>.from(state.selectedResources);
    if (current.contains(domain)) {
      current.remove(domain);
    } else {
      current.add(domain);
    }
    state = state.copyWith(selectedResources: current);
  }

  /// Select / deselect all resources.
  void toggleAllResources() {
    final allDomains = state.sites.map((s) => s.domain).toList();
    final allSelected = state.selectedResources.length == allDomains.length;
    state = state.copyWith(selectedResources: allSelected ? [] : allDomains);
  }

  /// Toggle all adult resources.
  void toggleAdultResources() {
    final adultDomains = state.sites
        .where((s) => s.isAdult)
        .map((s) => s.domain)
        .toList();
    final allAdultSelected = adultDomains.every(
      (d) => state.selectedResources.contains(d),
    );
    final current = List<String>.from(state.selectedResources);
    if (allAdultSelected) {
      current.removeWhere((d) => adultDomains.contains(d));
    } else {
      for (final d in adultDomains) {
        if (!current.contains(d)) current.add(d);
      }
    }
    state = state.copyWith(selectedResources: current);
  }

  /// Switch grouping mode.
  void setGroupMode(SearchGroupMode mode) {
    state = state.copyWith(groupMode: mode);
  }

  /// Toggle the resource dropdown panel expanded state.
  void toggleExpanded() {
    state = state.copyWith(isExpanded: !state.isExpanded);
  }

  /// Collapse the resource dropdown panel.
  void collapseExpanded() {
    if (state.isExpanded) {
      state = state.copyWith(isExpanded: false);
    }
  }

  /// Clear search history.
  Future<void> clearSearchHistory() async {
    try {
      await _api.post(ApiConstants.searchHistoryClear);
    } catch (_) {}
    if (!mounted) return;
    state = state.copyWith(searchHistory: []);
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((
  ref,
) {
  final api = ref.read(apiClientProvider);
  final sse = ref.watch(sseClientProvider);
  return SearchNotifier(api, sse);
});
