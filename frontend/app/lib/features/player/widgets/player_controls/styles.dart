import 'package:flutter/material.dart';

/// B站风格播放器控件样式常量
class PlayerControlsStyles {
  PlayerControlsStyles._();

  // ─── 配色 ──────────────────────────────────────────────────────────────────

  /// 进度条已播放部分（B站粉）
  static const Color progressPlayed = Color(0xFFFB7299);

  /// 进度条缓冲部分
  static const Color progressBuffered = Color(0x4DFFFFFF);

  /// 进度条底色
  static const Color progressTrack = Color(0x33FFFFFF);

  /// 进度条拖拽 thumb
  static const Color progressThumb = Color(0xFFFB7299);

  /// 控制栏背景渐变（顶部/底部）
  static const Color gradientStart = Colors.transparent;
  static const Color gradientEnd = Color(0xB3000000);

  /// 按钮图标颜色
  static const Color iconColor = Colors.white;

  /// 文字颜色
  static const Color textColor = Colors.white;

  /// 次要文字颜色
  static const Color textSecondary = Color(0xCCFFFFFF);

  /// 手势反馈背景
  static const Color gestureBg = Color(0x66000000);

  /// 倍速面板背景
  static const Color panelBg = Color(0xCC1c1c1e);

  /// 倍速选中色
  static const Color speedActive = Color(0xFFFB7299);

  /// 倍速未选中色
  static const Color speedInactive = Color(0xCCFFFFFF);

  // ─── 尺寸 ──────────────────────────────────────────────────────────────────

  /// 进度条高度
  static const double progressBarHeight = 3.0;

  /// 进度条拖拽时高度
  static const double progressBarDragHeight = 5.0;

  /// 进度条 thumb 大小
  static const double progressThumbSize = 12.0;

  /// 进度条拖拽时 thumb 大小
  static const double progressThumbDragSize = 16.0;

  /// 控制栏高度（上下）
  static const double controlBarHeight = 44.0;

  /// 按钮大小（底部控制栏所有图标统一尺寸，与顶部投屏图标一致）
  static const double iconSize = 24.0;

  /// 手势反馈图标大小
  static const double gestureIconSize = 36.0;

  /// 手势反馈文字大小
  static const double gestureTextSize = 13.0;

  /// 时间文字大小
  static const double timeTextSize = 12.0;

  /// 标题文字大小
  static const double titleTextSize = 16.0;

  // ─── 动画 ──────────────────────────────────────────────────────────────────

  /// 控制栏自动隐藏时间
  static const Duration autoHideDelay = Duration(seconds: 5);

  /// 投屏期顶部滚动提示条文字移动速度（px/s）
  static const double castBannerScrollSpeed = 30.0;

  /// 控制栏显示/隐藏动画时长
  static const Duration controlsAnimDuration = Duration(milliseconds: 300);

  /// 手势反馈动画时长
  static const Duration gestureAnimDuration = Duration(milliseconds: 200);

  /// 双击快进/快退秒数
  static const Duration seekDuration = Duration(seconds: 10);

  /// 长按倍速
  static const double longPressSpeed = 2.0;

  // ─── 倍速选项 ──────────────────────────────────────────────────────────────

  static const List<double> speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0];

  // ─── 投屏 ──────────────────────────────────────────────────────────────────

  /// 投屏未连接图标颜色
  static const Color castInactive = Color(0x99FFFFFF);

  /// 投屏连接中图标颜色
  static const Color castActive = Color(0xFFFB7299);

  // ─── 字幕 ──────────────────────────────────────────────────────────────────

  /// 字幕未激活图标颜色
  static const Color subtitleInactive = Color(0x99FFFFFF);

  /// 字幕激活图标颜色
  static const Color subtitleActive = Color(0xFFFB7299);

  /// 字幕倍速文字大小
  static const double speedTextSize = 12.0;

  // ─── 清晰度 ────────────────────────────────────────────────────────────────

  /// 清晰度按钮文字大小
  static const double qualityTextSize = 12.0;

  /// 清晰度未激活颜色
  static const Color qualityInactive = Color(0x99FFFFFF);

  /// 清晰度激活颜色
  static const Color qualityActive = Color(0xFFFB7299);

  /// 清晰度面板宽度
  static const double qualityPanelWidth = 200.0;

  /// 清晰度面板最大高度
  static const double qualityPanelMaxHeight = 400.0;

  // ─── 弹幕 ────────────────────────────────────────────────────────────────

  /// 弹幕未激活图标颜色
  static const Color danmakuInactive = Color(0x99FFFFFF);

  /// 弹幕激活图标颜色
  static const Color danmakuActive = Color(0xFFFB7299);

  /// 弹幕面板宽度
  static const double danmakuPanelWidth = 260.0;

  /// 弹幕面板最大高度
  static const double danmakuPanelMaxHeight = 460.0;

  // ─── 面板自适应缩放 ──────────────────────────────────────────────────────

  /// 面板缩放基准宽度（播放器宽度 ≥ 此值时不缩放）
  static const double panelScaleBase = 400.0;

  /// 缩放最小系数（控制栏和面板统一）
  static const double panelScaleMin = 0.75;

  /// 根据播放器宽度计算缩放系数（控制栏和面板统一使用）
  static double controlScale(double playerWidth) {
    return (playerWidth / panelScaleBase).clamp(panelScaleMin, 1.0);
  }

  /// 带最小值保护的通用尺寸缩放
  static double scaledSize(double base, double scale, [double min = 0.0]) {
    final upper = base < min ? min : base;
    return (base * scale).clamp(min, upper);
  }

  /// 缩放后的字号（最小 9px）
  ///
  /// 当 [base] 小于最小下限时，上界取下限值，避免 clamp 参数反转抛
  /// ArgumentError（参见 subtitle_panel.dart / danmaku_panel.dart 中
  /// base=2 的小间距调用）。
  static double scaledFontSize(double base, double scale) {
    final upper = base < 9.0 ? 9.0 : base;
    return (base * scale).clamp(9.0, upper);
  }

  /// 缩放后的 padding（最小 3px）
  ///
  /// 当 [base] 小于最小下限时，上界取下限值，避免 clamp 参数反转抛
  /// ArgumentError（参见 subtitle_panel.dart / danmaku_panel.dart 中
  /// base=2 的小间距调用）。
  static double scaledPadding(double base, double scale) {
    final upper = base < 3.0 ? 3.0 : base;
    return (base * scale).clamp(3.0, upper);
  }

  /// 缩放后的面板宽度（不超过播放器宽度 - 16）
  static double scaledWidth(double naturalWidth, double playerWidth) {
    return naturalWidth.clamp(0.0, playerWidth - 16);
  }

  /// 上方弹窗（More/Cast）的最大高度
  static double topPanelMaxHeight(double playerHeight) {
    return (playerHeight - controlBarHeight - 12).clamp(0.0, double.infinity);
  }

  /// 下方弹窗的最大高度
  static double bottomPanelMaxHeight(double playerHeight) {
    return (playerHeight - controlBarHeight - 20).clamp(0.0, double.infinity);
  }
}
