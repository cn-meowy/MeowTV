/// Resource site item — mirrors Web ResourceSiteItem.
class ResourceSiteItem {
  final String domain;
  final String name;
  final String api;
  final String detail;
  final String? comment;
  final int? cacheTime;
  final bool isEnabled;
  final bool isAdult;
  final bool searchable;

  const ResourceSiteItem({
    required this.domain,
    required this.name,
    required this.api,
    required this.detail,
    this.comment,
    this.cacheTime,
    required this.isEnabled,
    required this.isAdult,
    required this.searchable,
  });

  factory ResourceSiteItem.fromJson(Map<String, dynamic> j) => ResourceSiteItem(
    domain: j['domain'] as String? ?? '',
    name: j['name'] as String? ?? '',
    api: j['api'] as String? ?? '',
    detail: j['detail'] as String? ?? '',
    comment: j['comment'] as String?,
    cacheTime: j['cache_time'] as int?,
    isEnabled: j['is_enabled'] as bool? ?? true,
    isAdult: j['is_adult'] as bool? ?? false,
    searchable: j['searchable'] as bool? ?? true,
  );
}
