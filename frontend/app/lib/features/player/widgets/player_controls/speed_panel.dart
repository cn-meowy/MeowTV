import 'package:flutter/material.dart';
import 'styles.dart';

/// 倍速选择面板
class SpeedPanel extends StatelessWidget {
  final double currentSpeed;
  final void Function(double speed) onSelected;
  final VoidCallback onDismiss;
  final double scale;
  final double maxHeight;
  final double playerWidth;

  const SpeedPanel({
    super.key,
    required this.currentSpeed,
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
                child: Text('播放速度', style: TextStyle(
                  color: PlayerControlsStyles.textColor,
                  fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                  fontWeight: FontWeight.w600,
                )),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ...PlayerControlsStyles.speedOptions.map((speed) => _SpeedItem(
              speed: speed,
              isActive: (currentSpeed - speed).abs() < 0.01,
              onTap: () => onSelected(speed),
              scale: scale,
            )),
            SizedBox(height: PlayerControlsStyles.scaledPadding(7, scale)),
          ]),
        ),
      ),
    );
  }
}

class _SpeedItem extends StatelessWidget {
  final double speed;
  final bool isActive;
  final VoidCallback onTap;
  final double scale;

  const _SpeedItem({required this.speed, required this.isActive, required this.onTap, required this.scale});

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
            speed == 1.0 ? '正常' : '${speed}x',
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
