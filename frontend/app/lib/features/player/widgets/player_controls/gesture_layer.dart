import 'package:flutter/material.dart';

/// 手势检测层
///
/// 处理：单击（显示/隐藏控件）、双击（暂停/播放）、
/// 水平滑动（快进/快退）、垂直滑动（左=亮度，右=音量）、长按（2x倍速）。
class GestureLayer extends StatelessWidget {
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;
  final VoidCallback onHorizontalSeekStart;
  final void Function(Duration delta) onHorizontalSeekUpdate;
  final void Function(Duration totalDelta) onHorizontalSeekEnd;
  final void Function(bool isRight) onVerticalStart;
  final void Function(double delta) onVerticalUpdate;
  final VoidCallback onVerticalEnd;
  final Widget child;

  const GestureLayer({
    super.key,
    required this.onSingleTap,
    required this.onDoubleTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onHorizontalSeekStart,
    required this.onHorizontalSeekUpdate,
    required this.onHorizontalSeekEnd,
    required this.onVerticalStart,
    required this.onVerticalUpdate,
    required this.onVerticalEnd,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSingleTap,
      onDoubleTapDown: (_) => onDoubleTap(),
      onLongPressStart: (_) => onLongPressStart(),
      onLongPressEnd: (_) => onLongPressEnd(),
      onHorizontalDragStart: (_) => onHorizontalSeekStart(),
      onHorizontalDragUpdate: (details) {
        // 每 px 约等于 1 秒
        final px = details.primaryDelta ?? 0;
        if (px != 0) {
          onHorizontalSeekUpdate(Duration(seconds: px.round()));
        }
      },
      onHorizontalDragEnd: (_) {
        // 累积的 delta 由 controls_overlay 管理
        onHorizontalSeekEnd(Duration.zero);
      },
      onVerticalDragStart: (details) {
        final midX = context.size?.width ?? 0;
        onVerticalStart(details.localPosition.dx > midX / 2);
      },
      onVerticalDragUpdate: (details) {
        final boxH = context.size?.height ?? 1;
        if (boxH > 0) {
          final delta = -(details.primaryDelta ?? 0) / boxH;
          onVerticalUpdate(delta);
        }
      },
      onVerticalDragEnd: (_) => onVerticalEnd(),
      child: child,
    );
  }
}
