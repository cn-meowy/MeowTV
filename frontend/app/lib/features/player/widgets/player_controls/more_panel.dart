import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../settings/play_mode_provider.dart';
import '../../../../shared/models/enums.dart';
import '../../audio_track/audio_track_provider.dart';
import '../../capture/capture_provider.dart';
import '../../capture/media_capture_manager.dart';
import 'sleep_timer_provider.dart';
import 'styles.dart';

/// 预设时间选项（分钟）
const _presetMinutes = [10, 20, 30, 45, 60];

/// 更多设置面板（定时关闭）
class MorePanel extends ConsumerStatefulWidget {
  final VoidCallback onDismiss;
  final VoidCallback? onOpenGifPanel;
  final VoidCallback? onOpenAudioTrackPanel;
  final double scale;
  final double maxHeight;
  final double playerWidth;

  const MorePanel({
    super.key,
    required this.onDismiss,
    this.onOpenGifPanel,
    this.onOpenAudioTrackPanel,
    required this.scale,
    required this.maxHeight,
    required this.playerWidth,
  });

  @override
  ConsumerState<MorePanel> createState() => _MorePanelState();
}

class _MorePanelState extends ConsumerState<MorePanel> {
  final _customController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _customController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onPresetTap(int minutes) {
    ref.read(sleepTimerProvider.notifier).startTimerMinutes(minutes);
  }

  void _onCustomSubmit() {
    final text = _customController.text.trim();
    if (text.isEmpty) return;
    final minutes = int.tryParse(text);
    if (minutes == null || minutes <= 0 || minutes > 999) {
      // 输入无效，忽略
      return;
    }
    ref.read(sleepTimerProvider.notifier).startTimerMinutes(minutes);
    _customController.clear();
  }

  void _cyclePlayMode() {
    final current = ref.read(playModeProvider);
    final next = switch (current) {
      PlayMode.autoNext => PlayMode.pauseOnEnd,
      PlayMode.pauseOnEnd => PlayMode.loopSingle,
      PlayMode.loopSingle => PlayMode.autoNext,
    };
    ref.read(playModeProvider.notifier).setPlayMode(next);
  }

  String get _playModeLabel {
    final mode = ref.watch(playModeProvider);
    return switch (mode) {
      PlayMode.autoNext => '自动下一集',
      PlayMode.pauseOnEnd => '播完暂停',
      PlayMode.loopSingle => '单集循环',
    };
  }

  @override
  Widget build(BuildContext context) {
    final timerState = ref.watch(sleepTimerProvider);
    final manager = ref.watch(captureManagerProvider);
    final scale = widget.scale;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: PlayerControlsStyles.scaledWidth(280, widget.playerWidth),
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
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
              Text('定时关闭', style: TextStyle(
                color: PlayerControlsStyles.textColor,
                fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                fontWeight: FontWeight.w600,
              )),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close, color: PlayerControlsStyles.iconColor, size: PlayerControlsStyles.scaledFontSize(10, scale)),
                onPressed: widget.onDismiss,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: PlayerControlsStyles.scaledPadding(28, scale), minHeight: PlayerControlsStyles.scaledPadding(28, scale)),
              ),
            ]),
          ),
          const Divider(color: Colors.white12, height: 1),

          // 预设时间按钮
          Padding(
            padding: EdgeInsets.fromLTRB(
              PlayerControlsStyles.scaledPadding(9, scale),
              PlayerControlsStyles.scaledPadding(9, scale),
              PlayerControlsStyles.scaledPadding(9, scale),
              PlayerControlsStyles.scaledPadding(7, scale),
            ),
            child: Wrap(
              spacing: PlayerControlsStyles.scaledPadding(7, scale),
              runSpacing: PlayerControlsStyles.scaledPadding(7, scale),
              children: _presetMinutes.map((minutes) => _TimerButton(
                label: '$minutes分钟',
                isActive: timerState.isActive && timerState.totalSeconds == minutes * 60,
                onTap: () => _onPresetTap(minutes),
                scale: scale,
              )).toList(),
            ),
          ),

          // 自定义输入
          Padding(
            padding: EdgeInsets.fromLTRB(
              PlayerControlsStyles.scaledPadding(9, scale),
              PlayerControlsStyles.scaledPadding(7, scale),
              PlayerControlsStyles.scaledPadding(9, scale),
              PlayerControlsStyles.scaledPadding(7, scale),
            ),
            child: Row(children: [
              Expanded(child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _customController,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: PlayerControlsStyles.textColor, fontSize: PlayerControlsStyles.scaledFontSize(10, scale)),
                  decoration: InputDecoration(
                    hintText: '自定义分钟数',
                    hintStyle: TextStyle(color: PlayerControlsStyles.textSecondary.withValues(alpha: 0.6), fontSize: PlayerControlsStyles.scaledFontSize(10, scale)),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: PlayerControlsStyles.scaledPadding(9, scale),
                      vertical: PlayerControlsStyles.scaledPadding(7, scale),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: PlayerControlsStyles.speedActive),
                    ),
                  ),
                  onSubmitted: (_) => _onCustomSubmit(),
                ),
              )),
              SizedBox(width: PlayerControlsStyles.scaledPadding(7, scale)),
              GestureDetector(
                onTap: _onCustomSubmit,
                child: Container(
                  height: 36,
                  padding: EdgeInsets.symmetric(horizontal: PlayerControlsStyles.scaledPadding(9, scale)),
                  decoration: BoxDecoration(
                    color: PlayerControlsStyles.speedActive,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text('确定', style: TextStyle(color: Colors.white, fontSize: PlayerControlsStyles.scaledFontSize(10, scale), fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),

          // 定时激活时显示剩余时间和取消按钮
          if (timerState.isActive) ...[
            const Divider(color: Colors.white12, height: 1),
            Padding(
              padding: EdgeInsets.all(PlayerControlsStyles.scaledPadding(9, scale)),
              child: Row(children: [
                Icon(Icons.timer, color: PlayerControlsStyles.speedActive, size: PlayerControlsStyles.scaledFontSize(10, scale)),
                SizedBox(width: PlayerControlsStyles.scaledPadding(7, scale)),
                Text(
                  '剩余 ${timerState.remainingFormatted}',
                  style: TextStyle(color: PlayerControlsStyles.speedActive, fontSize: PlayerControlsStyles.scaledFontSize(10, scale), fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    ref.read(sleepTimerProvider.notifier).cancelTimer();
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: PlayerControlsStyles.scaledPadding(9, scale),
                      vertical: PlayerControlsStyles.scaledPadding(5, scale),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('取消定时', style: TextStyle(color: PlayerControlsStyles.textColor, fontSize: PlayerControlsStyles.scaledFontSize(10, scale))),
                  ),
                ),
              ]),
            ),
          ] else ...[
            SizedBox(height: PlayerControlsStyles.scaledPadding(7, scale)),
          ],

          const Divider(color: Colors.white12, height: 1),

          // 连播模式
          Padding(
            padding: EdgeInsets.fromLTRB(
              PlayerControlsStyles.scaledPadding(9, scale),
              PlayerControlsStyles.scaledPadding(9, scale),
              PlayerControlsStyles.scaledPadding(9, scale),
              PlayerControlsStyles.scaledPadding(9, scale),
            ),
            child: Row(children: [
              Text('连播模式', style: TextStyle(
                color: PlayerControlsStyles.textColor,
                fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
              )),
              const Spacer(),
              GestureDetector(
                onTap: _cyclePlayMode,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: PlayerControlsStyles.scaledPadding(9, scale),
                    vertical: PlayerControlsStyles.scaledPadding(4, scale),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(_playModeLabel, style: TextStyle(
                    color: PlayerControlsStyles.textSecondary,
                    fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                  )),
                ),
              ),
            ]),
          ),

          const Divider(color: Colors.white12, height: 1),

          // 音轨（仅多音轨时显示）
          if (ref.watch(audioTrackManagerProvider).hasMultipleTracks) ...[
            _MenuRow(
              icon: Icons.audiotrack,
              label: '音轨',
              trailing: Text(
                ref.watch(audioTrackManagerProvider).activeTrack?.label ?? '',
                style: TextStyle(
                  color: PlayerControlsStyles.textSecondary,
                  fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                ),
              ),
              onTap: () {
                widget.onDismiss();
                widget.onOpenAudioTrackPanel?.call();
              },
              scale: scale,
            ),
            const Divider(color: Colors.white12, height: 1),
          ],

          // 截图/录制/GIF 功能暂时禁用，待 bug 修复后恢复
          // // 截图
          // _MenuRow(
          //   icon: Icons.photo_camera,
          //   label: '截图',
          //   onTap: () async {
          //     final manager = ref.read(captureManagerProvider);
          //     widget.onDismiss();
          //     // 先关闭面板再执行截图，避免面板遮挡截图内容
          //     final result = await manager.screenshot();
          //     // 结果通过 manager.lastScreenshot / manager.lastError 自动通知 UI
          //     if (result == null && manager.lastError == null) {
          //       // 截图返回空但无错误（如状态非 idle），设置通用错误
          //       manager.setError('截图失败，请稍后重试');
          //     }
          //   },
          //   scale: scale,
          // ),
          //
          // // 录制
          // _MenuRow(
          //   icon: Icons.fiber_manual_record,
          //   label: manager.captureState == CaptureState.recording
          //       ? '停止录制 ${manager.recordDuration.inSeconds}s'
          //       : '录制',
          //   labelColor: manager.captureState == CaptureState.recording
          //       ? PlayerControlsStyles.speedActive
          //       : null,
          //   onTap: () async {
          //     final manager = ref.read(captureManagerProvider);
          //     widget.onDismiss();
          //     if (manager.captureState == CaptureState.recording) {
          //       await manager.stopRecording();
          //     } else {
          //       final success = await manager.startRecording();
          //       if (success) {
          //         // 录制成功启动，错误回调中已处理失败情况
          //       }
          //     }
          //   },
          //   scale: scale,
          // ),
          //
          // // GIF
          // _MenuRow(
          //   icon: Icons.gif,
          //   label: '生成 GIF',
          //   onTap: () {
          //     widget.onDismiss();
          //     widget.onOpenGifPanel?.call();
          //   },
          //   scale: scale,
          // ),

          ]),
        ),
      ),
    );
  }
}

class _TimerButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final double scale;

  const _TimerButton({
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: PlayerControlsStyles.scaledPadding(9, scale),
          vertical: PlayerControlsStyles.scaledPadding(7, scale),
        ),
        decoration: BoxDecoration(
          color: isActive ? PlayerControlsStyles.speedActive : Colors.white12,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : PlayerControlsStyles.textSecondary,
            fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? labelColor;
  final Widget? trailing;
  final VoidCallback onTap;
  final double scale;

  const _MenuRow({
    required this.icon,
    required this.label,
    this.labelColor,
    this.trailing,
    required this.onTap,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          PlayerControlsStyles.scaledPadding(9, scale),
          PlayerControlsStyles.scaledPadding(9, scale),
          PlayerControlsStyles.scaledPadding(9, scale),
          PlayerControlsStyles.scaledPadding(9, scale),
        ),
        child: Row(children: [
          Icon(icon, color: labelColor ?? PlayerControlsStyles.iconColor, size: PlayerControlsStyles.scaledFontSize(10, scale)),
          SizedBox(width: PlayerControlsStyles.scaledPadding(9, scale)),
          Text(label, style: TextStyle(
            color: labelColor ?? PlayerControlsStyles.textColor,
            fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
          )),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ]),
      ),
    );
  }
}
