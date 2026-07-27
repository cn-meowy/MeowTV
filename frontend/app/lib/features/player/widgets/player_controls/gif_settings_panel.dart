import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../capture/capture_provider.dart';
import 'styles.dart';

/// GIF 设置面板
class GifSettingsPanel extends ConsumerStatefulWidget {
  final VoidCallback onDismiss;
  final String videoPath;
  final Duration videoDuration;
  final double scale;
  final double maxHeight;
  final double playerWidth;

  const GifSettingsPanel({
    super.key,
    required this.onDismiss,
    required this.videoPath,
    required this.videoDuration,
    required this.scale,
    required this.maxHeight,
    required this.playerWidth,
  });

  @override
  ConsumerState<GifSettingsPanel> createState() => _GifSettingsPanelState();
}

class _GifSettingsPanelState extends ConsumerState<GifSettingsPanel> {
  double _startSeconds = 0;
  double _endSeconds = 10;
  int _width = 480;
  int _fps = 10;
  int _quality = 50; // 10-100, maps to ffmpeg palette quality

  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    // 默认取视频前 10 秒，不超过视频总长
    _endSeconds = widget.videoDuration.inSeconds.toDouble().clamp(1.0, 10.0);
    if (widget.videoDuration.inSeconds < 10) {
      _endSeconds = widget.videoDuration.inSeconds.toDouble();
    }
  }

  String _formatDuration(double seconds) {
    final s = seconds.toInt();
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  void _generate() async {
    if (_isGenerating) return;

    // 校验视频路径：网络流无法直接生成 GIF，需要先录制
    if (widget.videoPath.isEmpty) {
      ref.read(captureManagerProvider).setError('无法生成 GIF：请先录制视频片段，再从录制文件生成');
      return;
    }

    setState(() => _isGenerating = true);

    final manager = ref.read(captureManagerProvider);
    final gifPath = await manager.generateGif(
      videoPath: widget.videoPath,
      start: Duration(milliseconds: (_startSeconds * 1000).round()),
      end: Duration(milliseconds: (_endSeconds * 1000).round()),
      fps: _fps,
      width: _width,
      quality: _quality,
    );

    if (!mounted) return;
    setState(() => _isGenerating = false);

    if (gifPath != null) {
      // 生成成功，关闭面板，预览浮层会自动显示
      widget.onDismiss();
    }
    // 生成失败时，manager.lastError 已设置，controls_overlay 会显示 SnackBar
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(captureManagerProvider);
    final progress = manager.gifProgress;
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
                Text('生成 GIF', style: TextStyle(
                  color: PlayerControlsStyles.textColor,
                  fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                  fontWeight: FontWeight.w600,
                )),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: PlayerControlsStyles.iconColor, size: PlayerControlsStyles.scaledFontSize(10, scale)),
                  onPressed: _isGenerating ? null : widget.onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: PlayerControlsStyles.scaledPadding(28, scale), minHeight: PlayerControlsStyles.scaledPadding(28, scale)),
                ),
              ]),
            ),
            const Divider(color: Colors.white12, height: 1),

            // 时间范围
            Padding(
              padding: EdgeInsets.fromLTRB(
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(7, scale),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('时间范围  ${_formatDuration(_startSeconds)} ─ ${_formatDuration(_endSeconds)}',
                  style: TextStyle(color: PlayerControlsStyles.textColor, fontSize: PlayerControlsStyles.scaledFontSize(10, scale))),
                SizedBox(height: PlayerControlsStyles.scaledPadding(7, scale)),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: PlayerControlsStyles.speedActive,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: PlayerControlsStyles.speedActive,
                    overlayColor: PlayerControlsStyles.speedActive.withValues(alpha: 0.12),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: RangeSlider(
                    values: RangeValues(_startSeconds, _endSeconds),
                    min: 0,
                    max: widget.videoDuration.inSeconds.toDouble().clamp(1.0, 60.0),
                    divisions: widget.videoDuration.inSeconds.clamp(1, 60),
                    onChanged: _isGenerating ? null : (values) {
                      setState(() {
                        _startSeconds = values.start;
                        _endSeconds = values.end;
                      });
                    },
                  ),
                ),
              ]),
            ),

            const Divider(color: Colors.white12, height: 1),

            // 尺寸选择
            Padding(
              padding: EdgeInsets.fromLTRB(
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(4, scale),
              ),
              child: Row(children: [
                Text('尺寸', style: TextStyle(color: PlayerControlsStyles.textColor, fontSize: PlayerControlsStyles.scaledFontSize(10, scale))),
                const Spacer(),
                ...[480, 360, 240].map((w) => _OptionChip(
                  label: '${w}p',
                  isActive: _width == w,
                  onTap: _isGenerating ? null : () => setState(() => _width = w),
                  scale: scale,
                )),
              ]),
            ),

            // 帧率选择
            Padding(
              padding: EdgeInsets.fromLTRB(
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(7, scale),
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(4, scale),
              ),
              child: Row(children: [
                Text('帧率', style: TextStyle(color: PlayerControlsStyles.textColor, fontSize: PlayerControlsStyles.scaledFontSize(10, scale))),
                const Spacer(),
                ...[10, 15, 20].map((f) => _OptionChip(
                  label: '$f',
                  isActive: _fps == f,
                  onTap: _isGenerating ? null : () => setState(() => _fps = f),
                  scale: scale,
                )),
              ]),
            ),

            // 质量选择
            Padding(
              padding: EdgeInsets.fromLTRB(
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(7, scale),
                PlayerControlsStyles.scaledPadding(9, scale),
                PlayerControlsStyles.scaledPadding(4, scale),
              ),
              child: Row(children: [
                Text('质量', style: TextStyle(color: PlayerControlsStyles.textColor, fontSize: PlayerControlsStyles.scaledFontSize(10, scale))),
                const Spacer(),
                ...[
                  (10, '低'),
                  (50, '中'),
                  (80, '高'),
                ].map((q) => _OptionChip(
                  label: q.$2,
                  isActive: _quality == q.$1,
                  onTap: _isGenerating ? null : () => setState(() => _quality = q.$1),
                  scale: scale,
                )),
              ]),
            ),

            const Divider(color: Colors.white12, height: 1),

            // 生成按钮 / 进度
            Padding(
              padding: EdgeInsets.all(PlayerControlsStyles.scaledPadding(9, scale)),
              child: _isGenerating
                  ? Column(children: [
                      SizedBox(
                        width: double.infinity,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(PlayerControlsStyles.speedActive),
                        ),
                      ),
                      SizedBox(height: PlayerControlsStyles.scaledPadding(7, scale)),
                      Text('${(progress * 100).toInt()}%',
                        style: TextStyle(color: PlayerControlsStyles.textSecondary, fontSize: PlayerControlsStyles.scaledFontSize(10, scale))),
                    ])
                  : SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: widget.videoPath.isEmpty ? null : _generate,
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: PlayerControlsStyles.scaledPadding(9, scale)),
                          decoration: BoxDecoration(
                            color: widget.videoPath.isEmpty
                                ? Colors.white12
                                : PlayerControlsStyles.speedActive,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            widget.videoPath.isEmpty ? '请先录制视频' : '生成 GIF',
                            style: TextStyle(
                              color: widget.videoPath.isEmpty
                                  ? PlayerControlsStyles.textSecondary
                                  : Colors.white,
                              fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final double scale;

  const _OptionChip({
    required this.label,
    required this.isActive,
    this.onTap,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(left: PlayerControlsStyles.scaledPadding(7, scale)),
        padding: EdgeInsets.symmetric(
          horizontal: PlayerControlsStyles.scaledPadding(9, scale),
          vertical: PlayerControlsStyles.scaledPadding(4, scale),
        ),
        decoration: BoxDecoration(
          color: isActive ? PlayerControlsStyles.speedActive : Colors.white12,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: TextStyle(
          color: isActive ? Colors.white : PlayerControlsStyles.textSecondary,
          fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        )),
      ),
    );
  }
}
