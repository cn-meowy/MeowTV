import 'package:flutter/foundation.dart';
import 'subtitle_model.dart';

class SubtitleManager extends ChangeNotifier {
  SubtitleMode _mode = SubtitleMode.off;
  SubtitleTrack? _activeTrack;
  double _offsetMs = 0.0;
  List<EmbeddedSubtitleTrack> _embeddedTracks = [];

  SubtitleMode get mode => _mode;
  SubtitleTrack? get activeTrack => _activeTrack;
  double get offsetMs => _offsetMs;
  List<EmbeddedSubtitleTrack> get embeddedTracks => List.unmodifiable(_embeddedTracks);

  void selectTrack(SubtitleTrack track) {
    _activeTrack = track;
    _mode = _modeFromSource(track.source);
    notifyListeners();
  }

  void disable() {
    _activeTrack = null;
    _mode = SubtitleMode.off;
    notifyListeners();
  }

  void setOffset(double ms) {
    _offsetMs = ms;
    notifyListeners();
  }

  void setEmbeddedTracks(List<EmbeddedSubtitleTrack> tracks) {
    _embeddedTracks = List.from(tracks);
    notifyListeners();
  }

  List<SubtitleCue> getActiveCues(Duration position) {
    if (_activeTrack == null) return [];
    final offsetDuration = Duration(milliseconds: _offsetMs.round());
    return _activeTrack!.cues
        .map((cue) => cue.withOffset(offsetDuration))
        .where((cue) => position >= cue.start && position <= cue.end)
        .toList();
  }

  SubtitleMode _modeFromSource(SubtitleSource source) {
    switch (source) {
      case SubtitleSource.embedded:
        return SubtitleMode.embedded;
      case SubtitleSource.external:
        return SubtitleMode.external;
      case SubtitleSource.online:
        return SubtitleMode.online;
    }
  }
}
