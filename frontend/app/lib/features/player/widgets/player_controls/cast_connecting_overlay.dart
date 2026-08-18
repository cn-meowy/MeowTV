import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../playback/playback_controller.dart';
import '../../playback/playback_provider.dart';
import '../../../settings/buffer_mode_provider.dart';
import '../../../../shared/models/enums.dart';
import 'styles.dart';

/// 投屏时替代视频画面的连接界面。
class CastConnectingOverlay extends ConsumerStatefulWidget {
  final String? title;
  final VoidCallback? onDisconnect;
  final VoidCallback? onPreviousEpisode;
  final VoidCallback? onNextEpisode;
  final bool canPrevious;
  final bool canNext;

  const CastConnectingOverlay({
    super.key,
    this.title,
    this.onDisconnect,
    this.onPreviousEpisode,
    this.onNextEpisode,
    this.canPrevious = true,
    this.canNext = true,
  });

  @override
  ConsumerState<CastConnectingOverlay> createState() =>
      _CastConnectingOverlayState();
}

class _CastConnectingOverlayState extends ConsumerState<CastConnectingOverlay> {
  bool _visible = true;
  Timer? _hideTimer;
  bool _isVolumeGesture = false;
  bool _isBrightnessGesture = false;
  bool _isSeeking = false;
  double _gestureValue = 0.5;
  Duration _seekDelta = Duration.zero;

  @override
  void initState() {
    super.initState();
    // 投屏期间控制条常驻，避免后台被系统杀掉导致 TV 播放中断。
    // 退出投屏后由 PlayerScreen 销毁本 widget，dispose 兜底清理。
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _toggleVisible() {
    // 投屏态默认常驻。用户点击可临时隐藏，但 5 秒后自动重新显示，
    // 而不是完全隐藏 —— 避免后台运行时 UI 不在视野内被系统判断闲置。
    setState(() => _visible = !_visible);
    if (_visible) {
      _hideTimer?.cancel();
    } else {
      // 隐藏 5 秒后强制重新显示
      _hideTimer?.cancel();
      _hideTimer = Timer(PlayerControlsStyles.autoHideDelay, () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  String _bannerText(BufferMode mode) {
    switch (mode) {
      case BufferMode.strategyA:
        return 'HLS 缓冲模式直连源站，若播放失败请切换至「边播边下」模式';
      case BufferMode.strategyB:
        return '正在通过 app 代理播放，请保持手机前台运行';
    }
  }

  // ─── 垂直手势 ──

  void _onVerticalStart(bool isRight) {
    if (!mounted) return;
    setState(() {
      _isBrightnessGesture = !isRight;
      _isVolumeGesture = isRight;
    });
    _hideTimer?.cancel();
    if (_isVolumeGesture) {
      final vol = ref.read(playbackControllerProvider).state.volume;
      if (mounted) setState(() => _gestureValue = vol.clamp(0.0, 1.0));
    } else {
      _initBrightness();
    }
  }

  Future<void> _initBrightness() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      final b = await ScreenBrightness().application;
      if (mounted && _isBrightnessGesture) {
        setState(() => _gestureValue = b.clamp(0.0, 1.0));
      }
    } catch (_) {}
  }

  void _onVerticalUpdate(double delta) {
    if (!mounted) return;
    setState(() => _gestureValue = (_gestureValue + delta).clamp(0.0, 1.0));
    if (_isVolumeGesture) {
      ref.read(playbackControllerProvider).setVolume(_gestureValue);
    }
    if (_isBrightnessGesture && (Platform.isIOS || Platform.isAndroid)) {
      try {
        ScreenBrightness().setApplicationScreenBrightness(_gestureValue);
      } catch (_) {}
    }
  }

  void _onVerticalEnd() {
    if (!mounted) return;
    setState(() { _isVolumeGesture = false; _isBrightnessGesture = false; });
    // 投屏期控制条常驻：手势结束不重新隐藏
    _hideTimer?.cancel();
  }

  // ─── 水平手势 ──

  void _onSeekStart() {
    if (!mounted) return;
    setState(() { _isSeeking = true; _seekDelta = Duration.zero; });
    _hideTimer?.cancel();
  }

  void _onSeekUpdate(double dx) {
    if (!mounted) return;
    setState(() => _seekDelta += Duration(milliseconds: (dx * 1000).round()));
  }

  void _onSeekEnd() {
    if (!mounted) return;
    if (_seekDelta != Duration.zero) {
      final pb = ref.read(playbackControllerProvider);
      pb.seekTo(pb.state.position + _seekDelta);
    }
    setState(() { _isSeeking = false; _seekDelta = Duration.zero; });
    // 投屏期控制条常驻：手势结束不重新隐藏
    _hideTimer?.cancel();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ─── build ──

  @override
  Widget build(BuildContext context) {
    final pb = ref.watch(playbackControllerProvider);
    final state = pb.state;
    final sz = MediaQuery.of(context).size;
    final bufferMode = ref.watch(bufferModeProvider).mode;

    return Container(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleVisible,
          onVerticalDragStart: (d) => _onVerticalStart(d.globalPosition.dx > sz.width / 2),
          onVerticalDragUpdate: (d) => _onVerticalUpdate(-d.delta.dy / sz.height),
          onVerticalDragEnd: (_) => _onVerticalEnd(),
          onHorizontalDragStart: (_) => _onSeekStart(),
          onHorizontalDragUpdate: (d) => _onSeekUpdate(d.delta.dx),
          onHorizontalDragEnd: (_) => _onSeekEnd(),
          child: const SizedBox.expand(),
        ),
        if (_isVolumeGesture || _isBrightnessGesture)
          Center(child: _gestureOverlay()),
        if (_isSeeking)
          Center(child: _seekOverlay(state)),
        AnimatedOpacity(
          opacity: _visible ? 1.0 : 0.0,
          duration: PlayerControlsStyles.controlsAnimDuration,
          child: IgnorePointer(ignoring: !_visible, child: _panel(state, pb)),
        ),
        // 顶部滚动提示条（投屏期常驻，不随控件隐藏，不拦截点击）
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: _ScrollingBanner(text: _bannerText(bufferMode)),
          ),
        ),
        // 常驻退出投屏按钮（不随控件自动隐藏）
        Positioned(
          top: 16,
          right: 16,
          child: _buildDisconnectButton(),
        ),
      ]),
    );
  }

  Widget _gestureOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: PlayerControlsStyles.gestureBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          _isVolumeGesture
              ? (_gestureValue > 0 ? Icons.volume_up : Icons.volume_off)
              : (_gestureValue > 0.5 ? Icons.brightness_high : Icons.brightness_low),
          color: PlayerControlsStyles.iconColor,
          size: PlayerControlsStyles.gestureIconSize,
        ),
        const SizedBox(height: 4),
        Text('${(_gestureValue * 100).round()}%',
            style: const TextStyle(color: PlayerControlsStyles.textColor, fontSize: 13)),
      ]),
    );
  }

  Widget _seekOverlay(PlaybackState state) {
    final target = state.position + _seekDelta;
    final fwd = _seekDelta.inMilliseconds >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: PlayerControlsStyles.gestureBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(fwd ? Icons.fast_forward : Icons.fast_rewind,
            color: PlayerControlsStyles.iconColor, size: PlayerControlsStyles.gestureIconSize),
        const SizedBox(width: 8),
        Text(_fmt(target),
            style: const TextStyle(color: PlayerControlsStyles.textColor, fontSize: 13)),
      ]),
    );
  }

  Widget _panel(PlaybackState state, PlaybackController pb) {
    final durMs = state.duration.inMilliseconds.toDouble();
    final posMs = state.position.inMilliseconds.toDouble().clamp(0.0, durMs);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cast, size: 48, color: Color(0x80FFFFFF)),
          const SizedBox(height: 12),
          const Text('正在投屏至',
              style: TextStyle(color: PlayerControlsStyles.textSecondary, fontSize: 13)),
          const SizedBox(height: 4),
          Text(state.castDeviceName ?? '',
              style: const TextStyle(color: PlayerControlsStyles.textColor, fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          if (widget.title != null && widget.title!.isNotEmpty) ...[
            Text(widget.title!,
                style: const TextStyle(color: PlayerControlsStyles.textColor, fontSize: 14)),
            const SizedBox(height: 20),
          ],
          // 上一集 / 播放暂停 / 下一集
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              onPressed: widget.canPrevious ? widget.onPreviousEpisode : null,
              icon: Icon(Icons.skip_previous,
                  color: widget.canPrevious ? PlayerControlsStyles.iconColor : PlayerControlsStyles.iconColor.withValues(alpha: 0.3)),
              iconSize: 36,
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () => pb.togglePlayPause(),
              child: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: PlayerControlsStyles.iconColor, size: 48),
            ),
            const SizedBox(width: 16),
            IconButton(
              onPressed: widget.canNext ? widget.onNextEpisode : null,
              icon: Icon(Icons.skip_next,
                  color: widget.canNext ? PlayerControlsStyles.iconColor : PlayerControlsStyles.iconColor.withValues(alpha: 0.3)),
              iconSize: 36,
            ),
          ]),
          const SizedBox(height: 20),
          // 进度条
          if (durMs > 0) ...[
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: PlayerControlsStyles.progressPlayed,
                inactiveTrackColor: PlayerControlsStyles.progressTrack,
                thumbColor: PlayerControlsStyles.progressThumb,
                overlayColor: PlayerControlsStyles.progressPlayed.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: posMs,
                min: 0,
                max: durMs,
                onChanged: (v) => pb.seekTo(Duration(milliseconds: v.round())),
              ),
            ),
            // 时间
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_fmt(state.position),
                    style: const TextStyle(color: PlayerControlsStyles.textSecondary, fontSize: 12)),
                Text('${_fmt(state.position)} / ${_fmt(state.duration)}',
                    style: const TextStyle(color: PlayerControlsStyles.textSecondary, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 20),
          ],
        ]),
      ),
    );
  }

  Widget _buildDisconnectButton() {
    return GestureDetector(
      onTap: widget.onDisconnect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: PlayerControlsStyles.gestureBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PlayerControlsStyles.iconColor.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cast_connected, color: PlayerControlsStyles.iconColor, size: 16),
          const SizedBox(width: 4),
          const Text('退出投屏', style: TextStyle(color: PlayerControlsStyles.textColor, fontSize: 12)),
        ]),
      ),
    );
  }
}

/// 投屏期顶部滚动提示条。
///
/// 文本超过单屏宽度时自动横向滚动（无限循环），否则静态居中显示。
/// 使用 [SingleChildScrollView] + [ScrollController] + 周期 [Timer] 驱动，
/// 不引入第三方 Marquee 依赖。滚动速度由 [PlayerControlsStyles.castBannerScrollSpeed] 控制。
class _ScrollingBanner extends StatefulWidget {
  final String text;

  const _ScrollingBanner({required this.text});

  @override
  State<_ScrollingBanner> createState() => _ScrollingBannerState();
}

class _ScrollingBannerState extends State<_ScrollingBanner> {
  final ScrollController _controller = ScrollController();
  Timer? _timer;
  // 文本是否需要滚动（仅在内容超宽时启动）
  bool _needsScroll = false;
  // 单次循环周期（一屏空白 + 文本宽度），用于回绕
  double _loopExtent = 0.0;
  static const _separator = '        ';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndStart());
  }

  @override
  void didUpdateWidget(covariant _ScrollingBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      // 文案变化（如用户切换缓冲模式）：重新测量并重置滚动
      _stop();
      if (_controller.hasClients) _controller.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndStart());
    }
  }

  @override
  void dispose() {
    _stop();
    _controller.dispose();
    super.dispose();
  }

  void _measureAndStart() {
    if (!mounted || !_controller.hasClients) return;
    final viewport = _controller.position.viewportDimension;
    // 测量单段文本（含分隔符）宽度
    final tp = TextPainter(
      text: TextSpan(
        text: widget.text + _separator,
        style: const TextStyle(
          color: PlayerControlsStyles.textColor,
          fontSize: 13,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final segmentWidth = tp.width;
    _needsScroll = segmentWidth > viewport;
    if (!_needsScroll) {
      if (mounted) setState(() {});
      return;
    }
    // 循环范围：从 0 滚动到 segmentWidth（第二段起点），再回绕到 0
    _loopExtent = segmentWidth;
    // 约 16ms 一帧推进，步长 = 速度(px/s) * 帧间隔(s)
    final step = PlayerControlsStyles.castBannerScrollSpeed / 60.0;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_controller.hasClients) return;
      final next = _controller.offset + step;
      if (next >= _loopExtent) {
        _controller.jumpTo(next - _loopExtent);
      } else {
        _controller.jumpTo(next);
      }
    });
    if (mounted) setState(() {});
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    // 不滚动时静态居中显示
    if (!_needsScroll) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: const Color(0x33000000),
        alignment: Alignment.center,
        child: Text(
          widget.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: PlayerControlsStyles.textColor, fontSize: 13),
        ),
      );
    }
    final segment = widget.text + _separator;
    return Container(
      width: double.infinity,
      color: const Color(0x33000000),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(segment,
              style: const TextStyle(
                  color: PlayerControlsStyles.textColor, fontSize: 13)),
          // 重复一次以实现无缝回绕
          Text(segment,
              style: const TextStyle(
                  color: PlayerControlsStyles.textColor, fontSize: 13)),
        ]),
      ),
    );
  }
}