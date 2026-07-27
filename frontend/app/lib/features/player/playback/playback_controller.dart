import 'dart:async';
import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../cast/cast_service.dart';
import '../../../core/logger/app_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlaybackState — 统一播放状态模型
// ─────────────────────────────────────────────────────────────────────────────

/// 对 UI 暴露的统一播放状态，屏蔽本地/远端差异。
///
/// [isCasting] 为 true 时，[position]/[duration]/[isPlaying] 取自远端会话；
/// 否则取自本地 VideoPlayerController。
class PlaybackState {
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final double speed;
  final bool isCasting;
  final String? castDeviceName;
  final double volume; // 远端音量（0.0-1.0），投屏时从 CastSession 回读

  const PlaybackState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.isCasting = false,
    this.castDeviceName,
    this.volume = 1.0,
  });

  PlaybackState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    double? speed,
    bool? isCasting,
    String? castDeviceName,
    double? volume,
  }) {
    return PlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      isCasting: isCasting ?? this.isCasting,
      castDeviceName: castDeviceName ?? this.castDeviceName,
      volume: volume ?? this.volume,
    );
  }

  @override
  String toString() => 'PlaybackState(playing:$isPlaying, buffering:$isBuffering, '
      'pos:$position, dur:$duration, speed:$speed, casting:$isCasting, '
      'device:$castDeviceName, vol:$volume)';
}

// ─────────────────────────────────────────────────────────────────────────────
// PlaybackController — 统一播放抽象层
// ─────────────────────────────────────────────────────────────────────────────

/// 对 UI 暴露统一的 [PlaybackState] 流与命令接口，
/// 内部按 [isCasting] 在本地 [ChewieController] 与远端 [MeowCastService] 之间路由。
///
/// UI 层（controls_overlay / bottom_bar）只依赖此抽象层，
/// 不再直接碰 VideoPlayerController。
class PlaybackController extends ChangeNotifier {
  /// 本地 ChewieController 的动态引用（由 PlayerScreen 持有并更新）
  final ValueNotifier<ChewieController?> chewieNotifier;

  /// 投屏服务
  final MeowCastService castService;

  PlaybackController({
    required this.chewieNotifier,
    required this.castService,
  }) {
    // 监听本地 controller 变化
    chewieNotifier.addListener(_onLocalControllerChanged);
    _onLocalControllerChanged(); // 初始同步

    // 监听投屏状态变化
    _castStateSub = castService.stateStream.listen(_onCastStateChanged);

    // 监听远端进度/时长/音量流
    _castPosSub = castService.positionStream.listen(_onCastPosition);
    _castDurSub = castService.durationStream.listen(_onCastDuration);
    _castVolSub = castService.volumeStream.listen(_onCastVolume);
  }

  // ─── 当前状态 ──────────────────────────────────────────────────────────────

  PlaybackState _state = const PlaybackState();
  PlaybackState get state => _state;

  /// 标记是否已销毁，防止 dispose 后 pause 等操作触发 notifyListeners
  /// 导致 Riverpod 抛出 "Tried to modify a provider while the widget tree was building"。
  bool _disposed = false;

  // ─── 订阅管理 ──────────────────────────────────────────────────────────────

  StreamSubscription<CastState>? _castStateSub;
  StreamSubscription<Duration>? _castPosSub;
  StreamSubscription<Duration>? _castDurSub;
  StreamSubscription<double>? _castVolSub;
  VoidCallback? _localVpcListener;
  VideoPlayerController? _lastListenedVpc;

  // ─── 本地 controller 变化回调 ─────────────────────────────────────────────

  void _onLocalControllerChanged() {
    // 先从旧 VPC 摘除监听。
    // 修复：原代码仅 `_localVpcListener?.call()` 调用了一次旧回调，
    // 从未真正 removeListener，导致切集/切清晰度时旧 VPC 监听永久残留，
    // dispose 路径中 pause 触发的 notifyListeners 仍会沿旧链路传递。
    if (_lastListenedVpc != null && _localVpcListener != null) {
      _lastListenedVpc!.removeListener(_localVpcListener!);
    }

    final cc = chewieNotifier.value;
    if (cc != null) {
      _localVpcListener = () {
        if (!_state.isCasting) {
          _syncFromLocal();
        }
      };
      _lastListenedVpc = cc.videoPlayerController;
      cc.videoPlayerController.addListener(_localVpcListener!);
      _syncFromLocal(); // 立即同步一次
    } else {
      _localVpcListener = null;
      _lastListenedVpc = null;
    }
  }

  /// 从本地 VideoPlayerController 同步状态
  void _syncFromLocal() {
    final cc = chewieNotifier.value;
    if (cc == null) return;
    final vpc = cc.videoPlayerController;
    final value = vpc.value;
    _state = _state.copyWith(
      isPlaying: value.isPlaying,
      isBuffering: value.isBuffering,
      position: value.position,
      duration: value.duration,
      speed: value.playbackSpeed,
      isCasting: false,
      castDeviceName: null,
    );
    notifyListeners();
  }

  // ─── 投屏状态变化回调 ─────────────────────────────────────────────────────

  void _onCastStateChanged(CastState castState) {
    final isCasting = castState == CastState.playing ||
        castState == CastState.paused ||
        castState == CastState.buffering ||
        castState == CastState.loading ||
        castState == CastState.connected;

    final isPlaying = castState == CastState.playing;
    final isBuffering = castState == CastState.buffering || castState == CastState.loading;

    _state = _state.copyWith(
      isCasting: isCasting,
      isPlaying: isCasting ? isPlaying : _state.isPlaying,
      isBuffering: isCasting ? isBuffering : _state.isBuffering,
      castDeviceName: isCasting ? (castService.connectedDevice?.name ?? '') : null,
    );

    // 投屏断开时切回本地源同步 + 重置音量
    if (!isCasting && castState == CastState.disconnected) {
      _state = _state.copyWith(volume: 1.0);
      _syncFromLocal();
    }

    notifyListeners();
  }

  void _onCastPosition(Duration pos) {
    if (_state.isCasting) {
      _state = _state.copyWith(position: pos);
      notifyListeners();
    }
  }

  void _onCastDuration(Duration dur) {
    if (_state.isCasting) {
      _state = _state.copyWith(duration: dur);
      notifyListeners();
    }
  }

  void _onCastVolume(double vol) {
    if (_state.isCasting) {
      _state = _state.copyWith(volume: vol);
      notifyListeners();
    }
  }

  // ─── 统一命令接口 ─────────────────────────────────────────────────────────

  /// 播放（投屏中路由到远端，否则本地）
  Future<void> play() async {
    if (castService.isCasting) {
      await castService.play();
    } else {
      chewieNotifier.value?.play();
    }
  }

  /// 暂停
  Future<void> pause() async {
    if (castService.isCasting) {
      await castService.pause();
    } else {
      chewieNotifier.value?.pause();
    }
  }

  /// 播放/暂停切换
  Future<void> togglePlayPause() async {
    if (_state.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// 跳转到指定位置
  Future<void> seekTo(Duration position) async {
    if (castService.isCasting) {
      await castService.seek(position);
    } else {
      await chewieNotifier.value?.videoPlayerController.seekTo(position);
    }
  }

  /// 设置播放倍速
  ///
  /// 注意：远端倍速支持取决于协议（DLNA/Chromecast 可设 playbackRate，
  /// AirPlay 不一定支持）。对不支持的协议在投屏时降级为 no-op + 日志。
  Future<void> setSpeed(double speed) async {
    if (castService.isCasting) {
      // 远端倍速：dart_cast 的 CastSession 暂未暴露 setPlaybackRate，
      // 目前降级为 no-op + 日志。后续 dart_cast 版本支持后补充。
      appLogger.i('[PlaybackController] 投屏倍速设置暂不支持: $speed');
      return;
    }
    chewieNotifier.value?.videoPlayerController.setPlaybackSpeed(speed);
  }

  /// 设置音量（0.0-1.0，仅投屏时有效，本地音量由系统控制）
  Future<void> setVolume(double volume) async {
    if (castService.isCasting) {
      await castService.setVolume(volume);
    }
    // 本地播放不通过此接口设音量（由 VolumeController 插件管理）
  }

  // ─── 生命周期 ─────────────────────────────────────────────────────────────

  /// 覆写 notifyListeners：dispose 后不再通知，避免 Riverpod 在 widget 树
  /// unmount 期间检测到非法的 provider 修改。
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;

    // 兜底：确保 _localVpcListener 被摘除。
    // 使用 _lastListenedVpc（而非 chewieNotifier.value），因为外部可能在
    // dispose 之前已将 notifier 置空，此时 chewieNotifier.value 取不到旧 VPC。
    // _lastListenedVpc 在 _onLocalControllerChanged 中缓存了实际挂载监听的 VPC。
    if (_lastListenedVpc != null && _localVpcListener != null) {
      _lastListenedVpc!.removeListener(_localVpcListener!);
    }
    _localVpcListener = null;
    _lastListenedVpc = null;

    chewieNotifier.removeListener(_onLocalControllerChanged);

    _castStateSub?.cancel();
    _castPosSub?.cancel();
    _castDurSub?.cancel();
    _castVolSub?.cancel();
    super.dispose();
  }
}
