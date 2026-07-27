import 'search_result.dart';

/// Paginated response for /api/resource/paginate — mirrors Web ResourcePageResp.
class ResourcePageResp {
  final List<SearchResultItem> items;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  const ResourcePageResp({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  factory ResourcePageResp.fromJson(Map<String, dynamic> j) => ResourcePageResp(
    items: (j['items'] as List<dynamic>?)
            ?.map((e) => SearchResultItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    total: j['total'] as int? ?? 0,
    page: j['page'] as int? ?? 1,
    pageSize: j['page_size'] as int? ?? 20,
    totalPages: j['total_pages'] as int? ?? 0,
  );
}
