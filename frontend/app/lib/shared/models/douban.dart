/// Douban models — mirrors Web DoubanSubject, DoubanTags, etc.
library;

import '../utils/image_utils.dart';

class DoubanSubject {
  final String id;
  final String title;
  final String cover;
  final String rate;
  final String url;
  final String? cardSubtitle;
  final String? type;
  final List<String>? tags;

  const DoubanSubject({
    required this.id,
    required this.title,
    required this.cover,
    required this.rate,
    required this.url,
    this.cardSubtitle,
    this.type,
    this.tags,
  });

  /// 将封面 URL 中的尺寸标识替换为原图路径（用于轮播大图）
  String get originalCover => ImageUtils.replaceToOriginal(cover);

  factory DoubanSubject.fromJson(Map<String, dynamic> j) => DoubanSubject(
    id: j['id']?.toString() ?? '',
    title: j['title'] as String? ?? '',
    cover: j['cover'] as String? ?? '',
    rate: j['rate']?.toString() ?? '',
    url: j['url'] as String? ?? '',
    cardSubtitle: j['card_subtitle'] as String?,
    type: j['type'] as String?,
    tags: (j['tags'] as List<dynamic>?)?.cast<String>(),
  );

  DoubanSubject copyWith({
    String? id,
    String? title,
    String? cover,
    String? rate,
    String? url,
    String? cardSubtitle,
    String? type,
    List<String>? tags,
  }) =>
      DoubanSubject(
        id: id ?? this.id,
        title: title ?? this.title,
        cover: cover ?? this.cover,
        rate: rate ?? this.rate,
        url: url ?? this.url,
        cardSubtitle: cardSubtitle ?? this.cardSubtitle,
        type: type ?? this.type,
        tags: tags ?? this.tags,
      );
}

class DoubanSubjectsResponse {
  final List<DoubanSubject> subjects;
  final int total;
  final bool hasMore;
  const DoubanSubjectsResponse({required this.subjects, required this.total, required this.hasMore});
  factory DoubanSubjectsResponse.fromJson(Map<String, dynamic> j) => DoubanSubjectsResponse(
    subjects: (j['subjects'] as List<dynamic>?)
            ?.map((e) => DoubanSubject.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    total: j['total'] as int? ?? 0,
    hasMore: j['has_more'] as bool? ?? false,
  );
}

class DoubanTagsResponse {
  final List<String> tags;
  const DoubanTagsResponse({required this.tags});
  factory DoubanTagsResponse.fromJson(Map<String, dynamic> j) => DoubanTagsResponse(
    tags: (j['tags'] as List<dynamic>?)?.cast<String>() ?? [],
  );
}
