import 'subtitle_model.dart';

/// Abstract interface for an online subtitle source (e.g. OpenSubtitles, Shooter).
abstract class OnlineSubtitleSource {
  String get id;
  String get displayName;
  Future<List<SubtitleSearchResult>> search(SubtitleSearchQuery query);
  Future<SubtitleDownloadResult> download(SubtitleSearchResult result);
}

/// Registry of available online subtitle sources.
class SubtitleSourceRegistry {
  final Map<String, OnlineSubtitleSource> _sources = {};

  void register(OnlineSubtitleSource source) {
    _sources[source.id] = source;
  }

  void unregister(String sourceId) {
    _sources.remove(sourceId);
  }

  List<OnlineSubtitleSource> get available => List.unmodifiable(_sources.values);

  OnlineSubtitleSource? get(String sourceId) => _sources[sourceId];

  bool get hasSources => _sources.isNotEmpty;
}
