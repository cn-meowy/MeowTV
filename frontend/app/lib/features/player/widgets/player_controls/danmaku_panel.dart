import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../danmaku/danmaku_item.dart';
import '../../danmaku/danmaku_provider.dart';
import 'styles.dart';

/// 弹幕设置面板
class DanmakuPanel extends ConsumerWidget {
  final VoidCallback onDismiss;
  final double scale;
  final double maxHeight;
  final double playerWidth;

  const DanmakuPanel({
    super.key,
    required this.onDismiss,
    required this.scale,
    required this.maxHeight,
    required this.playerWidth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(danmakuControllerProvider);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: PlayerControlsStyles.scaledWidth(PlayerControlsStyles.danmakuPanelWidth, playerWidth),
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
                PlayerControlsStyles.scaledPadding(7, scale),
                PlayerControlsStyles.scaledPadding(7, scale),
              ),
              child: Row(children: [
                Text('弹幕设置', style: TextStyle(
                  color: PlayerControlsStyles.textColor,
                  fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                  fontWeight: FontWeight.w600,
                )),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: PlayerControlsStyles.iconColor, size: PlayerControlsStyles.scaledFontSize(10, scale)),
                  onPressed: onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: PlayerControlsStyles.scaledPadding(28, scale), minHeight: PlayerControlsStyles.scaledPadding(28, scale)),
                ),
              ]),
            ),
            const Divider(color: Colors.white12, height: 1),

            _SwitchRow(
              label: '弹幕开关',
              value: controller.isEnabled,
              onChanged: (v) { controller.isEnabled = v; controller.notifyUI(); },
              scale: scale,
            ),
            _SliderRow(
              label: '透明度',
              value: controller.opacity,
              min: 0.1, max: 1.0, divisions: 9,
              valueLabel: '${(controller.opacity * 100).round()}%',
              onChanged: (v) { controller.opacity = v; controller.notifyUI(); },
              scale: scale,
            ),
            _SegmentRow(
              label: '字号',
              options: const ['小', '中', '大'],
              values: const [0.7, 1.0, 1.4],
              currentValue: controller.fontSizeScale,
              onChanged: (v) { controller.fontSizeScale = v; controller.notifyUI(); },
              scale: scale,
            ),
            _SegmentRow(
              label: '滚动速度',
              options: const ['慢', '正常', '快'],
              values: const [0.6, 1.0, 1.5],
              currentValue: controller.speed,
              onChanged: (v) { controller.speed = v; controller.notifyUI(); },
              scale: scale,
            ),
            _SegmentRow(
              label: '显示区域',
              options: const ['全屏', '上半', '1/4'],
              values: const [0.0, 1.0, 3.0],
              currentValue: controller.displayArea.index.toDouble(),
              onChanged: (v) {
                controller.displayArea = DanmakuDisplayArea.values[v.round()];
                controller.notifyUI();
              },
              scale: scale,
            ),
            _SegmentRow(
              label: '同屏密度',
              options: const ['少', '中', '多', '无限'],
              values: const [10.0, 30.0, 60.0, 0.0],
              currentValue: controller.maxDensity.toDouble(),
              onChanged: (v) { controller.maxDensity = v.round(); controller.notifyUI(); },
              scale: scale,
            ),

            const Divider(color: Colors.white12, height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: EdgeInsets.fromLTRB(
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(4, scale),
              ),
              child: Align(alignment: Alignment.centerLeft, child: Text('过滤设置',
                style: TextStyle(color: PlayerControlsStyles.textSecondary, fontSize: PlayerControlsStyles.scaledFontSize(10, scale)))),
            ),
            _SwitchRow(
              label: '滚动弹幕',
              value: controller.filter.scrollEnabled,
              onChanged: (v) => controller.setFilter(controller.filter.copyWith(scrollEnabled: v)),
              scale: scale,
            ),
            _SwitchRow(
              label: '顶部固定',
              value: controller.filter.topFixedEnabled,
              onChanged: (v) => controller.setFilter(controller.filter.copyWith(topFixedEnabled: v)),
              scale: scale,
            ),
            _SwitchRow(
              label: '底部固定',
              value: controller.filter.bottomFixedEnabled,
              onChanged: (v) => controller.setFilter(controller.filter.copyWith(bottomFixedEnabled: v)),
              scale: scale,
            ),
            SizedBox(height: PlayerControlsStyles.scaledPadding(9, scale)),
          ]),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final double scale;
  const _SwitchRow({required this.label, required this.value, required this.onChanged, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: PlayerControlsStyles.scaledPadding(9, scale),
        vertical: PlayerControlsStyles.scaledPadding(4, scale),
      ),
      child: Row(children: [
        Text(label, style: TextStyle(color: PlayerControlsStyles.textSecondary, fontSize: PlayerControlsStyles.scaledFontSize(10, scale))),
        const Spacer(),
        SizedBox(height: 28, child: Switch(
          value: value, onChanged: onChanged,
          activeThumbColor: PlayerControlsStyles.speedActive,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        )),
      ]),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min, max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;
  final double scale;
  const _SliderRow({required this.label, required this.value, required this.min, required this.max,
    required this.divisions, required this.valueLabel, required this.onChanged, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: PlayerControlsStyles.scaledPadding(9, scale),
        vertical: PlayerControlsStyles.scaledPadding(2, scale),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: TextStyle(color: PlayerControlsStyles.textSecondary, fontSize: PlayerControlsStyles.scaledFontSize(10, scale))),
          const Spacer(),
          Text(valueLabel, style: TextStyle(color: PlayerControlsStyles.speedActive, fontSize: PlayerControlsStyles.scaledFontSize(10, scale))),
        ]),
        SliderTheme(data: SliderThemeData(
          activeTrackColor: PlayerControlsStyles.speedActive,
          thumbColor: PlayerControlsStyles.speedActive,
          inactiveTrackColor: Colors.white24,
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        ), child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged)),
      ]),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  final String label;
  final List<String> options;
  final List<double> values;
  final double currentValue;
  final ValueChanged<double> onChanged;
  final double scale;
  const _SegmentRow({required this.label, required this.options, required this.values,
    required this.currentValue, required this.onChanged, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: PlayerControlsStyles.scaledPadding(9, scale),
        vertical: PlayerControlsStyles.scaledPadding(5, scale),
      ),
      child: Row(children: [
        Text(label, style: TextStyle(color: PlayerControlsStyles.textSecondary, fontSize: PlayerControlsStyles.scaledFontSize(10, scale))),
        const Spacer(),
        ...List.generate(options.length, (i) {
          final isActive = (values[i] - currentValue).abs() < 0.01;
          return GestureDetector(
            onTap: () => onChanged(values[i]),
            child: Container(
              margin: EdgeInsets.only(left: PlayerControlsStyles.scaledPadding(4, scale)),
              padding: EdgeInsets.symmetric(
                horizontal: PlayerControlsStyles.scaledPadding(7, scale),
                vertical: PlayerControlsStyles.scaledPadding(4, scale),
              ),
              decoration: BoxDecoration(
                color: isActive ? PlayerControlsStyles.speedActive : Colors.white12,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(options[i], style: TextStyle(
                color: isActive ? Colors.white : PlayerControlsStyles.textSecondary,
                fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              )),
            ),
          );
        }),
      ]),
    );
  }
}
