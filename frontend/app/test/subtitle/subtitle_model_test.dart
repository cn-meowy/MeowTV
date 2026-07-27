// test/subtitle/subtitle_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowtv_mobile/features/player/subtitle/subtitle_model.dart';

void main() {
  group('SubtitleCue', () {
    test('creates with required fields', () {
      final cue = SubtitleCue(
        start: const Duration(seconds: 1, milliseconds: 500),
        end: const Duration(seconds: 4, milliseconds: 200),
        text: 'Hello World',
      );
      expect(cue.start.inMilliseconds, 1500);
      expect(cue.end.inMilliseconds, 4200);
      expect(cue.text, 'Hello World');
      expect(cue.style, isNull);
    });

    test('applies offset correctly', () {
      final cue = SubtitleCue(
        start: const Duration(seconds: 5),
        end: const Duration(seconds: 10),
        text: 'Test',
      );
      final offset = cue.withOffset(const Duration(milliseconds: -500));
      expect(offset.start.inMilliseconds, 4500);
      expect(offset.end.inMilliseconds, 9500);
    });

    test('offset does not make start negative', () {
      final cue = SubtitleCue(
        start: const Duration(milliseconds: 200),
        end: const Duration(seconds: 3),
        text: 'Early',
      );
      final offset = cue.withOffset(const Duration(milliseconds: -500));
      expect(offset.start.inMilliseconds, 0);
    });
  });

  group('SubtitleStyle', () {
    test('defaults are correct', () {
      const style = SubtitleStyle.defaults();
      expect(style.fontSize, 25);
      expect(style.color, 0xFFFFFFFF);
      expect(style.showStroke, isTrue);
      expect(style.strokeColor, 0xFF000000);
      expect(style.strokeWidth, 2.0);
    });

    test('copyWith works', () {
      const style = SubtitleStyle.defaults();
      final modified = style.copyWith(color: 0xFFFF0000, fontSize: 30);
      expect(modified.color, 0xFFFF0000);
      expect(modified.fontSize, 30);
      expect(modified.showStroke, style.showStroke);
    });
  });

  group('SubtitleTrack', () {
    test('creates with cues', () {
      final track = SubtitleTrack(
        id: 'test-1',
        label: '中文(简体)',
        language: 'zh-Hans',
        source: SubtitleSource.external,
        cues: [
          SubtitleCue(start: const Duration(seconds: 1), end: const Duration(seconds: 3), text: '你好'),
          SubtitleCue(start: const Duration(seconds: 5), end: const Duration(seconds: 7), text: '世界'),
        ],
      );
      expect(track.cues.length, 2);
      expect(track.source, SubtitleSource.external);
    });
  });

  group('SubtitleMode', () {
    test('enum values', () {
      expect(SubtitleMode.values, containsAll([
        SubtitleMode.off,
        SubtitleMode.embedded,
        SubtitleMode.external,
        SubtitleMode.online,
      ]));
    });
  });
}
