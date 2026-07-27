import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../settings/play_mode_provider.dart';
import '../../../../shared/models/enums.dart';
import 'styles.dart';

/// 连播模式选择面板
class PlayModePanel extends ConsumerWidget {
  final VoidCallback onDismiss;
  final double scale;
  final double maxHeight;
  final double playerWidth;

  const PlayModePanel({
    super.key,
    required this.onDismiss,
    required this.scale,
    required this.maxHeight,
    required this.playerWidth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(playModeProvider);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: PlayerControlsStyles.scaledWidth(180, playerWidth),
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: PlayerControlsStyles.panelBg,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(PlayerControlsStyles.scaledPadding(10, scale)),
            bottomLeft: Radius.circular(PlayerControlsStyles.scaledPadding(10, scale)),
          ),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 标题栏
          Padding(
            padding: EdgeInsets.fromLTRB(
              PlayerControlsStyles.scaledPadding(14, scale),
              PlayerControlsStyles.scaledPadding(14, scale),
              PlayerControlsStyles.scaledPadding(7, scale),
              PlayerControlsStyles.scaledPadding(7, scale),
            ),
            child: Row(children: [
              Text('连播设置', style: TextStyle(
                color: PlayerControlsStyles.textColor,
                fontSize: PlayerControlsStyles.scaledFontSize(13, scale),
                fontWeight: FontWeight.w600,
              )),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close, color: PlayerControlsStyles.iconColor, size: PlayerControlsStyles.scaledFontSize(16, scale)),
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: PlayerControlsStyles.scaledPadding(28, scale),
                  minHeight: PlayerControlsStyles.scaledPadding(28, scale),
                ),
              ),
            ]),
          ),
          const Divider(color: Colors.white12, height: 1),
          // 选项列表
          ...PlayMode.values.map((mode) => _PlayModeItem(
            mode: mode,
            isActive: currentMode == mode,
            onTap: () {
              ref.read(playModeProvider.notifier).setPlayMode(mode);
              onDismiss();
            },
            scale: scale,
          )),
          SizedBox(height: PlayerControlsStyles.scaledPadding(7, scale)),
        ]),
      ),
    );
  }
}

class _PlayModeItem extends StatelessWidget {
  final PlayMode mode;
  final bool isActive;
  final VoidCallback onTap;
  final double scale;

  const _PlayModeItem({
    required this.mode,
    required this.isActive,
    required this.onTap,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: PlayerControlsStyles.scaledPadding(14, scale),
          vertical: PlayerControlsStyles.scaledPadding(9, scale),
        ),
        child: Row(children: [
          Icon(
            isActive ? Icons.radio_button_checked : Icons.radio_button_off,
            color: isActive ? PlayerControlsStyles.speedActive : PlayerControlsStyles.speedInactive,
            size: PlayerControlsStyles.scaledFontSize(16, scale),
          ),
          SizedBox(width: PlayerControlsStyles.scaledPadding(10, scale)),
          Expanded(child: Text(
            mode.label,
            style: TextStyle(
              color: isActive ? PlayerControlsStyles.speedActive : PlayerControlsStyles.speedInactive,
              fontSize: PlayerControlsStyles.scaledFontSize(13, scale),
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          )),
        ]),
      ),
    );
  }
}
