import 'package:flutter_test/flutter_test.dart';
import 'package:meowtv_mobile/features/player/subtitle/subtitle_manager.dart';
import 'package:meowtv_mobile/features/player/subtitle/subtitle_model.dart';

void main() {
  group('SubtitleManager', () {
    late SubtitleManager manager;
    setUp(() { manager = SubtitleManager(); });
    tearDown(() { manager.dispose(); });

    test('initial state is off', () {
      expect(manager.mode, SubtitleMode.off);
      expect(manager.activeTrack, isNull);
      expect(manager.offsetMs, 0.0);
    });

    test('selectTrack changes mode and active track', () {
      final track = SubtitleTrack(
        id: 'test', label: 'Test', language: 'en',
        source: SubtitleSource.external,
        cues: [SubtitleCue(start: Duration.zero, end: const Duration(seconds: 2), text: 'Hi')],
      );
      manager.selectTrack(track);
      expect(manager.activeTrack, track);
      expect(manager.mode, SubtitleMode.external);
    });

    test('disable resets to off', () {
      final track = SubtitleTrack(
        id: 'test', label: 'Test', language: 'en',
        source: SubtitleSource.external,
        cues: [SubtitleCue(start: Duration.zero, end: const Duration(seconds: 2), text: 'Hi')],
      );
      manager.selectTrack(track);
      manager.disable();
      expect(manager.mode, SubtitleMode.off);
      expect(manager.activeTrack, isNull);
    });

    test('setOffset changes offsetMs', () {
      manager.setOffset(500.0);
      expect(manager.offsetMs, 500.0);
      manager.setOffset(-1000.0);
      expect(manager.offsetMs, -1000.0);
    });

    test('setOffset notifies listeners', () {
      int notifyCount = 0;
      manager.addListener(() => notifyCount++);
      manager.setOffset(500.0);
      expect(notifyCount, 1);
    });

    test('getActiveCues returns cues for current position with offset', () {
      final track = SubtitleTrack(
        id: 'test', label: 'Test', language: 'en',
        source: SubtitleSource.external,
        cues: [
          SubtitleCue(start: const Duration(seconds: 1), end: const Duration(seconds: 3), text: 'First'),
          SubtitleCue(start: const Duration(seconds: 5), end: const Duration(seconds: 7), text: 'Second'),
        ],
      );
      manager.selectTrack(track);

      var cues = manager.getActiveCues(const Duration(seconds: 2));
      expect(cues.length, 1);
      expect(cues[0].text, 'First');

      cues = manager.getActiveCues(const Duration(seconds: 4));
      expect(cues, isEmpty);

      manager.setOffset(-1000.0);
      cues = manager.getActiveCues(const Duration(milliseconds: 1500));
      expect(cues.length, 1);
      expect(cues[0].text, 'First');
    });

    test('setEmbeddedTracks updates tracks list', () {
      manager.setEmbeddedTracks([
        const EmbeddedSubtitleTrack(index: 0, label: '中文', language: 'zh'),
        const EmbeddedSubtitleTrack(index: 1, label: 'English', language: 'en'),
      ]);
      expect(manager.embeddedTracks.length, 2);
    });
  });
}
