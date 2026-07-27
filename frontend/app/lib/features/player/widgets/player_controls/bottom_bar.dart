import 'dart:math' show pi;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../playback/playback_provider.dart';
import '../../quality/quality_provider.dart';
import '../../quality/quality_level.dart';
import '../../danmaku/danmaku_provider.dart';
import 'styles.dart';
import 'controls_overlay.dart' show FullscreenMode;

/// 底部控制栏：进度条(含时间) + 播放/暂停 + 清晰度 + 倍速 + 字幕 + 全屏
class BottomBar extends ConsumerStatefulWidget {
  final ChewieController chewieController;
  final double scale;
  final VoidCallback onPlayPause;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final void Function(Duration position) onSeek;
  final VoidCallback onSpeedTap;
  final VoidCallback onSubtitleTap;
  final VoidCallback onEnterPortraitFullscreen;
  final VoidCallback onEnterLandscapeFullscreen;
  final VoidCallback onQualityTap;
  final VoidCallback onDanmakuTap;
  final VoidCallback onPipTap;
  final VoidCallback? onLongPressPortraitFullscreen;
  final VoidCallback? onLongPressLandscapeFullscreen;
  final FullscreenMode? currentFullscreenMode;
  final bool isSubtitleActive;
  final bool isPipAvailable;

  const BottomBar({
    super.key,
    required this.chewieController,
    required this.scale,
    required this.onPlayPause,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onSeek,
    required this.onSpeedTap,
    required this.onSubtitleTap,
    required this.onEnterPortraitFullscreen,
    required this.onEnterLandscapeFullscreen,
    required this.onQualityTap,
    required this.onDanmakuTap,
    required this.onPipTap,
    this.onLongPressPortraitFullscreen,
    this.onLongPressLandscapeFullscreen,
    this.currentFullscreenMode,
    this.isSubtitleActive = false,
    this.isPipAvailable = false,
  });

  @override
  ConsumerState<BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends ConsumerState<BottomBar> {
  VideoPlayerController get _vpc => widget.chewieController.videoPlayerController;
  double get scale => widget.scale;

  bool _isDragging = false;
  double _dragProgress = 0.0;

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _onProgressBarTap(double progress) {
    final pbState = ref.read(playbackControllerProvider).state;
    final duration = pbState.isCasting ? pbState.duration : _vpc.value.duration;
    if (duration.inMilliseconds == 0) return;
    widget.onSeek(Duration(milliseconds: (duration.inMilliseconds * progress).round()));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [PlayerControlsStyles.gradientEnd, PlayerControlsStyles.gradientStart],
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 进度条 + 两侧时间
        _buildProgressBarWithTime(),
        // 按钮行（按钮空间紧贴图标/文字，无内外边框，图标间无额外间距）
        SizedBox(
          height: PlayerControlsStyles.scaledSize(PlayerControlsStyles.controlBarHeight, scale, 33),
          child: Row(children: [
            // 播放/暂停
            _buildPlayPauseButton(),
            const Spacer(),
            // 右侧按钮组：所有按钮紧邻排列，无间距
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildQualityButton(),
                _buttonSpacing(),
                _buildSpeedButton(),
                // _buttonSpacing(),
                // // 字幕
                // _buildIconButton(
                //   icon: Icon(
                //     widget.isSubtitleActive ? Icons.subtitles : Icons.subtitles_outlined,
                //     color: widget.isSubtitleActive ? PlayerControlsStyles.subtitleActive : PlayerControlsStyles.subtitleInactive,
                //     size: PlayerControlsStyles.scaledSize(PlayerControlsStyles.iconSize, scale, 18),
                //   ),
                //   onPressed: widget.onSubtitleTap,
                // ),
                // _buttonSpacing(),
                // // 弹幕
                // _buildDanmakuButton(),
                _buttonSpacing(),
                _buildPipButton(),
                _buttonSpacing(),
                _buildLongPressIconButton(
                  icon: Transform.rotate(
                    angle: pi / 4,
                    child: SvgPicture.asset(
                      widget.currentFullscreenMode == FullscreenMode.portrait
                          ? 'assets/images/shrink.svg'
                          : 'assets/images/expand.svg',
                      colorFilter: ColorFilter.mode(PlayerControlsStyles.iconColor, BlendMode.srcIn),
                      // 竖屏全屏图标缩小至 80%（iconSize 24.0 -> 19.2）
                      width: PlayerControlsStyles.scaledSize(PlayerControlsStyles.iconSize * 0.8, scale, 14),
                      height: PlayerControlsStyles.scaledSize(PlayerControlsStyles.iconSize * 0.8, scale, 14),
                    ),
                  ),
                  onPressed: widget.onEnterPortraitFullscreen,
                  onLongPress: widget.onLongPressPortraitFullscreen,
                ),
                _buttonSpacing(),
                _buildLongPressIconButton(
                  icon: SvgPicture.asset(
                    widget.currentFullscreenMode == FullscreenMode.landscape
                        ? 'assets/images/shrink.svg'
                        : 'assets/images/expand.svg',
                    colorFilter: ColorFilter.mode(PlayerControlsStyles.iconColor, BlendMode.srcIn),
                    // 横屏全屏图标缩小至 80%（iconSize 24.0 -> 19.2）
                    width: PlayerControlsStyles.scaledSize(PlayerControlsStyles.iconSize * 0.8, scale, 14),
                    height: PlayerControlsStyles.scaledSize(PlayerControlsStyles.iconSize * 0.8, scale, 14),
                  ),
                  onPressed: widget.onEnterLandscapeFullscreen,
                  onLongPress: widget.onLongPressLandscapeFullscreen,
                ),
              ],
            ),
          ]),
        ),
      ]),
    );
  }

  /// 统一构建控制按钮：用 GestureDetector+Center 取代 IconButton，
  /// 彻底规避 IconButton 内部 kMinInteractiveDimension(48px) 最小点击区域约束，
  /// 让按钮宽度严格等于图标宽度，实现与文字按钮一致的零间距紧凑排列。
  ///
  /// 外层 2px padding 使图标与文字按钮保持一致的视觉间距。
  Widget _buildIconButton({
    required Widget icon,
    required VoidCallback? onPressed,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Padding(
        padding: EdgeInsets.all(PlayerControlsStyles.scaledSize(4, scale, 3)),
        child: Center(child: icon),
      ),
    );
  }

  Widget _buildLongPressIconButton({
    required Widget icon,
    required VoidCallback? onPressed,
    required VoidCallback? onLongPress,
  }) {
    // 无长按回调时退化为普通按钮，避免 LongPressGestureRecognizer 参与
    // 竞技场导致 Tap 响应延迟 800ms
    if (onLongPress == null) {
      return _buildIconButton(icon: icon, onPressed: onPressed);
    }
    return RawGestureDetector(
      gestures: {
        TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(),
          (TapGestureRecognizer instance) {
            instance.onTap = onPressed;
          },
        ),
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 800)),
          (LongPressGestureRecognizer instance) {
            instance.onLongPress = onLongPress;
          },
        ),
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.all(PlayerControlsStyles.scaledSize(4, scale, 3)),
        child: Center(child: icon),
      ),
    );
  }

  Widget _buttonSpacing() {
  return SizedBox(width: PlayerControlsStyles.scaledSize(8, scale, 6));
}

  Widget _buildPlayPauseButton() {
    final pbState = ref.watch(playbackControllerProvider).state;
    if (pbState.isCasting) {
      return _buildIconButton(
        icon: Icon(
          pbState.isPlaying ? Icons.pause : Icons.play_arrow,
          color: PlayerControlsStyles.iconColor,
          size: PlayerControlsStyles.scaledSize(PlayerControlsStyles.iconSize, scale, 18),
        ),
        onPressed: widget.onPlayPause,
      );
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _vpc,
      builder: (_, value, _) {
        return _buildIconButton(
          icon: Icon(
            value.isPlaying ? Icons.pause : Icons.play_arrow,
            color: PlayerControlsStyles.iconColor,
            size: PlayerControlsStyles.scaledSize(PlayerControlsStyles.iconSize, scale, 18),
          ),
          onPressed: widget.onPlayPause,
        );
      },
    );
  }

  Widget _buildQualityButton() {
    final manager = ref.watch(qualityManagerProvider);
    // 隐藏条件：既没有解析到清晰度等级，也不是默认模式
    if (manager.levels.isEmpty && !manager.isDefault) return const SizedBox.shrink();

    final label = manager.currentLabel;
    final isAuto = manager.mode == QualityMode.auto;
    final isDefault = manager.isDefault;
    // 容器宽度收紧到刚好包裹文字：无固定高度、无 maxWidth 约束，外层 padding 与图标按钮保持一致间距
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isDefault ? null : widget.onQualityTap,
      child: Padding(
        padding: EdgeInsets.all(PlayerControlsStyles.scaledSize(4, scale, 3)),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: isDefault
                  ? PlayerControlsStyles.textSecondary
                  : isAuto
                      ? PlayerControlsStyles.textSecondary
                      : PlayerControlsStyles.qualityActive,
              fontSize: PlayerControlsStyles.scaledSize(PlayerControlsStyles.qualityTextSize, scale, 9),
              fontWeight: isDefault || isAuto ? FontWeight.normal : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDanmakuButton() {
    final controller = ref.watch(danmakuControllerProvider);
    final isActive = controller.isEnabled && controller.hasData;
    return _buildIconButton(
      icon: Icon(
        isActive ? Icons.comment : Icons.comment_outlined,
        color: isActive ? PlayerControlsStyles.danmakuActive : PlayerControlsStyles.danmakuInactive,
        size: PlayerControlsStyles.scaledSize(PlayerControlsStyles.iconSize, scale, 18),
      ),
      onPressed: widget.onDanmakuTap,
    );
  }

  Widget _buildPipButton() {
    if (!widget.isPipAvailable) return const SizedBox.shrink();
    return _buildIconButton(
      icon: Icon(
        Icons.picture_in_picture_alt,
        color: PlayerControlsStyles.textSecondary,
        size: PlayerControlsStyles.scaledSize(PlayerControlsStyles.iconSize, scale, 18),
      ),
      onPressed: widget.onPipTap,
    );
  }

  Widget _buildSpeedButton() {
    final pbState = ref.watch(playbackControllerProvider).state;
    if (pbState.isCasting) {
      final speed = pbState.speed;
      final label = speed == 1.0 ? '倍速' : '${speed}x';
      // 容器宽度收紧到刚好包裹文字：无固定高度、无 maxWidth 约束，单行完整显示"倍速"，外层 padding 与图标按钮保持一致间距
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSpeedTap,
        child: Padding(
          padding: EdgeInsets.all(PlayerControlsStyles.scaledSize(4, scale, 3)),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: speed == 1.0
                    ? PlayerControlsStyles.textSecondary
                    : PlayerControlsStyles.speedActive,
                fontSize: PlayerControlsStyles.scaledSize(PlayerControlsStyles.speedTextSize, scale, 9),
                fontWeight: speed == 1.0 ? FontWeight.normal : FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _vpc,
      builder: (_, value, _) {
        final speed = value.playbackSpeed;
        final label = speed == 1.0 ? '倍速' : '${speed}x';
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSpeedTap,
          child: Padding(
            padding: EdgeInsets.all(PlayerControlsStyles.scaledSize(4, scale, 3)),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: speed == 1.0
                      ? PlayerControlsStyles.textSecondary
                      : PlayerControlsStyles.speedActive,
                  fontSize: PlayerControlsStyles.scaledSize(PlayerControlsStyles.speedTextSize, scale, 9),
                  fontWeight: speed == 1.0 ? FontWeight.normal : FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressBarWithTime() {
    final pbState = ref.watch(playbackControllerProvider).state;
    if (pbState.isCasting) {
      final position = pbState.position;
      final duration = pbState.duration;
      final progress = duration.inMilliseconds > 0
          ? position.inMilliseconds / duration.inMilliseconds
          : 0.0;
      final displayProgress = _isDragging ? _dragProgress : progress;

      return _ProgressBarWithTime(
        progress: displayProgress.clamp(0.0, 1.0),
        buffered: 0.0,
        isDragging: _isDragging,
        position: _formatDuration(position),
        duration: _formatDuration(duration),
        scale: scale,
        onTap: _onProgressBarTap,
        onDragStart: (p) {
          setState(() { _isDragging = true; _dragProgress = p; });
          widget.onDragStart();
        },
        onDragUpdate: (p) => setState(() => _dragProgress = p),
        onDragEnd: () {
          _onProgressBarTap(_dragProgress);
          setState(() { _isDragging = false; });
          widget.onDragEnd();
        },
      );
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _vpc,
      builder: (_, value, _) {
        final position = value.position;
        final duration = value.duration;
        final buffer = value.buffered.isNotEmpty ? value.buffered.last.end : Duration.zero;

        final progress = duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;
        final bufferProgress = duration.inMilliseconds > 0
            ? buffer.inMilliseconds / duration.inMilliseconds
            : 0.0;

        final displayProgress = _isDragging ? _dragProgress : progress;

        return _ProgressBarWithTime(
          progress: displayProgress.clamp(0.0, 1.0),
          buffered: bufferProgress.clamp(0.0, 1.0),
          isDragging: _isDragging,
          position: _formatDuration(position),
          duration: _formatDuration(duration),
          scale: scale,
          onTap: _onProgressBarTap,
          onDragStart: (p) {
            setState(() { _isDragging = true; _dragProgress = p; });
            widget.onDragStart();
          },
          onDragUpdate: (p) => setState(() => _dragProgress = p),
          onDragEnd: () {
            _onProgressBarTap(_dragProgress);
            setState(() { _isDragging = false; });
            widget.onDragEnd();
          },
        );
      },
    );
  }
}

/// B站风格进度条
class _ProgressBar extends StatelessWidget {
  final double progress;
  final double buffered;
  final bool isDragging;
  final void Function(double progress) onTap;
  final void Function(double progress) onDragStart;
  final void Function(double progress) onDragUpdate;
  final VoidCallback onDragEnd;

  const _ProgressBar({
    required this.progress,
    required this.buffered,
    required this.isDragging,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final height = isDragging
        ? PlayerControlsStyles.progressBarDragHeight
        : PlayerControlsStyles.progressBarHeight;
    final thumbSize = isDragging
        ? PlayerControlsStyles.progressThumbDragSize
        : PlayerControlsStyles.progressThumbSize;

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (details) {
          final p = (details.localPosition.dx / width).clamp(0.0, 1.0);
          onDragStart(p);
        },
        onHorizontalDragUpdate: (details) {
          final box = context.findRenderObject() as RenderBox;
          final local = box.globalToLocal(details.globalPosition);
          final p = (local.dx / box.size.width).clamp(0.0, 1.0);
          onDragUpdate(p);
        },
        onHorizontalDragEnd: (_) => onDragEnd(),
        onTapUp: (details) {
          final p = (details.localPosition.dx / width).clamp(0.0, 1.0);
          onTap(p);
        },
        child: Container(
          height: isDragging ? 24.0 : 12.0,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              height: height,
              decoration: BoxDecoration(
                color: PlayerControlsStyles.progressTrack,
                borderRadius: BorderRadius.circular(height / 2),
              ),
            ),
            FractionallySizedBox(
              widthFactor: buffered,
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: PlayerControlsStyles.progressBuffered,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
            FractionallySizedBox(
              widthFactor: progress,
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: PlayerControlsStyles.progressPlayed,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
            if (isDragging || progress > 0)
              Positioned(
                left: progress * width - thumbSize / 2,
                top: 0,
                bottom: 0,
                child: Center(child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    color: PlayerControlsStyles.progressThumb,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: PlayerControlsStyles.progressThumb.withValues(alpha: 0.4), blurRadius: 4)],
                  ),
                )),
              ),
          ]),
        ),
      );
    });
  }
}

/// 进度条 + 两侧时间
class _ProgressBarWithTime extends StatelessWidget {
  final double progress;
  final double buffered;
  final bool isDragging;
  final String position;
  final String duration;
  final double scale;
  final void Function(double progress) onTap;
  final void Function(double progress) onDragStart;
  final void Function(double progress) onDragUpdate;
  final VoidCallback onDragEnd;

  const _ProgressBarWithTime({
    required this.progress,
    required this.buffered,
    required this.isDragging,
    required this.position,
    required this.duration,
    required this.scale,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: PlayerControlsStyles.scaledSize(16, scale, 12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: PlayerControlsStyles.scaledSize(48, scale, 36),
            child: Text(
              position,
              style: TextStyle(
                color: PlayerControlsStyles.textSecondary,
                fontSize: PlayerControlsStyles.scaledSize(PlayerControlsStyles.timeTextSize, scale, 9),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _ProgressBar(
            progress: progress,
            buffered: buffered,
            isDragging: isDragging,
            onTap: onTap,
            onDragStart: onDragStart,
            onDragUpdate: onDragUpdate,
            onDragEnd: onDragEnd,
          )),
          const SizedBox(width: 8),
          SizedBox(
            width: PlayerControlsStyles.scaledSize(48, scale, 36),
            child: Text(
              duration,
              style: TextStyle(
                color: PlayerControlsStyles.textSecondary,
                fontSize: PlayerControlsStyles.scaledSize(PlayerControlsStyles.timeTextSize, scale, 9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
