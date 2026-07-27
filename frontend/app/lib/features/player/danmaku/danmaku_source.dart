/// 弹幕数据请求
class DanmakuFetchRequest {
  final String? title;
  final int? episode;
  final String? episodeTitle;
  final Duration? duration;

  const DanmakuFetchRequest({
    this.title,
    this.episode,
    this.episodeTitle,
    this.duration,
  });
}

/// 弹幕数据源结果
class DanmakuSourceResult {
  final dynamic rawData;       // 原始数据（格式取决于 source）
  final String format;         // 数据格式标识，如 "bilibili-xml"

  const DanmakuSourceResult({
    required this.rawData,
    required this.format,
  });
}

/// 弹幕数据源接口（可插拔）
abstract class DanmakuSource {
  /// 唯一标识
  String get id;

  /// 显示名称
  String get displayName;

  /// 获取弹幕数据（返回原始格式，由转换层处理）
  Future<DanmakuSourceResult?> fetch(DanmakuFetchRequest request);

  /// 支持的数据格式标识（用于匹配转换器）
  String get outputFormat;
}
