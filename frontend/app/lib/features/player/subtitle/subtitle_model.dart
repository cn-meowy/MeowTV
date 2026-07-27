// lib/features/player/subtitle/subtitle_model.dart

/// 字幕来源类型
enum SubtitleSource {
  embedded,  // 内嵌字幕轨道
  external,  // 外挂字幕文件
  online,    // 在线搜索下载
}

/// 字幕显示模式
enum SubtitleMode {
  off,       // 关闭
  embedded,  // 内嵌字幕
  external,  // 外挂字幕
  online,    // 在线字幕
}

/// 字幕对齐方式（独立于 Flutter Alignment）
enum SubtitleAlignment {
  topLeft,      topCenter,      topRight,
  centerLeft,   center,         centerRight,
  bottomLeft,   bottomCenter,   bottomRight,
}

/// 统一字幕样式
class SubtitleStyle {
  final int? color;            // 0xAARRGGBB
  final int? fontSize;
  final String? fontName;
  final SubtitleAlignment? alignment;
  final bool? bold;
  final bool? italic;
  final bool showStroke;
  final int strokeColor;       // 0xAARRGGBB
  final double strokeWidth;

  const SubtitleStyle({
    this.color,
    this.fontSize,
    this.fontName,
    this.alignment,
    this.bold,
    this.italic,
    this.showStroke = true,
    this.strokeColor = 0xFF000000,
    this.strokeWidth = 2.0,
  });

  const SubtitleStyle.defaults()
      : color = 0xFFFFFFFF,
        fontSize = 25,
        fontName = null,
        alignment = null,
        bold = null,
        italic = null,
        showStroke = true,
        strokeColor = 0xFF000000,
        strokeWidth = 2.0;

  SubtitleStyle copyWith({
    int? color,
    int? fontSize,
    String? fontName,
    SubtitleAlignment? alignment,
    bool? bold,
    bool? italic,
    bool? showStroke,
    int? strokeColor,
    double? strokeWidth,
  }) {
    return SubtitleStyle(
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      fontName: fontName ?? this.fontName,
      alignment: alignment ?? this.alignment,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      showStroke: showStroke ?? this.showStroke,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }

  Map<String, dynamic> toJson() => {
    'color': color,
    'fontSize': fontSize,
    'fontName': fontName,
    'bold': bold,
    'italic': italic,
    'showStroke': showStroke,
    'strokeColor': strokeColor,
    'strokeWidth': strokeWidth,
  };
}

/// 单条字幕
class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;
  final SubtitleStyle? style;

  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
    this.style,
  });

  /// 应用时间轴偏移
  SubtitleCue withOffset(Duration offset) {
    final newStart = start + offset;
    return SubtitleCue(
      start: newStart.isNegative ? Duration.zero : newStart,
      end: end + offset,
      text: text,
      style: style,
    );
  }

  Map<String, dynamic> toJson() => {
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'text': text,
    'style': style?.toJson(),
  };
}

/// 字幕轨道
class SubtitleTrack {
  final String id;
  final String label;
  final String language;
  final SubtitleSource source;
  final List<SubtitleCue> cues;

  const SubtitleTrack({
    required this.id,
    required this.label,
    required this.language,
    required this.source,
    required this.cues,
  });
}

/// 内嵌字幕轨道信息（从原生层返回）
class EmbeddedSubtitleTrack {
  final int index;
  final String label;
  final String language;

  const EmbeddedSubtitleTrack({
    required this.index,
    required this.label,
    required this.language,
  });
}

/// 在线字幕搜索查询
class SubtitleSearchQuery {
  final String? title;
  final String? episodeTitle;
  final int? season;
  final int? episode;
  final String? language;

  const SubtitleSearchQuery({
    this.title,
    this.episodeTitle,
    this.season,
    this.episode,
    this.language,
  });
}

/// 在线字幕搜索结果
class SubtitleSearchResult {
  final String id;
  final String sourceId;
  final String label;
  final String language;
  final String? downloadUrl;
  final Map<String, dynamic> metadata;

  const SubtitleSearchResult({
    required this.id,
    required this.sourceId,
    required this.label,
    required this.language,
    this.downloadUrl,
    this.metadata = const {},
  });
}

/// 在线字幕下载结果
class SubtitleDownloadResult {
  final String content;
  final String format; // "srt" / "vtt" / "ass"

  const SubtitleDownloadResult({
    required this.content,
    required this.format,
  });
}
