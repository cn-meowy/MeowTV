/// Resource detail models — mirrors Web ResourceDetailResp, PlaySource, PlayEpisode.
library;

class ResourceDetailResponse {
  final int vodId;
  final String vodName;
  final String? vodSub;
  final String? vodPic;
  final String? vodActor;
  final String? vodDirector;
  final String? vodBlurb;
  final String? vodContent;
  final String? vodRemarks;
  final String? vodArea;
  final String? vodLang;
  final String? vodYear;
  final String? vodScore;
  final int? vodDoubanId;
  final String? vodDoubanScore;
  final String? vodClass;
  final String? vodPlayUrl;
  final String? vodPlayFrom;
  final String? typeName;
  final int? typeId1;
  final String resourceDomain;
  final String resourceName;

  const ResourceDetailResponse({
    required this.vodId,
    required this.vodName,
    this.vodSub,
    this.vodPic,
    this.vodActor,
    this.vodDirector,
    this.vodBlurb,
    this.vodContent,
    this.vodRemarks,
    this.vodArea,
    this.vodLang,
    this.vodYear,
    this.vodScore,
    this.vodDoubanId,
    this.vodDoubanScore,
    this.vodClass,
    this.vodPlayUrl,
    this.vodPlayFrom,
    this.typeName,
    this.typeId1,
    required this.resourceDomain,
    required this.resourceName,
  });

  factory ResourceDetailResponse.fromJson(Map<String, dynamic> j) => ResourceDetailResponse(
    vodId: j['vod_id'] as int? ?? 0,
    vodName: j['vod_name'] as String? ?? '',
    vodSub: j['vod_sub'] as String?,
    vodPic: j['vod_pic'] as String?,
    vodActor: j['vod_actor'] as String?,
    vodDirector: j['vod_director'] as String?,
    vodBlurb: j['vod_blurb'] as String?,
    vodContent: j['vod_content'] as String?,
    vodRemarks: j['vod_remarks'] as String?,
    vodArea: j['vod_area'] as String?,
    vodLang: j['vod_lang'] as String?,
    vodYear: j['vod_year'] as String?,
    vodScore: j['vod_score'] as String?,
    vodDoubanId: j['vod_douban_id'] as int?,
    vodDoubanScore: j['vod_douban_score'] as String?,
    vodClass: j['vod_class'] as String?,
    vodPlayUrl: j['vod_play_url'] as String?,
    vodPlayFrom: j['vod_play_from'] as String?,
    typeName: j['type_name'] as String?,
    typeId1: j['type_id_1'] as int?,
    resourceDomain: j['resource_domain'] as String? ?? '',
    resourceName: j['resource_name'] as String? ?? '',
  );

  /// Parsed play sources with m3u8/mp4 filtering.
  List<PlaySource> get parsedSources => PlaySourceParser.parse(vodPlayUrl ?? '', vodPlayFrom);
}

class PlayEpisode {
  final String name;
  final String url;
  const PlayEpisode({required this.name, required this.url});
}

class PlaySource {
  final String name;
  final List<PlayEpisode> episodes;
  const PlaySource({required this.name, required this.episodes});
}

/// Parser for vod_play_url — mirrors Web parsePlaySources exactly.
class PlaySourceParser {
  // The separator between sources is three dollar signs: $$$
  static const _sourceSep = r'$$$';

  static List<PlaySource> parse(String vodPlayUrl, [String? vodPlayFrom]) {
    if (vodPlayUrl.isEmpty) return [];

    final sourceSegments = vodPlayUrl.split(_sourceSep);
    final fromNames = vodPlayFrom?.split(_sourceSep) ?? [];

    final sources = <PlaySource>[];

    for (var si = 0; si < sourceSegments.length; si++) {
      final segment = sourceSegments[si].trim();
      if (segment.isEmpty) continue;

      final sourceName = (si < fromNames.length && fromNames[si].trim().isNotEmpty)
          ? fromNames[si].trim()
          : '线路${si + 1}';
      final episodes = <PlayEpisode>[];

      for (final part in segment.split('#')) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        final dollarIdx = trimmed.indexOf('\$');
        String epName;
        String epUrl;
        if (dollarIdx == -1) {
          epName = '第${episodes.length + 1}集';
          epUrl = trimmed;
        } else {
          epName = trimmed.substring(0, dollarIdx).trim();
          if (epName.isEmpty) epName = '第${episodes.length + 1}集';
          epUrl = trimmed.substring(dollarIdx + 1).trim();
        }
        if (epUrl.isEmpty) continue;
        // Only keep m3u8 and mp4 — filter out iframe/webplayer
        final isM3u8 = epUrl.contains('.m3u8');
        final isMp4 = RegExp(r'\.mp4(\?.*)?$', caseSensitive: false).hasMatch(epUrl);
        if (!isM3u8 && !isMp4) continue;
        episodes.add(PlayEpisode(name: epName, url: epUrl));
      }

      if (episodes.isNotEmpty) {
        sources.add(PlaySource(name: sourceName, episodes: episodes));
      }
    }
    return sources;
  }
}
