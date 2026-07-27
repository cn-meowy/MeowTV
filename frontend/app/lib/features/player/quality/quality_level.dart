import '../../../core/stream/stream_config.dart';

/// 清晰度等级模型
class QualityLevel {
  final String id;             // variant 唯一标识
  final String label;          // 显示名称，如"1080P"、"720P"
  final int bandwidth;         // 带宽 (bps)
  final int width;             // 视频宽度
  final int height;            // 视频高度
  final String? codec;         // 视频编码
  final String url;            // variant playlist URL
  final double frameRate;      // 帧率

  const QualityLevel({
    required this.id,
    required this.label,
    required this.bandwidth,
    required this.width,
    required this.height,
    this.codec,
    required this.url,
    this.frameRate = 0.0,
  });

  /// 自动生成标签
  String get autoLabel {
    if (height >= 2160) return '4K';
    if (height >= 1080) return '1080P';
    if (height >= 720) return '720P';
    if (height >= 480) return '480P';
    if (height >= 360) return '360P';
    return '${height}P';
  }

  /// 带宽显示文本
  String get bandwidthLabel {
    final kbps = bandwidth ~/ 1000;
    if (kbps >= 1000) {
      return '${kbps ~/ 1000}Mbps';
    }
    return '${kbps}kbps';
  }
}

/// 清晰度模式
enum QualityMode {
  auto,     // 自适应（ABR）
  manual,   // 手动选择
}

/// 清晰度偏好
enum QualityPreference {
  auto,       // 自适应
  highest,    // 最高清晰度
  medium,     // 中等清晰度
  lowest,     // 最低清晰度（省流量）
  specific,   // 指定清晰度
}

/// VariantInfo → QualityLevel 映射扩展
extension VariantInfoToQuality on VariantInfo {
  QualityLevel toQualityLevel() {
    final h = height ?? _parseHeight(resolution);
    return QualityLevel(
      id: '${bandwidth}_$resolution',
      label: name ?? _autoLabel(h),
      bandwidth: bandwidth,
      width: width ?? _parseWidth(resolution) ?? 0,
      height: h ?? 0,
      codec: codec,
      url: uri,
      frameRate: frameRate ?? 0.0,
    );
  }
}

// Helper functions for VariantInfoToQuality extension
String _autoLabel(int? height) {
  if (height == null) return '未知';
  if (height >= 2160) return '4K';
  if (height >= 1080) return '1080P';
  if (height >= 720) return '720P';
  if (height >= 480) return '480P';
  if (height >= 360) return '360P';
  return '${height}P';
}

int? _parseHeight(String resolution) {
  if (resolution.isEmpty) return null;
  final parts = resolution.split('x');
  if (parts.length == 2) return int.tryParse(parts[1]);
  return null;
}

int? _parseWidth(String resolution) {
  if (resolution.isEmpty) return null;
  final parts = resolution.split('x');
  if (parts.length == 2) return int.tryParse(parts[0]);
  return null;
}
