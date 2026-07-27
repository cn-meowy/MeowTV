import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../../../core/logger/app_logger.dart';
import 'danmaku_item.dart';
import 'danmaku_source.dart';
import 'danmaku_converter.dart';
import 'danmaku_track_manager.dart';

/// 弹幕控制器
class DanmakuController extends ChangeNotifier {
  final DanmakuConverterFactory _converterFactory = DanmakuConverterFactory();
  final DanmakuTrackManager trackManager = DanmakuTrackManager();

  List<DanmakuItem> _allItems = [];
  List<DanmakuItem> activeItems = [];

  bool isEnabled = true;
  double speed = 1.0;
  double opacity = 1.0;
  double fontSizeScale = 1.0;
  int maxDensity = 0;
  DanmakuDisplayArea displayArea = DanmakuDisplayArea.full;
  DanmakuFilter filter = const DanmakuFilter();

  static const fixedDisplayDuration = Duration(seconds: 5);
  static const baseSpeed = 120.0;

  Duration currentPosition = Duration.zero;
  bool _isPlaying = false;

  DanmakuController() {
    _converterFactory.registerDefaults();
  }

  void loadItems(List<DanmakuItem> items) {
    _allItems = List.from(items);
    _allItems.sort((a, b) => a.startTime.compareTo(b.startTime));
    appLogger.i('[Danmaku] 加载 ${items.length} 条弹幕');
    notifyListeners();
  }

  Future<void> loadFromSource(DanmakuSource source, DanmakuFetchRequest request) async {
    try {
      final result = await source.fetch(request);
      if (result == null) {
        appLogger.w('[Danmaku] 数据源 ${source.id} 返回空');
        return;
      }
      final converter = _converterFactory.get(result.format);
      if (converter == null) {
        appLogger.w('[Danmaku] 未注册的格式: ${result.format}');
        return;
      }
      final items = converter.convert(result.rawData);
      loadItems(items);
    } catch (e) {
      appLogger.e('[Danmaku] 加载弹幕失败', error: e);
    }
  }

  void play() {
    _isPlaying = true;
  }

  void pause() {
    _isPlaying = false;
  }

  void seekTo(Duration position) {
    currentPosition = position;
    activeItems.clear();
    trackManager.clear();
    notifyListeners();
  }

  void updatePosition(Duration position, Size canvasSize) {
    currentPosition = position;
    if (!_isPlaying || !isEnabled || _allItems.isEmpty) return;

    final effectiveFontSize = 25.0 * fontSizeScale;
    trackManager.recalculate(canvasSize, effectiveFontSize);
    _updateActiveItems(position, canvasSize);
  }

  void _updateActiveItems(Duration position, Size canvasSize) {
    // 移除离开屏幕的弹幕
    activeItems.removeWhere((item) {
      if (item.mode == DanmakuMode.scroll) {
        if (item.currentX != null && item.measuredWidth != null) {
          return item.currentX! + item.measuredWidth! < 0;
        }
      } else {
        if (position - item.startTime > fixedDisplayDuration) {
          return true;
        }
      }
      return false;
    });

    if (maxDensity > 0 && activeItems.length >= maxDensity) {
      notifyListeners();
      return;
    }

    for (final item in _allItems) {
      if (activeItems.any((a) => a.id == item.id)) continue;
      final diff = position.inMilliseconds - item.startTime.inMilliseconds;
      if (diff < 0 || diff > 100) continue;
      if (!_passesFilter(item)) continue;
      _assignTrack(item, canvasSize, position);
      if (item.assignedTrack != null) {
        activeItems.add(item);
      }
    }

    final scrollSpeed = baseSpeed * speed;
    for (final item in activeItems) {
      if (item.mode == DanmakuMode.scroll) {
        final elapsed = (position.inMilliseconds - item.startTime.inMilliseconds) / 1000.0;
        item.currentX = canvasSize.width - elapsed * scrollSpeed;
      }
    }

    notifyListeners();
  }

  bool _passesFilter(DanmakuItem item) {
    if (item.mode == DanmakuMode.scroll && !filter.scrollEnabled) return false;
    if (item.mode == DanmakuMode.topFixed && !filter.topFixedEnabled) return false;
    if (item.mode == DanmakuMode.bottomFixed && !filter.bottomFixedEnabled) return false;
    if (filter.blockColors.contains(item.style.color & 0x00FFFFFF)) return false;
    if (item.style.fontSize < filter.minFontSize || item.style.fontSize > filter.maxFontSize) return false;
    return true;
  }

  void _assignTrack(DanmakuItem item, Size canvasSize, Duration position) {
    final scrollSpeed = baseSpeed * speed;
    switch (item.mode) {
      case DanmakuMode.scroll:
        final track = trackManager.assignScrollTrack(item, canvasSize.width, position, scrollSpeed);
        if (track != null) {
          item.assignedTrack = track;
          item.currentY = track * trackManager.trackHeight;
          item.currentX = canvasSize.width;
        }
      case DanmakuMode.topFixed:
        final track = trackManager.assignTopFixedTrack(position, fixedDisplayDuration);
        if (track != null) {
          item.assignedTrack = track;
          item.currentY = track * trackManager.trackHeight;
          item.currentX = 0;
        }
      case DanmakuMode.bottomFixed:
        final track = trackManager.assignBottomFixedTrack(position, fixedDisplayDuration);
        if (track != null) {
          item.assignedTrack = track;
          item.currentY = track * trackManager.trackHeight;
          item.currentX = 0;
        }
    }
  }

  void setFilter(DanmakuFilter newFilter) {
    filter = newFilter;
    notifyListeners();
  }

  /// 通知 UI 更新（公开接口，供外部 widget 修改属性后调用）
  void notifyUI() {
    notifyListeners();
  }

  void reset({bool notify = true}) {
    _allItems = [];
    activeItems.clear();
    trackManager.clear();
    currentPosition = Duration.zero;
    if (notify) notifyListeners();
  }

  bool get hasData => _allItems.isNotEmpty;
}
