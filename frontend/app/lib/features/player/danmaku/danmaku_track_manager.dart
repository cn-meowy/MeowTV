import 'dart:ui';
import 'danmaku_item.dart';

/// 弹幕轨道管理器 — 负责轨道分配和碰撞检测
class DanmakuTrackManager {
  int trackCount = 0;
  double trackHeight = 0;

  /// 每条轨道上最后一条滚动弹幕的右边缘 X 坐标和时间戳
  final List<_TrackSlot> _scrollTracks = [];

  /// 每条轨道上固定弹幕的结束时间
  final List<Duration?> _fixedTracks = [];

  /// 重新计算轨道数（容器尺寸变化时调用）
  void recalculate(Size containerSize, double fontSize) {
    trackHeight = fontSize * 1.5;
    trackCount = (containerSize.height / trackHeight).floor();
    if (trackCount < 1) trackCount = 1;

    while (_scrollTracks.length < trackCount) {
      _scrollTracks.add(_TrackSlot());
    }
    while (_scrollTracks.length > trackCount) {
      _scrollTracks.removeLast();
    }
    while (_fixedTracks.length < trackCount) {
      _fixedTracks.add(null);
    }
    while (_fixedTracks.length > trackCount) {
      _fixedTracks.removeLast();
    }
  }

  /// 为滚动弹幕分配轨道
  int? assignScrollTrack(
    DanmakuItem item,
    double canvasWidth,
    Duration currentPosition,
    double speed,
  ) {
    final itemWidth = item.measuredWidth ?? (item.content.length * item.style.fontSize * 0.6);

    for (var i = 0; i < trackCount; i++) {
      final slot = _scrollTracks[i];
      if (slot.isEmpty) {
        slot.lastRightEdge = canvasWidth + itemWidth;
        slot.lastTime = currentPosition;
        return i;
      }

      final elapsed = currentPosition.inMilliseconds - slot.lastTime!.inMilliseconds;
      final currentRight = slot.lastRightEdge! - (elapsed / 1000.0) * speed;

      if (currentRight <= canvasWidth - itemWidth * 0.5) {
        slot.lastRightEdge = canvasWidth + itemWidth;
        slot.lastTime = currentPosition;
        return i;
      }
    }
    return null;
  }

  /// 为顶部固定弹幕分配轨道
  int? assignTopFixedTrack(Duration currentPosition, Duration displayDuration) {
    final endTime = currentPosition + displayDuration;
    for (var i = 0; i < trackCount; i++) {
      final existingEnd = _fixedTracks[i];
      if (existingEnd == null || existingEnd <= currentPosition) {
        _fixedTracks[i] = endTime;
        return i;
      }
    }
    return null;
  }

  /// 为底部固定弹幕分配轨道
  int? assignBottomFixedTrack(Duration currentPosition, Duration displayDuration) {
    final endTime = currentPosition + displayDuration;
    for (var i = trackCount - 1; i >= 0; i--) {
      final existingEnd = _fixedTracks[i];
      if (existingEnd == null || existingEnd <= currentPosition) {
        _fixedTracks[i] = endTime;
        return i;
      }
    }
    return null;
  }

  /// 清除所有轨道状态
  void clear() {
    for (final slot in _scrollTracks) {
      slot.clear();
    }
    for (var i = 0; i < _fixedTracks.length; i++) {
      _fixedTracks[i] = null;
    }
  }
}

class _TrackSlot {
  double? lastRightEdge;
  Duration? lastTime;

  bool get isEmpty => lastRightEdge == null;

  void clear() {
    lastRightEdge = null;
    lastTime = null;
  }
}
