import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../playback/playback_controller.dart';
import '../../playback/playback_provider.dart';
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
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(PlayerControlsStyles.autoHideDelay, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _toggleVisible() {
    setState(() => _visible = !_visible);
    if (_visible) _startHideTimer();
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
    _startHideTimer();
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
    _startHideTimer();
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
          // 断开投屏按钮
          TextButton(
            onPressed: widget.onDisconnect,
            style: TextButton.styleFrom(
              foregroundColor: PlayerControlsStyles.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              side: BorderSide(color: PlayerControlsStyles.iconColor.withValues(alpha: 0.3)),
            ),
            child: const Text('断开投屏', style: TextStyle(fontSize: 14)),
          ),
        ]),
      ),
    );
  }
}