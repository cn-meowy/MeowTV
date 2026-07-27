// test/subtitle/subtitle_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowtv_mobile/features/player/subtitle/subtitle_parser.dart';

void main() {
  group('SrtParser', () {
    late SrtParser parser;
    setUp(() { parser = SrtParser(); });

    test('parses simple SRT content', () async {
      const content = '1\n00:00:01,000 --> 00:00:04,000\nHello World\n\n2\n00:00:05,000 --> 00:00:08,000\nSecond line\n';
      final cues = await parser.parse(content);
      expect(cues.length, 2);
      expect(cues[0].start.inMilliseconds, 1000);
      expect(cues[0].end.inMilliseconds, 4000);
      expect(cues[0].text, 'Hello World');
      expect(cues[1].start.inMilliseconds, 5000);
      expect(cues[1].text, 'Second line');
    });

    test('parses multi-line subtitle', () async {
      const content = '1\n00:00:01,000 --> 00:00:04,000\nLine one\nLine two\n';
      final cues = await parser.parse(content);
      expect(cues.length, 1);
      expect(cues[0].text, 'Line one\nLine two');
    });

    test('handles empty content', () async {
      final cues = await parser.parse('');
      expect(cues, isEmpty);
    });

    test('skips malformed entries', () async {
      const content = '1\nnot a timestamp\nBad entry\n\n2\n00:00:01,000 --> 00:00:04,000\nGood entry\n';
      final cues = await parser.parse(content);
      expect(cues.length, 1);
      expect(cues[0].text, 'Good entry');
    });
  });

  group('VttParser', () {
    late VttParser parser;
    setUp(() { parser = VttParser(); });

    test('parses simple VTT content', () async {
      const content = 'WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nHello World\n\n00:00:05.000 --> 00:00:08.000\nSecond line\n';
      final cues = await parser.parse(content);
      expect(cues.length, 2);
      expect(cues[0].start.inMilliseconds, 1000);
      expect(cues[0].end.inMilliseconds, 4000);
      expect(cues[0].text, 'Hello World');
    });

    test('parses VTT with hours', () async {
      const content = 'WEBVTT\n\n01:02:03.500 --> 01:02:06.500\nTest with hours\n';
      final cues = await parser.parse(content);
      expect(cues.length, 1);
      expect(cues[0].start.inMilliseconds, 3723500);
    });

    test('handles empty VTT', () async {
      const content = 'WEBVTT\n\n';
      final cues = await parser.parse(content);
      expect(cues, isEmpty);
    });
  });

  group('AssParser', () {
    late AssParser parser;
    setUp(() { parser = AssParser(); });

    test('parses simple ASS dialogue', () async {
      const content = '[Script Info]\nTitle: Test\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:04.00,Default,,0,0,0,,Hello World\nDialogue: 0,0:00:05.00,0:00:08.00,Default,,0,0,0,,Second line\n';
      final cues = await parser.parse(content);
      expect(cues.length, 2);
      expect(cues[0].start.inMilliseconds, 1000);
      expect(cues[0].end.inMilliseconds, 4000);
      expect(cues[0].text, 'Hello World');
    });

    test('parses ASS with style override tags stripped', () async {
      const content = '[Script Info]\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:04.00,Default,,0,0,0,,{\\b1}Bold{\\b0} text\n';
      final cues = await parser.parse(content);
      expect(cues.length, 1);
      expect(cues[0].text, 'Bold text');
      expect(cues[0].style?.bold, isTrue);
    });

    test('parses ASS with color override', () async {
      const content = '[Script Info]\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:04.00,Default,,0,0,0,,{\\c&H0000FF&}Red text\n';
      final cues = await parser.parse(content);
      expect(cues.length, 1);
      expect(cues[0].style?.color, 0xFFFF0000);
    });

    test('handles ASS with no Events section', () async {
      const content = '[Script Info]\nTitle: Empty\n';
      final cues = await parser.parse(content);
      expect(cues, isEmpty);
    });
  });

  group('SubtitleParserFactory', () {
    test('creates SRT parser for .srt extension', () {
      final parser = SubtitleParserFactory.create('srt');
      expect(parser, isA<SrtParser>());
    });
    test('creates VTT parser for .vtt extension', () {
      final parser = SubtitleParserFactory.create('vtt');
      expect(parser, isA<VttParser>());
    });
    test('creates ASS parser for .ass extension', () {
      final parser = SubtitleParserFactory.create('ass');
      expect(parser, isA<AssParser>());
    });
    test('creates ASS parser for .ssa extension', () {
      final parser = SubtitleParserFactory.create('ssa');
      expect(parser, isA<AssParser>());
    });
    test('returns null for unknown format', () {
      final parser = SubtitleParserFactory.create('sub');
      expect(parser, isNull);
    });
  });
}
