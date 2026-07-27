import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'quality_level.dart';

/// 自适应码率控制器
class ABRController {
  final List<double> _segmentDownloadSpeeds = [];
  DateTime? _lastSwitchTime;
  static const _minSwitchInterval = Duration(seconds: 30);
  static const _maxSpeedSamples = 5;

  /// 记录 segment 下载速度
  void recordSegmentSpeed(double bytesPerSecond, int segmentBitrate) {
    _segmentDownloadSpeeds.add(bytesPerSecond);
    if (_segmentDownloadSpeeds.length > _maxSpeedSamples) {
      _segmentDownloadSpeeds.removeAt(0);
    }
  }

  /// 根据网络状况评估推荐清晰度
  QualityLevel? evaluate(List<QualityLevel> levels, ConnectivityResult connectivity) {
    if (levels.isEmpty) return null;
    if (!_canSwitch()) return null;

    final bandwidth = estimateBandwidth(connectivity);
    final targetBandwidth = bandwidth * 0.7; // 留 30% 缓冲余量

    // 按带宽从低到高排序，找最接近但不超过的清晰度
    final sorted = List<QualityLevel>.from(levels)
      ..sort((a, b) => a.bandwidth.compareTo(b.bandwidth));

    QualityLevel? selected;
    for (final level in sorted) {
      if (level.bandwidth <= targetBandwidth) {
        selected = level;
      }
    }
    return selected ?? sorted.first; // 兜底选最低
  }

  /// 带宽估算：结合 segment 下载速度和网络类型
  double estimateBandwidth(ConnectivityResult connectivity) {
    final segmentBandwidth = _calcSegmentDownloadSpeed();

    final double typeBandwidth;
    switch (connectivity) {
      case ConnectivityResult.wifi:
        typeBandwidth = double.infinity; // WiFi 不限
      case ConnectivityResult.mobile:
        typeBandwidth = 5_000_000.0; // 蜂窝假设 5Mbps
      case ConnectivityResult.ethernet:
        typeBandwidth = double.infinity;
      default:
        typeBandwidth = 2_000_000.0; // 其他假设 2Mbps
    }

    return min(segmentBandwidth, typeBandwidth);
  }

  /// 计算最近 N 个 segment 的平均下载速度
  double _calcSegmentDownloadSpeed() {
    if (_segmentDownloadSpeeds.isEmpty) return 10_000_000.0; // 默认 10Mbps
    return _segmentDownloadSpeeds.reduce((a, b) => a + b) /
        _segmentDownloadSpeeds.length;
  }

  /// 检查是否可以切换（防抖：最短间隔 30 秒）
  bool _canSwitch() {
    final now = DateTime.now();
    if (_lastSwitchTime == null) return true;
    return now.difference(_lastSwitchTime!) >= _minSwitchInterval;
  }

  /// 标记已切换
  void markSwitched() {
    _lastSwitchTime = DateTime.now();
  }

  /// 重置状态
  void reset() {
    _segmentDownloadSpeeds.clear();
    _lastSwitchTime = null;
  }
}
