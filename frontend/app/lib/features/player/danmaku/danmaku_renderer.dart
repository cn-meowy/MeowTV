import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'danmaku_item.dart';
import 'danmaku_track_manager.dart';

/// 弹幕 Canvas 渲染器
class DanmakuRenderer extends CustomPainter {
  final List<DanmakuItem> activeItems;
  final Duration videoPosition;
  final double speed;
  final double opacity;
  final double fontSizeScale;
  final DanmakuDisplayArea displayArea;
  final DanmakuTrackManager trackManager;

  DanmakuRenderer({
    required this.activeItems,
    required this.videoPosition,
    required this.speed,
    required this.opacity,
    required this.fontSizeScale,
    required this.displayArea,
    required this.trackManager,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (activeItems.isEmpty || size.isEmpty) return;

    final areaRect = _getDisplayArea(size);
    canvas.save();
    canvas.clipRect(areaRect);

    for (final item in activeItems) {
      if (item.currentX == null || item.currentY == null) continue;

      final x = item.currentX!;
      final y = item.currentY!;
      final fontSize = (item.style.fontSize * fontSizeScale).roundToDouble();

      // 视口裁剪
      if (x + 400 < 0 || x > size.width) continue;
      if (y + fontSize < areaRect.top || y > areaRect.bottom) continue;

      final textColor = Color(item.style.color)
          .withValues(alpha: item.style.opacity * opacity);

      // 固定弹幕居中
      double drawX = x;
      if (item.mode == DanmakuMode.topFixed || item.mode == DanmakuMode.bottomFixed) {
        // 使用 measuredWidth 居中
        final w = item.measuredWidth ?? 200.0;
        drawX = (size.width - w) / 2;
      }

      // 描边
      if (item.style.showStroke) {
        final strokeColor = Color(item.style.strokeColor)
            .withValues(alpha: item.style.opacity * opacity);
        final strokeBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: TextAlign.left,
          fontSize: fontSize,
        ))..pushStyle(ui.TextStyle(
          color: strokeColor,
          fontSize: fontSize,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = item.style.strokeWidth
            ..color = strokeColor,
        ))..addText(item.content);

        final strokeParagraph = strokeBuilder.build()
          ..layout(ui.ParagraphConstraints(width: size.width));
        canvas.drawParagraph(strokeParagraph, Offset(drawX, y));
      }

      // 填充文字
      final textBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: fontSize,
      ))..pushStyle(ui.TextStyle(
        color: textColor,
        fontSize: fontSize,
      ))..addText(item.content);

      final textParagraph = textBuilder.build()
        ..layout(ui.ParagraphConstraints(width: size.width));
      canvas.drawParagraph(textParagraph, Offset(drawX, y));
    }

    canvas.restore();
  }

  Rect _getDisplayArea(Size size) {
    switch (displayArea) {
      case DanmakuDisplayArea.full:
        return Rect.fromLTWH(0, 0, size.width, size.height);
      case DanmakuDisplayArea.topHalf:
        return Rect.fromLTWH(0, 0, size.width, size.height / 2);
      case DanmakuDisplayArea.bottomHalf:
        return Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2);
      case DanmakuDisplayArea.quarterTop:
        return Rect.fromLTWH(0, 0, size.width, size.height / 4);
    }
  }

  @override
  bool shouldRepaint(covariant DanmakuRenderer oldDelegate) => true;
}
