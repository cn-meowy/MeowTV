import 'package:flutter/services.dart';
import 'subtitle_model.dart';

class SubtitleRenderBridge {
  static const _channel = MethodChannel('com.meowtv.subtitle/render');

  Future<List<EmbeddedSubtitleTrack>> getEmbeddedTracks() async {
    try {
      final result = await _channel.invokeMethod<List>('getEmbeddedTracks');
      if (result == null) return [];
      return result.map((track) {
        final map = track as Map;
        return EmbeddedSubtitleTrack(
          index: map['index'] as int,
          label: (map['label'] as String?) ?? '字幕 ${map['index']}',
          language: (map['language'] as String?) ?? '',
        );
      }).toList();
    } on PlatformException catch (_) {
      return [];
    } on MissingPluginException catch (_) {
      return [];
    }
  }

  Future<bool> selectEmbeddedTrack(int trackIndex) async {
    try {
      await _channel.invokeMethod('selectEmbeddedTrack', {'trackIndex': trackIndex});
      return true;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  Future<bool> loadExternalSubtitle(List<SubtitleCue> cues, {double offsetMs = 0.0}) async {
    try {
      final cueData = cues.map((c) => c.toJson()).toList();
      await _channel.invokeMethod('loadExternalSubtitle', {'cues': cueData, 'offsetMs': offsetMs});
      return true;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  Future<bool> updateOffset(double offsetMs) async {
    try {
      await _channel.invokeMethod('updateOffset', {'offsetMs': offsetMs});
      return true;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  Future<void> clearSubtitle() async {
    try {
      await _channel.invokeMethod('clearSubtitle');
    } on PlatformException catch (_) {
      // Intentionally silent — best-effort clear
    } on MissingPluginException catch (_) {
      // Intentionally silent — best-effort clear
    }
  }
}
