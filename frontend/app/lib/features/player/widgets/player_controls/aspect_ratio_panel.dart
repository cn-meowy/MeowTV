import 'package:flutter/material.dart';
import 'styles.dart';

/// 画面比例选项
enum DisplayAspectRatio {
  ratio16_9,   // 16:9
  ratio4_3,    // 4:3
  ratio9_16,   // 9:16
  reset,       // 还原（恢复当前模式默认比例）
  fill,        // 填充拉伸（裁剪填满屏幕）
  autoAdapt;   // 自适应（视频原始比例）

  double? get value {
    switch (this) {
      case DisplayAspectRatio.ratio16_9:
        return 16 / 9;
      case DisplayAspectRatio.ratio4_3:
        return 4 / 3;
      case DisplayAspectRatio.ratio9_16:
        return 9 / 16;
      case DisplayAspectRatio.reset:
        return null;
      case DisplayAspectRatio.fill:
        return null;
      case DisplayAspectRatio.autoAdapt:
        return null;
    }
  }

  String get label {
    switch (this) {
      case DisplayAspectRatio.ratio16_9:
        return '16:9';
      case DisplayAspectRatio.ratio4_3:
        return '4:3';
      case DisplayAspectRatio.ratio9_16:
        return '9:16';
      case DisplayAspectRatio.reset:
        return '还原';
      case DisplayAspectRatio.fill:
        return '填充';
      case DisplayAspectRatio.autoAdapt:
        return '自适应';
    }
  }

  /// 横屏全屏 / 非全屏可用的选项
  static const List<DisplayAspectRatio> landscapeOptions = [
    DisplayAspectRatio.ratio16_9,
    DisplayAspectRatio.ratio9_16,
    DisplayAspectRatio.fill,
    DisplayAspectRatio.autoAdapt,
  ];

  /// 竖屏全屏可用的选项
  static const List<DisplayAspectRatio> portraitOptions = [
    DisplayAspectRatio.reset,
    DisplayAspectRatio.ratio9_16,
    DisplayAspectRatio.fill,
    DisplayAspectRatio.autoAdapt,
  ];
}

/// 画面比例选择面板
class AspectRatioPanel extends StatelessWidget {
  final DisplayAspectRatio current;
  final List<DisplayAspectRatio> options;
  final void Function(DisplayAspectRatio ratio) onSelected;
  final VoidCallback onDismiss;
  final double scale;
  final double maxHeight;
  final double playerWidth;

  const AspectRatioPanel({
    super.key,
    required this.current,
    required this.options,
    required this.onSelected,
    required this.onDismiss,
    required this.scale,
    required this.maxHeight,
    required this.playerWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: PlayerControlsStyles.scaledWidth(140, playerWidth),
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: PlayerControlsStyles.panelBg,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(PlayerControlsStyles.scaledPadding(9, scale)),
            bottomLeft: Radius.circular(PlayerControlsStyles.scaledPadding(9, scale)),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(7, scale),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('画面比例', style: TextStyle(
                  color: PlayerControlsStyles.textColor,
                  fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                  fontWeight: FontWeight.w600,
                )),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ...options.map((ratio) => _RatioItem(
              ratio: ratio,
              isActive: current == ratio,
              onTap: () => onSelected(ratio),
              scale: scale,
            )),
            SizedBox(height: PlayerControlsStyles.scaledPadding(7, scale)),
          ]),
        ),
      ),
    );
  }
}

class _RatioItem extends StatelessWidget {
  final DisplayAspectRatio ratio;
  final bool isActive;
  final VoidCallback onTap;
  final double scale;

  const _RatioItem({required this.ratio, required this.isActive, required this.onTap, required this.scale});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: PlayerControlsStyles.scaledPadding(9, scale),
          vertical: PlayerControlsStyles.scaledPadding(9, scale),
        ),
        child: Row(children: [
          Expanded(child: Text(
            ratio.label,
            style: TextStyle(
              color: isActive ? PlayerControlsStyles.speedActive : PlayerControlsStyles.speedInactive,
              fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          )),
          if (isActive)
            Icon(Icons.check, color: PlayerControlsStyles.speedActive, size: PlayerControlsStyles.scaledFontSize(10, scale)),
        ]),
      ),
    );
  }
}
