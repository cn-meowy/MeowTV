import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../shared/models/resource_page.dart';
import '../../shared/models/resource_site.dart';
import '../../shared/models/search_result.dart';
// api_constants.dart already imported above

/// 目标每页行数，pageSize = crossAxisCount × [_rowsPerPage]，
/// 保证每页数据填满完整的网格行，避免最后一行不满。
const _rowsPerPage = 7;

/// Resource page state.
class ResourceState {
  final List<ResourceSiteItem> sites;
  final String selectedResource;
  final String keyword;
  final int page;
  final List<SearchResultItem> results;
  final int total;
  final int totalPages;
  final bool loading;
  final String? error;
  final List<String> searchHistory;

  /// 当前网格列数（响应式，由 UI 层根据屏幕宽度计算后回传）。
  /// 与 [pageSize] 联动，保证每页数据填满完整行，避免最后一行不满。
  final int crossAxisCount;

  /// 动态分页大小 = crossAxisCount × [_rowsPerPage]，随列数变化自动重算。
  final int pageSize;

  const ResourceState({
    this.sites = const [],
    this.selectedResource = '',
    this.keyword = '',
    this.page = 1,
    this.results = const [],
    this.total = 0,
    this.totalPages = 0,
    this.loading = false,
    this.error,
    this.searchHistory = const [],
    this.crossAxisCount = 3,
    this.pageSize = 3 * _rowsPerPage,
  });

  ResourceState copyWith({
    List<ResourceSiteItem>? sites,
    String? selectedResource,
    String? keyword,
    int? page,
    List<SearchResultItem>? results,
    int? total,
    int? totalPages,
    bool? loading,
    String? error,
    List<String>? searchHistory,
    int? crossAxisCount,
    int? pageSize,
  }) => ResourceState(
    sites: sites ?? this.sites,
    selectedResource: selectedResource ?? this.selectedResource,
    keyword: keyword ?? this.keyword,
    page: page ?? this.page,
    results: results ?? this.results,
    total: total ?? this.total,
    totalPages: totalPages ?? this.totalPages,
    loading: loading ?? this.loading,
    error: error,
    searchHistory: searchHistory ?? this.searchHistory,
    crossAxisCount: crossAxisCount ?? this.crossAxisCount,
    pageSize: pageSize ?? this.pageSize,
  );
}

class ResourceNotifier extends StateNotifier<ResourceState> {
  final ApiClient _api;

  ResourceNotifier(this._api) : super(const ResourceState());

  CancelToken? _cancelToken;

  /// 根据网格列数计算分页大小，确保 pageSize 是列数的整数倍
  /// （每页填满完整行），并兜底在 [1, 100] 区间内满足后端校验。
  int _calcPageSize(int crossAxisCount) {
    final raw = crossAxisCount * _rowsPerPage;
    return raw.clamp(crossAxisCount, 100);
  }

  /// UI 层在屏幕宽度跨越断点（手机/平板）时调用，回传当前网格列数。
  ///
  /// 列数变化时自动重算 [ResourceState.pageSize] 并以新分页大小
  /// 重新拉取当前页数据，保证每页都填满完整行，无残缺末行。
  void setCrossAxisCount(int count) {
    if (count == state.crossAxisCount) return;
    final newPageSize = _calcPageSize(count);
    state = state.copyWith(crossAxisCount: count, pageSize: newPageSize);
    // 列数变化 -> pageSize 变化 -> 以新分页大小重新拉取当前页
    fetchData(
      state.selectedResource,
      state.page,
      state.keyword.trim().isNotEmpty ? state.keyword.trim() : null,
    );
  }

  /// Load available resource sites and trigger first fetch.
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
              .toList() ??
          [];

      // Default: select the first site
      final defaultDomain = items.isNotEmpty ? items.first.domain : '';
      state = state.copyWith(sites: items, selectedResource: defaultDomain);

      if (defaultDomain.isNotEmpty) {
        fetchData(defaultDomain, 1);
      }
    } catch (e) {
      // Silently fail — sites list will remain empty
    }
  }

  /// Fetch paginated data for a given resource domain and page.
  Future<void> fetchData(
    String resourceDomain,
    int currentPage, [
    String? searchKeyword,
  ]) async {
    if (resourceDomain.isEmpty) return;

    // Cancel previous request
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    if (!mounted) return;
    state = state.copyWith(loading: true, error: null);

    try {
      final resp = await _api.post<Map<String, dynamic>>(
        ApiConstants.resourcePaginate,
        data: {
          'page': currentPage,
          'page_size': state.pageSize,
          'resource': resourceDomain,
          if (searchKeyword != null && searchKeyword.trim().isNotEmpty)
            'keyword': searchKeyword.trim(),
        },
      );

      if (!mounted) return;
      final body = resp.data!;
      final pageResp = ResourcePageResp.fromJson(
        body['data'] as Map<String, dynamic>,
      );

      state = state.copyWith(
        results: pageResp.items,
        total: pageResp.total,
        totalPages: pageResp.totalPages,
        page: currentPage,
        loading: false,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      if (!mounted) return;
      state = state.copyWith(
        results: [],
        total: 0,
        totalPages: 0,
        loading: false,
        error: '请求资源站失败',
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        results: [],
        total: 0,
        totalPages: 0,
        loading: false,
        error: '请求资源站失败',
      );
    }
  }

  /// Switch to a different resource site.
  void handleResourceChange(String domain) {
    if (domain == state.selectedResource) return;
    state = state.copyWith(selectedResource: domain, page: 1, keyword: '');
    fetchData(domain, 1);
  }

  /// Search with the current keyword (triggered on Enter).
  void handleSearch() {
    final kw = state.keyword.trim();
    if (kw.isEmpty) return;
    saveSearchHistory(kw);
    // Update local searchHistory so chips reflect the new keyword immediately
    if (!state.searchHistory.contains(kw)) {
      final updated = [kw, ...state.searchHistory.where((k) => k != kw)];
      state = state.copyWith(page: 1, searchHistory: updated);
    } else {
      state = state.copyWith(page: 1);
    }
    fetchData(state.selectedResource, 1, kw);
  }

  /// Clear the keyword input — does NOT trigger a query.
  void handleClearKeyword() {
    state = state.copyWith(keyword: '');
  }

  /// Update keyword display value — does NOT trigger a query.
  void handleKeywordChange(String value) {
    state = state.copyWith(keyword: value);
  }

  /// Navigate to a different page.
  void handlePageChange(int newPage) {
    if (newPage < 1 || newPage > state.totalPages) return;
    state = state.copyWith(page: newPage);
    fetchData(
      state.selectedResource,
      newPage,
      state.keyword.trim().isNotEmpty ? state.keyword.trim() : null,
    );
  }

  /// Retry the last failed request.
  void retry() {
    fetchData(
      state.selectedResource,
      state.page,
      state.keyword.trim().isNotEmpty ? state.keyword.trim() : null,
    );
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
      state = state.copyWith(searchHistory: items);
    } catch (_) {}
  }

  /// Save search keyword to backend history.
  Future<void> saveSearchHistory(String keyword) async {
    try {
      await _api.post(
        ApiConstants.searchHistoryAdd,
        data: {'keyword': keyword},
      );
    } catch (_) {}
  }

  /// Clear all search history.
  Future<void> clearSearchHistory() async {
    try {
      await _api.post(ApiConstants.searchHistoryClear);
    } catch (_) {}
    if (!mounted) return;
    state = state.copyWith(searchHistory: []);
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }
}

final resourceProvider = StateNotifierProvider<ResourceNotifier, ResourceState>(
  (ref) {
    final api = ref.read(apiClientProvider);
    return ResourceNotifier(api);
  },
);
