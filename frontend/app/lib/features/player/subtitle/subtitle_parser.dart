// lib/features/player/subtitle/subtitle_parser.dart

import 'subtitle_model.dart';

/// Abstract base class for subtitle parsers.
abstract class SubtitleParser {
  /// Parses subtitle content into a list of [SubtitleCue]s.
  Future<List<SubtitleCue>> parse(String content);
}

/// Factory to create the appropriate parser based on format.
class SubtitleParserFactory {
  /// Creates a parser for the given format string (e.g. 'srt', 'vtt', 'ass').
  static SubtitleParser? create(String format) {
    switch (format.toLowerCase()) {
      case 'srt':
        return SrtParser();
      case 'vtt':
        return VttParser();
      case 'ass':
      case 'ssa':
        return AssParser();
      default:
        return null;
    }
  }

  /// Detects the format from a filename and creates the appropriate parser.
  static SubtitleParser? detectFormat(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return create(ext);
  }
}

// ---------------------------------------------------------------------------
// SRT Parser
// ---------------------------------------------------------------------------

/// Parser for SubRip (.srt) subtitle format.
class SrtParser extends SubtitleParser {
  static final _timestampRegex =
      RegExp(r'(\d{2}):(\d{2}):(\d{2}),(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2}),(\d{3})');

  @override
  Future<List<SubtitleCue>> parse(String content) async {
    if (content.trim().isEmpty) return [];

    final cues = <SubtitleCue>[];
    // Split by double newline (blank line) to get individual entries
    final blocks = content.trim().split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 2) continue;

      // Find the timestamp line (skip index line if present)
      int tsLineIndex = -1;
      for (int i = 0; i < lines.length; i++) {
        if (_timestampRegex.hasMatch(lines[i])) {
          tsLineIndex = i;
          break;
        }
      }

      if (tsLineIndex < 0) continue; // malformed entry, skip

      final match = _timestampRegex.firstMatch(lines[tsLineIndex])!;
      final start = _parseSrtTimestamp(match);
      final end = _parseSrtTimestamp(match, groupOffset: 4);

      // Text is everything after the timestamp line
      final text = lines.sublist(tsLineIndex + 1).join('\n').trim();
      if (text.isEmpty) continue;

      cues.add(SubtitleCue(start: start, end: end, text: text));
    }

    return cues;
  }

  Duration _parseSrtTimestamp(RegExpMatch match, {int groupOffset = 0}) {
    final hours = int.parse(match[groupOffset + 1]!);
    final minutes = int.parse(match[groupOffset + 2]!);
    final seconds = int.parse(match[groupOffset + 3]!);
    final millis = int.parse(match[groupOffset + 4]!);
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }
}

// ---------------------------------------------------------------------------
// VTT Parser
// ---------------------------------------------------------------------------

/// Parser for WebVTT (.vtt) subtitle format.
class VttParser extends SubtitleParser {
  static final _timestampRegex =
      RegExp(r'(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})\.(\d{3})');
  // VTT timestamps can also be MM:SS.mmm (no hours)
  static final _shortTimestampRegex =
      RegExp(r'(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(\d{2}):(\d{2})\.(\d{3})');

  @override
  Future<List<SubtitleCue>> parse(String content) async {
    if (content.trim().isEmpty) return [];

    // Strip WEBVTT header
    var body = content;
    if (body.startsWith('WEBVTT')) {
      body = body.substring(6);
      // Skip header metadata until first blank line
      final headerEnd = body.indexOf('\n\n');
      if (headerEnd >= 0) {
        body = body.substring(headerEnd + 2);
      }
    }

    // Remove STYLE blocks
    body = body.replaceAll(RegExp(r'STYLE\s*\n[^]*?(?=\n\n|\z)'), '');

    final cues = <SubtitleCue>[];
    final blocks = body.trim().split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      final trimmed = block.trim();
      if (trimmed.isEmpty) continue;

      final lines = trimmed.split('\n');
      int tsLineIndex = -1;
      RegExpMatch? tsMatch;

      for (int i = 0; i < lines.length; i++) {
        final m = _timestampRegex.firstMatch(lines[i]);
        if (m != null) {
          tsLineIndex = i;
          tsMatch = m;
          break;
        }
        final sm = _shortTimestampRegex.firstMatch(lines[i]);
        if (sm != null) {
          tsLineIndex = i;
          tsMatch = sm;
          break;
        }
      }

      if (tsLineIndex < 0 || tsMatch == null) continue;

      final isShort = _shortTimestampRegex == tsMatch.pattern;
      Duration start;
      Duration end;

      if (isShort) {
        start = _parseVttShortTimestamp(tsMatch);
        end = _parseVttShortTimestamp(tsMatch, groupOffset: 3);
      } else {
        start = _parseVttTimestamp(tsMatch);
        end = _parseVttTimestamp(tsMatch, groupOffset: 4);
      }

      // Text lines after timestamp, strip HTML tags
      var text = lines
          .sublist(tsLineIndex + 1)
          .join('\n')
          .trim()
          .replaceAll(RegExp(r'<[^>]*>'), '');

      if (text.isEmpty) continue;

      cues.add(SubtitleCue(start: start, end: end, text: text));
    }

    return cues;
  }

  Duration _parseVttTimestamp(RegExpMatch match, {int groupOffset = 0}) {
    final hours = int.parse(match[groupOffset + 1]!);
    final minutes = int.parse(match[groupOffset + 2]!);
    final seconds = int.parse(match[groupOffset + 3]!);
    final millis = int.parse(match[groupOffset + 4]!);
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }

  Duration _parseVttShortTimestamp(RegExpMatch match, {int groupOffset = 0}) {
    final minutes = int.parse(match[groupOffset + 1]!);
    final seconds = int.parse(match[groupOffset + 2]!);
    final millis = int.parse(match[groupOffset + 3]!);
    return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
  }
}

// ---------------------------------------------------------------------------
// ASS/SSA Parser
// ---------------------------------------------------------------------------

/// Parser for Advanced SubStation Alpha (.ass) / SubStation Alpha (.ssa) format.
class AssParser extends SubtitleParser {
  static final _assTimestampRegex =
      RegExp(r'(\d+):(\d{2}):(\d{2})\.(\d{2})');

  @override
  Future<List<SubtitleCue>> parse(String content) async {
    if (content.trim().isEmpty) return [];

    final cues = <SubtitleCue>[];

    // Find [Events] section
    final eventsStart = content.indexOf('[Events]');
    if (eventsStart < 0) return cues;

    // Find the end of [Events] section (next section or end of file)
    final nextSection = content.indexOf(RegExp(r'\n\['), eventsStart + 8);
    final eventsSection = nextSection > 0
        ? content.substring(eventsStart, nextSection)
        : content.substring(eventsStart);

    // Parse Format line to determine field indices
    final formatMatch =
        RegExp(r'Format:\s*(.*)', caseSensitive: false).firstMatch(eventsSection);
    if (formatMatch == null) return cues;

    final formatFields = formatMatch
        .group(1)!
        .split(',')
        .map((f) => f.trim().toLowerCase())
        .toList();

    final startIndex = formatFields.indexOf('start');
    final endIndex = formatFields.indexOf('end');
    final textIndex = formatFields.indexOf('text');

    if (startIndex < 0 || endIndex < 0 || textIndex < 0) return cues;

    // Parse Dialogue lines
    final dialogueRegex = RegExp(r'Dialogue:\s*(.*)', caseSensitive: false);
    for (final match in dialogueRegex.allMatches(eventsSection)) {
      final dialogueText = match.group(1)!;
      final fields = _splitAssDialogue(dialogueText);

      if (fields.length <= textIndex) continue;

      final startStr = fields[startIndex].trim();
      final endStr = fields[endIndex].trim();

      final startMatch = _assTimestampRegex.firstMatch(startStr);
      final endMatch = _assTimestampRegex.firstMatch(endStr);
      if (startMatch == null || endMatch == null) continue;

      final start = _parseAssTimestamp(startMatch);
      final end = _parseAssTimestamp(endMatch);

      // Text field: everything from textIndex onward (joined, as text may contain commas)
      final rawText = fields.sublist(textIndex).join(',').trim();

      // Process override tags and extract style info
      final processed = _processAssText(rawText);

      // Build style from extracted overrides
      SubtitleStyle? style;
      if (processed.bold != null || processed.italic != null || processed.color != null) {
        style = SubtitleStyle(
          bold: processed.bold,
          italic: processed.italic,
          color: processed.color,
        );
      }

      cues.add(SubtitleCue(
        start: start,
        end: end,
        text: processed.text,
        style: style,
      ));
    }

    return cues;
  }

  /// Split ASS dialogue line by commas, respecting that the Text field may
  /// contain commas (so we only split up to the text field index).
  List<String> _splitAssDialogue(String dialogueText) {
    // We need at least textIndex + 1 fields, but the text field itself
    // may contain commas. Split all and let caller join from textIndex.
    return dialogueText.split(',');
  }

  /// Parse ASS timestamp H:MM:SS.cc (centiseconds)
  Duration _parseAssTimestamp(RegExpMatch match) {
    final hours = int.parse(match[1]!);
    final minutes = int.parse(match[2]!);
    final seconds = int.parse(match[3]!);
    final centiseconds = int.parse(match[4]!);
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: centiseconds * 10,
    );
  }

  /// Process ASS text: strip override tags, extract style hints.
  _AssTextResult _processAssText(String rawText) {
    var text = rawText;
    bool? bold;
    bool? italic;
    int? color;

    // Replace \N with newline (ASS line break)
    text = text.replaceAll(r'\N', '\n');
    text = text.replaceAll(r'\n', '\n');

    // Extract style overrides before stripping
    if (text.contains(r'\b1')) bold = true;
    if (text.contains(r'\i1')) italic = true;

    // Extract color override: \c&HBBGGRR&
    final colorMatch = RegExp(r'\\c&H([0-9A-Fa-f]{6})&').firstMatch(text);
    if (colorMatch != null) {
      color = _assColorToArgb(colorMatch[1]!);
    }

    // Strip all override tags: {\...}
    text = text.replaceAll(RegExp(r'\{[^}]*\}'), '');

    return _AssTextResult(text: text, bold: bold, italic: italic, color: color);
  }

  /// Convert ASS BGR color string to ARGB int.
  /// ASS stores color as &HBBGGRR&, we need 0xAARRGGBB.
  int _assColorToArgb(String bgrHex) {
    final bb = int.parse(bgrHex.substring(0, 2), radix: 16);
    final gg = int.parse(bgrHex.substring(2, 4), radix: 16);
    final rr = int.parse(bgrHex.substring(4, 6), radix: 16);
    return 0xFF000000 | (rr << 16) | (gg << 8) | bb;
  }
}

/// Helper class for ASS text processing results.
class _AssTextResult {
  final String text;
  final bool? bold;
  final bool? italic;
  final int? color;

  const _AssTextResult({
    required this.text,
    this.bold,
    this.italic,
    this.color,
  });
}
