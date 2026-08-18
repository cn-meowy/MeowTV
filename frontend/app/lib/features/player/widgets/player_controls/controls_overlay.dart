import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:dart_cast/dart_cast.dart';
import '../../pip/pip_service.dart';
import '../../pip/pip_provider.dart';
import '../../cast/cast_provider.dart';
import '../../cast/cast_service.dart';
import '../../playback/playback_provider.dart';
import 'styles.dart';
import 'top_bar.dart';
import 'bottom_bar.dart';
import 'gesture_layer.dart';
import 'speed_panel.dart';
import 'subtitle_panel.dart';
import 'cast_panel.dart';
import 'more_panel.dart';
import 'quality_panel.dart';
import 'aspect_ratio_panel.dart';
import 'danmaku_panel.dart';
import '../../../settings/aspect_ratio_provider.dart';
import '../../subtitle/subtitle_provider.dart';
import '../../subtitle/subtitle_widget_overlay.dart';
import '../../danmaku/danmaku_provider.dart';
import '../../danmaku/danmaku_layer.dart';
import '../../capture/capture_provider.dart';
import '../../capture/media_capture_manager.dart';
import '../../capture/capture_preview_overlay.dart';
import 'audio_track_panel.dart';
import 'gif_settings_panel.dart';

/// 全屏模式
enum FullscreenMode { landscape, portrait }

/// B站风格视频控件覆盖层
class BilibiliControls extends ConsumerStatefulWidget {
  final ChewieController chewieController;
  final String title;
  final Future<void> Function(FullscreenMode)? onEnterFullscreen;
  final VoidCallback? onExitFullscreen;
  final Future<void> Function(FullscreenMode targetMode)? onSwitchFullscreenMode;

  /// 用户主动 seek 时的回调 — 通知位置守护系统这是用户操作而非异常跳回
  final void Function(Duration target)? onUserSeek;

  /// 画面比例变更回调
  final void Function(DisplayAspectRatio ratio)? onAspectRatioChange;

  /// 还原画面比例回调 — 由 PlayerScreen 处理「还原到当前视频初始状态」
  final VoidCallback? onResetAspectRatio;

  /// 用户选择投屏设备回调 — 由 PlayerScreen 处理投屏启动逻辑
  final void Function(CastDevice device)? onCastDevice;

  /// 用户主动断开投屏回调 — 由 PlayerScreen 处理断开续播逻辑
  final VoidCallback? onCastDisconnect;

  /// 当前全屏模式（静态变量，在 BilibiliControls 类级别共享）
  static FullscreenMode? currentFullscreenMode;

  const BilibiliControls({
    super.key,
    required this.chewieController,
    required this.title,
    this.onEnterFullscreen,
    this.onExitFullscreen,
    this.onSwitchFullscreenMode,
    this.onUserSeek,
    this.onAspectRatioChange,
    this.onResetAspectRatio,
    this.onCastDevice,
    this.onCastDisconnect,
  });

  @override
  ConsumerState<BilibiliControls> createState() => _BilibiliControlsState();
}

class _BilibiliControlsState extends ConsumerState<BilibiliControls> {
  ChewieController get _chewieController => widget.chewieController;
  VideoPlayerController get _vpc => _chewieController.videoPlayerController;

  bool _visible = true;
  Timer? _hideTimer;
  bool _isDragging = false;
  bool _showSpeedPanel = false;
  bool _showSubtitlePanel = false;
  bool _showCastPanel = false;
  bool _showMorePanel = false;
  bool _showAspectRatioPanel = false;
  bool _showQualityPanel = false;
  bool _showDanmakuPanel = false;
  bool _showGifPanel = false;
  bool _showAudioTrackPanel = false;

  // 手势状态
  bool _isSeeking = false;
  Duration _seekDelta = Duration.zero;
  bool _isLongPressing = false;
  bool _isVolumeGesture = false;
  bool _isBrightnessGesture = false;
  double _gestureValue = 0;

  double _speedBeforeLongPress = 1.0;
  Timer? _longPressHintTimer;
  bool _showLongPressHint = false;

  @override
  void initState() {
    super.initState();
    // 初始化音量控制器监听
    VolumeController.instance.addListener((volume) {
      // 监听系统音量变化，可选：同步到播放器
    });
    _startHideTimer();

    // 监听截图/录制/GIF 错误，显示 SnackBar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(captureManagerProvider).addListener(_onCaptureError);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _longPressHintTimer?.cancel();
    VolumeController.instance.removeListener();
    try {
      ref.read(captureManagerProvider).removeListener(_onCaptureError);
    } catch (_) {}
    super.dispose();
  }

  /// 截图/录制/GIF 错误回调 — 显示 SnackBar
  void _onCaptureError() {
    if (!mounted) return;
    final manager = ref.read(captureManagerProvider);
    final error = manager.lastError;
    if (error != null) {
      // 先清除错误（静默，不触发 notifyListeners），避免连锁通知
      manager.clearError();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(PlayerControlsStyles.autoHideDelay, () {
      if (!mounted) return;
      if (!_isDragging && !_isLongPressing && !_isVolumeGesture && !_isBrightnessGesture
          && !_showSpeedPanel && !_showSubtitlePanel && !_showCastPanel && !_showAspectRatioPanel && !_showQualityPanel && !_showDanmakuPanel && !_showGifPanel && !_showAudioTrackPanel) {
        setState(() => _visible = false);
      } else {
        _startHideTimer();
      }
    });
  }

  void _toggleVisible() {
    if (!mounted) return;
    if (_showSpeedPanel || _showSubtitlePanel || _showCastPanel || _showAspectRatioPanel || _showQualityPanel || _showDanmakuPanel || _showGifPanel || _showAudioTrackPanel) {
      _dismissAllPanels();
      return;
    }
    setState(() {
      _visible = !_visible;
      if (_visible) _startHideTimer();
    });
  }

  void _dismissAllPanels() {
    if (!mounted) return;
    setState(() {
      _showSpeedPanel = false;
      _showSubtitlePanel = false;
      _showCastPanel = false;
      _showMorePanel = false;
      _showQualityPanel = false;
      _showAspectRatioPanel = false;
      _showDanmakuPanel = false;
      _showGifPanel = false;
      _showAudioTrackPanel = false;
    });
    _startHideTimer();
  }

  bool get _anyPanelOpen => _showSpeedPanel || _showSubtitlePanel || _showCastPanel || _showMorePanel || _showAspectRatioPanel || _showQualityPanel || _showDanmakuPanel || _showGifPanel || _showAudioTrackPanel;

  void _keepVisible() {
    if (!mounted) return;
    if (!_visible) setState(() => _visible = true);
    _startHideTimer();
  }

  void _onDragStart() {
    if (!mounted) return;
    setState(() => _isDragging = true);
    _hideTimer?.cancel();
  }

  void _onDragEnd() {
    if (!mounted) return;
    setState(() => _isDragging = false);
    _startHideTimer();
  }

  void _onSpeedTap() {
    if (!mounted) return;
    setState(() {
      _showSpeedPanel = !_showSpeedPanel;
      if (_showSpeedPanel) {
        _showSubtitlePanel = false;
        _showCastPanel = false;
        _showDanmakuPanel = false;
      }
    });
    if (!_showSpeedPanel) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _onSpeedSelected(double speed) {
    if (!mounted) return;
    final pb = ref.read(playbackControllerProvider);
    if (pb.state.isCasting) {
      // 投屏模式：路由到 PlaybackController（dart_cast 暂不支持 setPlaybackRate，仅记录）
      pb.setSpeed(speed);
    } else {
      _vpc.setPlaybackSpeed(speed);
    }
    setState(() => _showSpeedPanel = false);
    _startHideTimer();
  }

  void _onSubtitleTap() {
    if (!mounted) return;
    setState(() {
      _showSubtitlePanel = !_showSubtitlePanel;
      if (_showSubtitlePanel) {
        _showSpeedPanel = false;
        _showCastPanel = false;
        _showDanmakuPanel = false;
      }
    });
    if (!_showSubtitlePanel) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _onPlayPause() {
    final pb = ref.read(playbackControllerProvider);
    if (pb.state.isCasting) {
      // 投屏模式：路由到 PlaybackController
      pb.togglePlayPause();
    } else if (_vpc.value.isPlaying) {
      _chewieController.pause();
    } else {
      _chewieController.play();
    }
    _keepVisible();
  }

  // ─── 全屏 ─────────────────────────────────────────────────────────────────

  Future<void> _onPortraitFullscreen() async {
    if (!mounted) return;

    if (BilibiliControls.currentFullscreenMode == FullscreenMode.portrait) {
      widget.onExitFullscreen?.call();
      BilibiliControls.currentFullscreenMode = null;
      return;
    }

    if (BilibiliControls.currentFullscreenMode == FullscreenMode.landscape) {
      if (widget.onSwitchFullscreenMode != null) {
        await widget.onSwitchFullscreenMode!(FullscreenMode.portrait);
      } else {
        widget.onExitFullscreen?.call();
        BilibiliControls.currentFullscreenMode = null;
        await Future.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        BilibiliControls.currentFullscreenMode = FullscreenMode.portrait;
        widget.onEnterFullscreen?.call(FullscreenMode.portrait);
      }
      return;
    }

    BilibiliControls.currentFullscreenMode = FullscreenMode.portrait;
    widget.onEnterFullscreen?.call(FullscreenMode.portrait);
  }

  Future<void> _onLandscapeFullscreen() async {
    if (!mounted) return;

    if (BilibiliControls.currentFullscreenMode == FullscreenMode.landscape) {
      widget.onExitFullscreen?.call();
      BilibiliControls.currentFullscreenMode = null;
      return;
    }

    if (BilibiliControls.currentFullscreenMode == FullscreenMode.portrait) {
      if (widget.onSwitchFullscreenMode != null) {
        await widget.onSwitchFullscreenMode!(FullscreenMode.landscape);
      } else {
        widget.onExitFullscreen?.call();
        BilibiliControls.currentFullscreenMode = null;
        await Future.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        BilibiliControls.currentFullscreenMode = FullscreenMode.landscape;
        widget.onEnterFullscreen?.call(FullscreenMode.landscape);
      }
      return;
    }

    BilibiliControls.currentFullscreenMode = FullscreenMode.landscape;
    widget.onEnterFullscreen?.call(FullscreenMode.landscape);
  }

  // ─── 投屏 ─────────────────────────────────────────────────────────────────

  void _onCastTap() {
    if (!mounted) return;
    setState(() {
      _showCastPanel = !_showCastPanel;
      if (_showCastPanel) {
        _showSpeedPanel = false;
        _showSubtitlePanel = false;
        _showMorePanel = false;
        _showQualityPanel = false;
        _showDanmakuPanel = false;
      }
    });
    if (!_showCastPanel) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _onMoreTap() {
    if (!mounted) return;
    setState(() {
      _showMorePanel = !_showMorePanel;
      if (_showMorePanel) {
        _showSpeedPanel = false;
        _showSubtitlePanel = false;
        _showCastPanel = false;
        _showQualityPanel = false;
        _showDanmakuPanel = false;
      }
    });
    if (!_showMorePanel) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _onPipTap() async {
    if (!mounted) return;
    final available = await PipService.instance.isAvailable;
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前设备不支持画中画'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final success = await PipService.instance.enterPip();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法进入画中画模式'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onLongPressPortraitFullscreen() {
    if (!mounted) return;
    setState(() {
      _showAspectRatioPanel = !_showAspectRatioPanel;
      if (_showAspectRatioPanel) {
        _showSpeedPanel = false;
        _showSubtitlePanel = false;
        _showCastPanel = false;
        _showMorePanel = false;
        _showQualityPanel = false;
        _showDanmakuPanel = false;
      }
    });
    if (!_showAspectRatioPanel) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _onLongPressLandscapeFullscreen() {
    // 与竖屏长按逻辑相同：弹出同一个比例面板
    _onLongPressPortraitFullscreen();
  }

  void _onQualityTap() {
    if (!mounted) return;
    setState(() {
      _showQualityPanel = !_showQualityPanel;
      if (_showQualityPanel) {
        _showSpeedPanel = false;
        _showSubtitlePanel = false;
        _showCastPanel = false;
        _showMorePanel = false;
        _showAspectRatioPanel = false;
        _showDanmakuPanel = false;
      }
    });
    if (!_showQualityPanel) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _onDanmakuTap() {
    if (!mounted) return;
    final controller = ref.read(danmakuControllerProvider);
    if (!controller.hasData) {
      controller.isEnabled = !controller.isEnabled;
      controller.notifyUI();
      return;
    }
    setState(() {
      _showDanmakuPanel = !_showDanmakuPanel;
      if (_showDanmakuPanel) {
        _showSpeedPanel = false;
        _showSubtitlePanel = false;
        _showCastPanel = false;
        _showMorePanel = false;
        _showQualityPanel = false;
        _showAspectRatioPanel = false;
        _showAudioTrackPanel = false;
      }
    });
    if (!_showDanmakuPanel) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  bool _isSubtitleActive() {
    return _chewieController.subtitle?.isNotEmpty ?? false;
  }

  // ─── 手势回调 ──────────────────────────────────────────────────────────────

  void _onDoubleTap() {
    _onPlayPause();
  }

  void _onLongPressStart() {
    if (!mounted) return;
    // 投屏模式不支持长按倍速
    final pb = ref.read(playbackControllerProvider);
    if (pb.state.isCasting) return;
    _speedBeforeLongPress = _vpc.value.playbackSpeed;
    _vpc.setPlaybackSpeed(PlayerControlsStyles.longPressSpeed);
    setState(() {
      _isLongPressing = true;
      _showLongPressHint = true;
    });
    _hideTimer?.cancel();
    _longPressHintTimer?.cancel();
    _longPressHintTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _isLongPressing) {
        setState(() => _showLongPressHint = false);
      }
    });
  }

  void _onLongPressEnd() {
    if (!mounted) return;
    // 投屏模式下长按未启动，无需恢复
    final pb = ref.read(playbackControllerProvider);
    if (pb.state.isCasting) return;
    _vpc.setPlaybackSpeed(_speedBeforeLongPress);
    _longPressHintTimer?.cancel();
    setState(() {
      _isLongPressing = false;
      _showLongPressHint = false;
    });
    _startHideTimer();
  }

  void _onHorizontalSeekStart() {
    if (!mounted) return;
    setState(() { _isSeeking = true; _seekDelta = Duration.zero; });
    _hideTimer?.cancel();
  }

  void _onHorizontalSeekUpdate(Duration delta) {
    if (!mounted) return;
    setState(() { _seekDelta += delta; });
  }

  void _onHorizontalSeekEnd(_) {
    if (!mounted) return;
    if (_seekDelta != Duration.zero) {
      final pb = ref.read(playbackControllerProvider);
      if (pb.state.isCasting) {
        // 投屏模式：基于远端进度计算 seek 目标
        final current = pb.state.position;
        final target = current + _seekDelta;
        pb.seekTo(target);
      } else {
        final current = _vpc.value.position;
        final target = current + _seekDelta;
        widget.onUserSeek?.call(target);
        _chewieController.seekTo(target);
      }
    }
    setState(() { _isSeeking = false; _seekDelta = Duration.zero; });
    _startHideTimer();
  }

  void _onVerticalStart(bool isRight) {
    if (!mounted) return;
    setState(() {
      _isBrightnessGesture = !isRight;
      _isVolumeGesture = isRight;
      if (_isVolumeGesture) {
        _gestureValue = 0.5;
        _initSystemVolumeValue();
      } else {
        _gestureValue = 0.5;
      }
    });
    _hideTimer?.cancel();
    if (_isBrightnessGesture) {
      _initBrightnessValue();
    }
  }

  Future<void> _initBrightnessValue() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      final brightness = await ScreenBrightness().application;
      if (mounted && _isBrightnessGesture) {
        setState(() {
          _gestureValue = brightness.clamp(0.0, 1.0);
        });
      }
    } catch (_) {}
  }

  Future<void> _initSystemVolumeValue() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      final volume = await VolumeController.instance.getVolume();
      if (mounted && _isVolumeGesture) {
        setState(() {
          _gestureValue = volume.clamp(0.0, 1.0);
        });
      }
    } catch (_) {}
  }

  void _onVerticalUpdate(double delta) {
    if (!mounted) return;
    setState(() {
      _gestureValue = (_gestureValue + delta).clamp(0.0, 1.0);
    });
    if (_isVolumeGesture) {
      VolumeController.instance.showSystemUI = false;
      VolumeController.instance.setVolume(_gestureValue);
    }
    if (_isBrightnessGesture && (Platform.isIOS || Platform.isAndroid)) {
      try {
        ScreenBrightness().setApplicationScreenBrightness(_gestureValue);
      } catch (_) {}
    }
  }

  void _onVerticalEnd() {
    if (!mounted) return;
    setState(() {
      _isVolumeGesture = false;
      _isBrightnessGesture = false;
    });
    _startHideTimer();
  }

  // ─── 构建 ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final playerWidth = constraints.maxWidth;
      final playerHeight = constraints.maxHeight;
      final scale = PlayerControlsStyles.controlScale(playerWidth);
      final topMaxH = PlayerControlsStyles.topPanelMaxHeight(playerHeight);
      final bottomMaxH = PlayerControlsStyles.bottomPanelMaxHeight(playerHeight);

      return Stack(fit: StackFit.expand, children: [
      // 手势检测层（最底层，全屏覆盖）
      GestureLayer(
        onDoubleTap: _onDoubleTap,
        onLongPressStart: _onLongPressStart,
        onLongPressEnd: _onLongPressEnd,
        onHorizontalSeekStart: _onHorizontalSeekStart,
        onHorizontalSeekUpdate: _onHorizontalSeekUpdate,
        onHorizontalSeekEnd: _onHorizontalSeekEnd,
        onVerticalStart: _onVerticalStart,
        onVerticalUpdate: _onVerticalUpdate,
        onVerticalEnd: _onVerticalEnd,
        onSingleTap: _toggleVisible,
        child: const SizedBox.expand(),
      ),

      // 中央手势反馈
      if (_isSeeking || _showLongPressHint || _isVolumeGesture || _isBrightnessGesture)
        _buildGestureFeedback(),

      // 字幕覆盖层（非投屏时显示）
      if (!ref.watch(playbackControllerProvider).state.isCasting)
        _buildSubtitleOverlay(),

      // 弹幕层
      if (!ref.watch(playbackControllerProvider).state.isCasting)
        const DanmakuLayer(),

      // 录制指示器
      Consumer(builder: (context, ref, _) {
        final manager = ref.watch(captureManagerProvider);
        if (manager.captureState != CaptureState.recording) return const SizedBox.shrink();
        return Positioned(
          top: 8,
          left: 48,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text('${manager.recordDuration.inSeconds}s',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        );
      }),

      // 面板外部点击遮罩
      if (_anyPanelOpen)
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismissAllPanels,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),

      // 顶部栏
      AnimatedPositioned(
        duration: PlayerControlsStyles.controlsAnimDuration,
        top: _visible ? 0 : -PlayerControlsStyles.controlBarHeight,
        left: 0, right: 0,
        child: TopBar(
          title: widget.title,
          scale: scale,
          onBack: () {
            if (BilibiliControls.currentFullscreenMode != null) {
              if (BilibiliControls.currentFullscreenMode == FullscreenMode.portrait) {
                _onPortraitFullscreen();
              } else {
                _onLandscapeFullscreen();
              }
            } else {
              Navigator.maybePop(context);
            }
          },
          onCast: _onCastTap,
          onMore: _onMoreTap,
          castState: ref.watch(castStateProvider).valueOrNull ?? CastState.disconnected,
        ),
      ),

      // 底部栏
      AnimatedPositioned(
        duration: PlayerControlsStyles.controlsAnimDuration,
        bottom: _visible ? 0 : -(PlayerControlsStyles.controlBarHeight + 20),
        left: 0, right: 0,
        child: BottomBar(
          chewieController: _chewieController,
          scale: scale,
          onPlayPause: _onPlayPause,
          onDragStart: _onDragStart,
          onDragEnd: _onDragEnd,
          onSeek: (d) {
            final pb = ref.read(playbackControllerProvider);
            if (pb.state.isCasting) {
              pb.seekTo(d);
            } else {
              widget.onUserSeek?.call(d);
              _chewieController.seekTo(d);
            }
          },
          onSpeedTap: _onSpeedTap,
          onSubtitleTap: _onSubtitleTap,
          onEnterPortraitFullscreen: _onPortraitFullscreen,
          onEnterLandscapeFullscreen: _onLandscapeFullscreen,
          onQualityTap: _onQualityTap,
          onPipTap: _onPipTap,
          onLongPressPortraitFullscreen: _onLongPressPortraitFullscreen,
          onLongPressLandscapeFullscreen: _onLongPressLandscapeFullscreen,
          isPipAvailable: ref.watch(pipAvailableProvider).valueOrNull ?? false,
          onDanmakuTap: _onDanmakuTap,
          currentFullscreenMode: BilibiliControls.currentFullscreenMode,
          isSubtitleActive: _isSubtitleActive(),
        ),
      ),

      // 中央播放/暂停按钮 + 缓冲指示器
      if (_visible)
        Center(
          child: _buildCenterPlayButton(),
        ),

      // 非可见状态下的缓冲指示器
      if (!_visible)
        _buildInvisibleBufferingIndicator(),

      // 倍速面板
      if (_showSpeedPanel)
        Positioned(
          right: 8,
          bottom: PlayerControlsStyles.controlBarHeight + 8,
          child: SpeedPanel(
            currentSpeed: ref.watch(playbackControllerProvider).state.speed,
            onSelected: _onSpeedSelected,
            onDismiss: () {
              if (!mounted) return;
              setState(() => _showSpeedPanel = false);
              _startHideTimer();
            },
            scale: scale,
            maxHeight: bottomMaxH,
            playerWidth: playerWidth,
          ),
        ),

      // 字幕面板
      if (_showSubtitlePanel)
        Positioned(
          right: 8,
          bottom: PlayerControlsStyles.controlBarHeight + 8,
          child: SubtitlePanel(
            onDismiss: () {
              if (!mounted) return;
              setState(() => _showSubtitlePanel = false);
              _startHideTimer();
            },
            scale: scale,
            maxHeight: bottomMaxH,
            playerWidth: playerWidth,
          ),
        ),

      // 投屏面板
      if (_showCastPanel)
        Positioned(
          right: 8,
          top: PlayerControlsStyles.controlBarHeight + 4,
          child: CastPanel(
            onDismiss: () {
              if (!mounted) return;
              setState(() => _showCastPanel = false);
              _startHideTimer();
            },
            onDeviceSelected: (device) {
              widget.onCastDevice?.call(device);
            },
            onDisconnect: () {
              widget.onCastDisconnect?.call();
            },
            scale: scale,
            maxHeight: topMaxH,
            playerWidth: playerWidth,
          ),
        ),

        // 更多面板
        if (_showMorePanel)
          Positioned(
            right: 8,
            top: PlayerControlsStyles.controlBarHeight + 4,
            child: MorePanel(
              onDismiss: () {
                if (!mounted) return;
                setState(() => _showMorePanel = false);
                _startHideTimer();
              },
              onOpenGifPanel: () {
                if (!mounted) return;
                setState(() {
                  _showGifPanel = true;
                  _showMorePanel = false;
                });
                _hideTimer?.cancel();
              },
              onOpenAudioTrackPanel: () {
                if (!mounted) return;
                setState(() {
                  _showAudioTrackPanel = true;
                  _showMorePanel = false;
                });
                _hideTimer?.cancel();
              },
              scale: scale,
              maxHeight: topMaxH,
              playerWidth: playerWidth,
            ),
          ),

        // 清晰度面板
        if (_showQualityPanel)
          Positioned(
            right: 8,
            bottom: PlayerControlsStyles.controlBarHeight + 8,
            child: QualityPanel(
              onDismiss: () {
                if (!mounted) return;
                setState(() => _showQualityPanel = false);
                _startHideTimer();
              },
              scale: scale,
              maxHeight: bottomMaxH,
              playerWidth: playerWidth,
            ),
          ),

        // 弹幕设置面板
        if (_showDanmakuPanel)
          Positioned(
            right: 8,
            bottom: PlayerControlsStyles.controlBarHeight + 8,
            child: DanmakuPanel(
              onDismiss: () {
                if (!mounted) return;
                setState(() => _showDanmakuPanel = false);
                _startHideTimer();
              },
              scale: scale,
              maxHeight: bottomMaxH,
              playerWidth: playerWidth,
            ),
          ),

        // 画面比例面板
        if (_showAspectRatioPanel)
          Positioned(
            right: 8,
            bottom: PlayerControlsStyles.controlBarHeight + 8,
            child: AspectRatioPanel(
              current: ref.watch(displayAspectRatioProvider),
              options: BilibiliControls.currentFullscreenMode == FullscreenMode.portrait
                  ? DisplayAspectRatio.portraitOptions
                  : DisplayAspectRatio.landscapeOptions,
              onSelected: (ratio) {
                if (!mounted) return;
                if (ratio == DisplayAspectRatio.reset) {
                  // 「还原」= 回到当前视频初始比例（自适应），由 PlayerScreen 处理
                  widget.onResetAspectRatio?.call();
                } else {
                  ref.read(displayAspectRatioProvider.notifier).setRatio(ratio);
                  widget.onAspectRatioChange?.call(ratio);
                }
                setState(() => _showAspectRatioPanel = false);
                _startHideTimer();
              },
              onDismiss: () {
                if (!mounted) return;
                setState(() => _showAspectRatioPanel = false);
                _startHideTimer();
              },
              scale: scale,
              maxHeight: bottomMaxH,
              playerWidth: playerWidth,
            ),
          ),

      // GIF 设置面板
      if (_showGifPanel)
        Positioned(
          right: 8,
          bottom: PlayerControlsStyles.controlBarHeight + 8,
          child: Builder(builder: (context) {
            // 优先使用录制文件（本地 mp4），网络流 URL 不能直接传给 ffmpeg
            final captureManager = ref.read(captureManagerProvider);
            final videoPath = captureManager.lastRecording?.filePath
                ?? _effectiveVideoPath(captureManager.currentVideoPath);
            return GifSettingsPanel(
              videoPath: videoPath,
              videoDuration: captureManager.currentVideoDuration
                  ?? captureManager.lastRecording?.duration
                  ?? _vpc.value.duration,
              onDismiss: () {
                if (!mounted) return;
                setState(() => _showGifPanel = false);
                _startHideTimer();
              },
              scale: scale,
              maxHeight: bottomMaxH,
              playerWidth: playerWidth,
            );
          }),
        ),

      // 音轨选择面板
      if (_showAudioTrackPanel)
        Positioned(
          right: 8,
          bottom: PlayerControlsStyles.controlBarHeight + 8,
          child: AudioTrackPanel(
            onDismiss: () {
              if (!mounted) return;
              setState(() => _showAudioTrackPanel = false);
              _startHideTimer();
            },
            scale: scale,
            maxHeight: bottomMaxH,
            playerWidth: playerWidth,
          ),
        ),

      // 截图/录制/GIF 预览浮层
      Consumer(builder: (context, ref, _) {
        final manager = ref.watch(captureManagerProvider);
        if (manager.lastScreenshot == null && manager.lastRecording == null && manager.lastGifPath == null) {
          return const SizedBox.shrink();
        }
        return CapturePreviewOverlay(
          onGenerateGif: () {
            if (!mounted) return;
            setState(() {
              _showGifPanel = true;
            });
            _hideTimer?.cancel();
          },
        );
      }),
    ]);
    });
  }

  /// 中央播放/暂停按钮 + 缓冲指示器（投屏时从 PlaybackController 读取状态）
  Widget _buildCenterPlayButton() {
    final pb = ref.watch(playbackControllerProvider);
    final state = pb.state;

    if (state.isCasting) {
      // 投屏模式：从 PlaybackState 读取
      if (state.isBuffering) {
        return GestureDetector(
          onTap: _onPlayPause,
          child: const CircularProgressIndicator(
            color: PlayerControlsStyles.progressPlayed,
            strokeWidth: 2.5,
          ),
        );
      }
      return GestureDetector(
        onTap: _onPlayPause,
        child: _buildPlayButton(isPlaying: state.isPlaying),
      );
    }

    // 本地模式：从 VideoPlayerController 读取
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _vpc,
      builder: (_, value, _) {
        if (value.isBuffering) {
          return GestureDetector(
            onTap: _onPlayPause,
            child: const CircularProgressIndicator(
              color: PlayerControlsStyles.progressPlayed,
              strokeWidth: 2.5,
            ),
          );
        }
        if (!value.isPlaying) {
          return GestureDetector(
            onTap: _onPlayPause,
            child: _buildPlayButton(isPlaying: false),
          );
        }
        return GestureDetector(
          onTap: _onPlayPause,
          child: _buildPlayButton(isPlaying: true),
        );
      },
    );
  }

  /// 非可见状态下的缓冲指示器（投屏时从 PlaybackController 读取状态）
  Widget _buildInvisibleBufferingIndicator() {
    final pb = ref.watch(playbackControllerProvider);
    final state = pb.state;

    if (state.isCasting) {
      if (!state.isBuffering) return const SizedBox.shrink();
      return const Center(child: CircularProgressIndicator(
        color: PlayerControlsStyles.progressPlayed,
        strokeWidth: 2.5,
      ));
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _vpc,
      builder: (_, value, _) {
        if (!value.isBuffering) return const SizedBox.shrink();
        return const Center(child: CircularProgressIndicator(
          color: PlayerControlsStyles.progressPlayed,
          strokeWidth: 2.5,
        ));
      },
    );
  }

  Widget _buildPlayButton({required bool isPlaying}) {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: PlayerControlsStyles.gestureBg.withValues(alpha: isPlaying ? 0.5 : 1.0),
        borderRadius: BorderRadius.circular(28),
      ),
      alignment: Alignment.center,
      child: Icon(
        isPlaying ? Icons.pause : Icons.play_arrow,
        color: PlayerControlsStyles.iconColor,
        size: 32,
      ),
    );
  }

  Widget _buildSubtitleOverlay() {
    final manager = ref.watch(subtitleManagerProvider);
    if (manager.activeTrack == null) return const SizedBox.shrink();
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _vpc,
      builder: (_, value, _) {
        return SubtitleWidgetOverlay(
          manager: manager,
          position: value.position,
        );
      },
    );
  }

  Widget _buildGestureFeedback() {
    return Center(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: PlayerControlsStyles.gestureBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: _buildGestureContent(),
    ));
  }

  Widget _buildGestureContent() {
    if (_showLongPressHint) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.fast_forward, color: PlayerControlsStyles.iconColor, size: PlayerControlsStyles.gestureIconSize),
        const SizedBox(width: 8),
        Text('${PlayerControlsStyles.longPressSpeed.toInt()}x 倍速播放中',
            style: const TextStyle(color: PlayerControlsStyles.textColor, fontSize: PlayerControlsStyles.gestureTextSize)),
      ]);
    }
    if (_isVolumeGesture) {
      final vol = (_gestureValue * 100).round();
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(vol > 0 ? Icons.volume_up : Icons.volume_off,
            color: PlayerControlsStyles.iconColor, size: PlayerControlsStyles.gestureIconSize),
        const SizedBox(height: 4),
        Text('$vol%',
            style: const TextStyle(color: PlayerControlsStyles.textColor, fontSize: PlayerControlsStyles.gestureTextSize)),
      ]);
    }
    if (_isBrightnessGesture) {
      final pct = (_gestureValue * 100).round();
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(pct > 50 ? Icons.brightness_high : Icons.brightness_low,
            color: PlayerControlsStyles.iconColor, size: PlayerControlsStyles.gestureIconSize),
        const SizedBox(height: 4),
        Text('$pct%',
            style: const TextStyle(color: PlayerControlsStyles.textColor, fontSize: PlayerControlsStyles.gestureTextSize)),
      ]);
    }
    if (_isSeeking) {
      final seconds = _seekDelta.inSeconds;
      final isForward = seconds > 0;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isForward ? Icons.fast_forward : Icons.fast_rewind,
            color: PlayerControlsStyles.iconColor, size: PlayerControlsStyles.gestureIconSize),
        const SizedBox(width: 8),
        Text('${isForward ? '+' : ''}$seconds 秒',
            style: const TextStyle(color: PlayerControlsStyles.textColor, fontSize: PlayerControlsStyles.gestureTextSize)),
      ]);
    }
    return const SizedBox.shrink();
  }
  /// 获取有效的本地视频路径（排除网络流 URL）
  /// 网络流 URL（http/https）不能直接传给 ffmpeg，需从录制文件生成 GIF
  String _effectiveVideoPath(String? currentPath) {
    if (currentPath != null &&
        !currentPath.startsWith('http://') &&
        !currentPath.startsWith('https://')) {
      return currentPath;
    }
    return '';
  }
}
