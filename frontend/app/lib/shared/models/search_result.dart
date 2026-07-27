/// Search result item — mirrors Web SearchResultItem.
class SearchResultItem {
  final int? vodId;
  final String resourceDomain;
  final String resourceName;
  final String title;
  final String? subtitle;
  final String? doubanId;
  final String? doubanScore;
  final String? year;
  final String? type;
  final int? typeId1;
  final String? genre;
  final String? cover;
  final String? actors;
  final String? director;
  final String? description;
  final String? remarks;
  final String? area;
  final String? lang;
  final String? score;
  final String? playFrom;
  final String? playUrl;

  const SearchResultItem({
    this.vodId,
    required this.resourceDomain,
    required this.resourceName,
    required this.title,
    this.subtitle,
    this.doubanId,
    this.doubanScore,
    this.year,
    this.type,
    this.typeId1,
    this.genre,
    this.cover,
    this.actors,
    this.director,
    this.description,
    this.remarks,
    this.area,
    this.lang,
    this.score,
    this.playFrom,
    this.playUrl,
  });

  factory SearchResultItem.fromJson(Map<String, dynamic> j) => SearchResultItem(
    vodId: j['vod_id'] as int?,
    resourceDomain: j['resource_domain'] as String? ?? '',
    resourceName: j['resource_name'] as String? ?? '',
    title: j['title'] as String? ?? '',
    subtitle: j['subtitle'] as String?,
    doubanId: j['douban_id']?.toString(),
    doubanScore: j['douban_score'] as String?,
    year: j['year'] as String?,
    type: j['type'] as String?,
    typeId1: j['type_id_1'] as int?,
    genre: j['genre'] as String?,
    cover: j['cover'] as String?,
    actors: j['actors'] as String?,
    director: j['director'] as String?,
    description: j['description'] as String?,
    remarks: j['remarks'] as String?,
    area: j['area'] as String?,
    lang: j['lang'] as String?,
    score: j['score'] as String?,
    playFrom: j['play_from'] as String?,
    playUrl: j['play_url'] as String?,
  );

  /// Group key for name-based grouping (mirrors Web).
  String get groupKey => doubanId != null ? 'db_$doubanId' : 'name_$title';
}

/// Merges name-based groups by consolidating items without doubanId into
/// their matching doubanId-based groups when they share the same title.
///
/// Problem: When the same movie appears across multiple sites, some sites
/// may have a `doubanId` while others don't. This causes the same movie
/// to be grouped under both `db_$doubanId` AND `name_$title`, resulting
/// in duplicate cards in the search page and incomplete group data in
/// the detail page.
///
/// Solution: After initial grouping by `groupKey`, merge all `name_$title`
/// groups into their corresponding `db_$doubanId` groups if the titles match.
/// The `db_$doubanId` group takes precedence; `name_$title` groups that
/// have no matching doubanId group are kept as-is.
///
/// [rawGroups] — map from raw groupKey (e.g. `db_12345`, `name_流浪地球`)
///                to items in that group.
/// Returns a new map where `name_$title` groups are merged into matching
/// `db_$doubanId` groups, and orphaned `name_$title` groups remain.
Map<String, List<SearchResultItem>> mergeNameGroups(
  Map<String, List<SearchResultItem>> rawGroups,
) {
  if (rawGroups.isEmpty) return {};

  // Build title -> groupKey mapping for all db_ groups
  final dbTitleToKey = <String, String>{};
  for (final entry in rawGroups.entries) {
    if (entry.key.startsWith('db_')) {
      for (final item in entry.value) {
        dbTitleToKey[item.title] = entry.key;
      }
    }
  }

  if (dbTitleToKey.isEmpty) return Map.from(rawGroups);

  // First: add all db_ groups
  final result = <String, List<SearchResultItem>>{};
  for (final entry in rawGroups.entries) {
    if (entry.key.startsWith('db_')) {
      result[entry.key] = [...entry.value];
    }
  }

  // Then: merge name_ groups into matching db_ groups (dedup by resourceDomain)
  for (final entry in rawGroups.entries) {
    if (entry.key.startsWith('name_')) {
      // Find the matching db_ group by title
      final dbKey = dbTitleToKey[entry.key.substring(5)]; // strip 'name_' prefix
      if (dbKey != null) {
        final existing = result[dbKey] ?? [];
        final existingDomains = existing.map((i) => i.resourceDomain).toSet();
        // Only add items whose resourceDomain is not already in the group
        final newItems = entry.value
            .where((i) => !existingDomains.contains(i.resourceDomain))
            .toList();
        result[dbKey] = [...existing, ...newItems];
      } else {
        // No matching db_ group, keep as-is
        result[entry.key] = [...entry.value];
      }
    }
  }

  return result;
}

/// SSE done event data.
class SearchDoneData {
  final String resourceDomain;
  final int count;
  const SearchDoneData({required this.resourceDomain, required this.count});
  factory SearchDoneData.fromJson(Map<String, dynamic> j) => SearchDoneData(
    resourceDomain: j['resource_domain'] as String? ?? '',
    count: j['count'] as int? ?? 0,
  );
}

/// SSE complete event data.
class SearchCompleteData {
  final int total;
  const SearchCompleteData({required this.total});
  factory SearchCompleteData.fromJson(Map<String, dynamic> j) => SearchCompleteData(
    total: j['total'] as int? ?? 0,
  );
}

/// SSE error event data.
class SearchErrorData {
  final String resourceDomain;
  final String message;
  const SearchErrorData({required this.resourceDomain, required this.message});
  factory SearchErrorData.fromJson(Map<String, dynamic> j) => SearchErrorData(
    resourceDomain: j['resource_domain'] as String? ?? '',
    message: j['message'] as String? ?? '',
  );
}
