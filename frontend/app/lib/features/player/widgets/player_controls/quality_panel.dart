import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../quality/quality_level.dart';
import '../../quality/quality_manager.dart';
import '../../quality/quality_provider.dart';
import 'styles.dart';

/// 清晰度选择面板
class QualityPanel extends ConsumerWidget {
  final VoidCallback onDismiss;
  final double scale;
  final double maxHeight;
  final double playerWidth;

  const QualityPanel({
    super.key,
    required this.onDismiss,
    required this.scale,
    required this.maxHeight,
    required this.playerWidth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(qualityManagerProvider);
    final isSwitching = manager.switchState != QualitySwitchState.idle;
    final isDefault = manager.isDefault;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: PlayerControlsStyles.scaledWidth(PlayerControlsStyles.qualityPanelWidth, playerWidth),
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
            // 标题栏
            Padding(
              padding: EdgeInsets.fromLTRB(
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(7, scale),
                PlayerControlsStyles.scaledPadding(7, scale),
              ),
              child: Row(children: [
                Text('清晰度', style: TextStyle(
                  color: PlayerControlsStyles.textColor,
                  fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                  fontWeight: FontWeight.w600,
                )),
                const Spacer(),
                if (isSwitching)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PlayerControlsStyles.speedActive,
                    ),
                  ),
                if (!isSwitching)
                  IconButton(
                    icon: Icon(Icons.close, color: PlayerControlsStyles.iconColor, size: PlayerControlsStyles.scaledFontSize(10, scale)),
                    onPressed: onDismiss,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(minWidth: PlayerControlsStyles.scaledPadding(28, scale), minHeight: PlayerControlsStyles.scaledPadding(28, scale)),
                  ),
              ]),
            ),
            const Divider(color: Colors.white12, height: 1),

            // 默认模式：仅显示"默认"选项，不可切换
            if (isDefault)
              _QualityItem(
                label: '默认',
                subtitle: '当前视频不支持清晰度切换',
                isActive: true,
                isSwitching: false,
                onTap: null,
                scale: scale,
              ),

            // 非默认模式：显示自动选项 + 各清晰度
            if (!isDefault) ...[
              // 自动选项
              _QualityItem(
                label: '自动${manager.currentLevel != null && manager.mode == QualityMode.auto ? ' (${manager.currentLevel!.label})' : ''}',
                subtitle: null,
                isActive: manager.mode == QualityMode.auto,
                isSwitching: isSwitching && manager.switchTarget == null,
                onTap: isSwitching ? null : () {
                  manager.setAutoMode();
                },
                scale: scale,
              ),
              const Divider(color: Colors.white12, height: 1, indent: 16, endIndent: 16),

              // 各清晰度选项
              ...manager.levels.map((level) => _QualityItem(
                label: level.label,
                subtitle: level.bandwidthLabel,
                isActive: manager.mode == QualityMode.manual && manager.currentLevel?.id == level.id,
                isSwitching: isSwitching && manager.switchTarget?.id == level.id,
                onTap: isSwitching ? null : () {
                  manager.selectQuality(level);
                  onDismiss();
                },
                scale: scale,
              )),
            ],

            SizedBox(height: PlayerControlsStyles.scaledPadding(7, scale)),
          ]),
        ),
      ),
    );
  }
}

class _QualityItem extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool isActive;
  final bool isSwitching;
  final VoidCallback? onTap;
  final double scale;

  const _QualityItem({
    required this.label,
    this.subtitle,
    required this.isActive,
    this.isSwitching = false,
    this.onTap,
    required this.scale,
  });

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
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(
                color: isActive ? PlayerControlsStyles.speedActive : PlayerControlsStyles.speedInactive,
                fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              )),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(
                  color: const Color(0x88FFFFFF),
                  fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                )),
            ],
          )),
          if (isSwitching)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: PlayerControlsStyles.speedActive,
              ),
            ),
          if (isActive && !isSwitching)
            Icon(Icons.check, color: PlayerControlsStyles.speedActive, size: PlayerControlsStyles.scaledFontSize(10, scale)),
        ]),
      ),
    );
  }
}
