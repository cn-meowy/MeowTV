import 'package:flutter/material.dart';
import '../../../../shared/widgets/marquee_text.dart';
import '../../cast/cast_service.dart';
import 'styles.dart';

/// 顶部控制栏：返回按钮 + 标题 + 投屏 + 更多
class TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onCast;
  final VoidCallback onMore;
  final CastState castState;
  final double scale;

  const TopBar({
    super.key,
    required this.title,
    required this.onBack,
    required this.onCast,
    required this.onMore,
    this.castState = CastState.disconnected,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = PlayerControlsStyles.scaledSize(PlayerControlsStyles.iconSize, scale, 18);
    final barHeight = PlayerControlsStyles.scaledSize(PlayerControlsStyles.controlBarHeight, scale, 33);
    final titleFontSize = PlayerControlsStyles.scaledSize(PlayerControlsStyles.titleTextSize, scale, 12);

    return Container(
      height: barHeight,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [PlayerControlsStyles.gradientEnd, PlayerControlsStyles.gradientStart],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: PlayerControlsStyles.scaledSize(4, scale, 3)),
        child: Row(children: [
          // 返回
          IconButton(
            icon: Icon(Icons.arrow_back, color: PlayerControlsStyles.iconColor, size: iconSize),
            onPressed: onBack,
          ),
          // 标题（超长时横向滚动，否则静态单行展示）
          Expanded(child: MarqueeText(
            text: title,
            style: TextStyle(
              color: PlayerControlsStyles.textColor,
              fontSize: titleFontSize,
              fontWeight: FontWeight.w500,
            ),
            staticMaxLines: 1,
          )),
          // 投屏
          IconButton(
            icon: _castIcon(iconSize),
            onPressed: onCast,
          ),
          // 更多
          IconButton(
            icon: Icon(Icons.more_vert, color: PlayerControlsStyles.iconColor, size: iconSize),
            onPressed: onMore,
          ),
        ]),
      ),
    );
  }

  Widget _castIcon(double iconSize) {
    final isConnected = castState == CastState.playing ||
        castState == CastState.paused ||
        castState == CastState.buffering ||
        castState == CastState.connected ||
        castState == CastState.loading;
    final isDiscovering = castState == CastState.discovering || castState == CastState.connecting;

    if (isConnected) {
      return Icon(Icons.cast_connected, color: PlayerControlsStyles.castActive, size: iconSize);
    }
    if (isDiscovering) {
      return Icon(Icons.cast_connected, color: PlayerControlsStyles.iconColor, size: iconSize);
    }
    return Icon(Icons.cast, color: PlayerControlsStyles.castInactive, size: iconSize);
  }
}
