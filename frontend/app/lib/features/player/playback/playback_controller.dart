import 'dart:async';
import 'dart:io' show Platform;
import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../cast/airplay_route_service.dart';
import '../cast/airplay_video_layer_bridge.dart';
import '../cast/cast_service.dart';
import '../../../core/logger/app_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlaybackState — 统一播放状态模型
// ─────────────────────────────────────────────────────────────────────────────

/// 对 UI 暴露的统一播放状态，屏蔽本地/远端差异。
///
/// [isCasting] 为 true 时，[position]/[duration]/[isPlaying] 取自远端会话；
/// 否则取自本地 VideoPlayerController。
///
/// [isAirPlayActive] 为 true 时表示原生 AirPlay 路由已激活（[isCasting] 也为 true）。
/// 此时控制命令路由到本地 VideoPlayerController（AVPlayer），由系统自动转发到 AirPlay 接收端。
class PlaybackState {
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final double speed;
  final bool isCasting;
  final bool isAirPlayActive;
  final String? castDeviceName;
  final double volume; // 远端音量（0.0-1.0），投屏时从 CastSession 回读

  const PlaybackState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.isCasting = false,
    this.isAirPlayActive = false,
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
    bool? isAirPlayActive,
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
      isAirPlayActive: isAirPlayActive ?? this.isAirPlayActive,
      castDeviceName: castDeviceName ?? this.castDeviceName,
      volume: volume ?? this.volume,
    );
  }

  @override
  String toString() => 'PlaybackState(playing:$isPlaying, buffering:$isBuffering, '
      'pos:$position, dur:$duration, speed:$speed, casting:$isCasting, '
      'airplay:$isAirPlayActive, device:$castDeviceName, vol:$volume)';
}

/// 将本地 VideoPlayerController 的快照合并进当前 [PlaybackState]。
///
/// 关键不变量：
/// - AirPlay 激活期间（`current.isAirPlayActive == true`），**保留** `isCasting`
///   标志——本地 VPC 仍在播放（AVPlayer 转发到 AirPlay 接收端），castService 流
///   在 AirPlay 模式下为空，必须由本地 VPC 提供进度；强写 `isCasting: false`
///   会立即清掉 `_onAirPlayActiveChanged(true)` 设置的 overlay 状态。
/// - 非 AirPlay 路径下，按既有语义将 `isCasting` 重置为 false（castService 才是
///   远端真实来源）。
///
/// 抽出为顶层纯函数便于单元测试（`playback_state_merge_test.dart`）。
PlaybackState mergeLocalSnapshot({
  required PlaybackState current,
  required bool isPlaying,
  required bool isBuffering,
  required Duration position,
  required Duration duration,
  required double speed,
}) {
  final isCasting = current.isAirPlayActive ? current.isCasting : false;
  return current.copyWith(
    isPlaying: isPlaying,
    isBuffering: isBuffering,
    position: position,
    duration: duration,
    speed: speed,
    isCasting: isCasting,
    castDeviceName: null,
  );
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

  /// 原生 AirPlay 路由服务
  final AirPlayRouteService airPlayRouteService;

  /// 原生 AirPlay 视频 Layer 桥接（iOS 专用，挂载可见 AVPlayerLayer）。
  final AirPlayVideoLayerBridge airPlayVideoLayerBridge;

  PlaybackController({
    required this.chewieNotifier,
    required this.castService,
    required this.airPlayRouteService,
    required this.airPlayVideoLayerBridge,
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

    // 监听原生 AirPlay 路由状态
    _airPlayActiveSub = airPlayRouteService.activeStream.listen(_onAirPlayActiveChanged);
    _airPlayNameSub = airPlayRouteService.routeNameStream.listen(_onAirPlayRouteNameChanged);

    // 仅 iOS 监听 AVPlayerLayer.isExternalPlaybackActive：用于精确识别
    // "视频已确实交接给 AirPlay 接收端"与"已被踢回本机"，避免依赖 CoreAudio
    // 路由变化（音频-only 时路由不变）。macOS 无 video_layer 插件，订阅会得到
    // EventChannel 错误日志（pre-existing），不再做处理。
    if (Platform.isIOS) {
      _externalActiveSub = airPlayVideoLayerBridge.externalActiveStream.listen(_onExternalPlaybackActiveChanged);
    }
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
  StreamSubscription<bool>? _airPlayActiveSub;
  StreamSubscription<String?>? _airPlayNameSub;
  StreamSubscription<bool>? _externalActiveSub;
  VoidCallback? _localVpcListener;
  VideoPlayerController? _lastListenedVpc;

  /// 是否已确认收到过 AVPlayerLayer.isExternalPlaybackActive = true。
  /// 用于门控原生在 attach 时立即推送的初始 false（真实外部播放尚未开始），
  /// 避免激活瞬间被误清 overlay。
  bool _externalVideoConfirmed = false;

  /// 宽限定时器：3 秒内若仍未确认外部视频交接，视为音频-only AirPlay
  /// （如 HomePod），按 false 分支同款退出 overlay。
  Timer? _externalGraceTimer;

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
        // AirPlay 激活时本地 VPC 仍在播放（AVPlayer 转发到 AirPlay 接收端），
        // 需要继续同步本地进度到 UI（因为 AirPlay 模式下 castService 流为空）。
        if (!_state.isCasting || _state.isAirPlayActive) {
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
    _state = mergeLocalSnapshot(
      current: _state,
      isPlaying: vpc.value.isPlaying,
      isBuffering: vpc.value.isBuffering,
      position: vpc.value.position,
      duration: vpc.value.duration,
      speed: vpc.value.playbackSpeed,
    );
    notifyListeners();
  }

  // ─── 投屏状态变化回调 ─────────────────────────────────────────────────────

  void _onCastStateChanged(CastState castState) {
    // AirPlay 激活期间，castService 偶发 disconnected（DLNA 会话并发清理等）
    // 不能清投屏态——DLNA 自身的断开-恢复语义见
    // `cast_service_disconnect_race_test.dart`。仅当 AirPlay 未激活时，
    // castService 的 disconnected 才表示真正的投屏结束。
    if (_state.isAirPlayActive && castState == CastState.disconnected) {
      return;
    }

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
      // 显式覆盖 position/duration 为 0：投屏结束瞬间本地 VPC 仍在播放新内容，
      // _syncFromLocal 同步的是本地 VPC 的瞬时值，状态会短暂不一致。
      // 此处先归零，让 castConnectingOverlay / controls_overlay 立即收到
      // "投屏已结束"状态，避免 UI 短暂显示错误的远端进度。
      _state = _state.copyWith(
        position: Duration.zero,
        duration: Duration.zero,
        volume: 1.0,
      );
      notifyListeners();
      _syncFromLocal();
    }

    notifyListeners();
  }

  void _onCastPosition(Duration pos) {
    // AirPlay 激活时进度来自本地 VPC（castService 进度流为空）。
    if (_state.isCasting && !_state.isAirPlayActive) {
      _state = _state.copyWith(position: pos);
      notifyListeners();
    }
  }

  void _onCastDuration(Duration dur) {
    if (_state.isCasting && !_state.isAirPlayActive) {
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

  // ─── 原生 AirPlay 路由回调 ────────────────────────────────────────────────

  /// AirPlay 路由激活状态变化。
  ///
  /// 激活时设置 isCasting=true + isAirPlayActive=true（UI 显示 cast overlay）。
  /// 进度/时长仍来自本地 VPC（_syncFromLocal 通过监听器持续工作）。
  /// 断开时清除状态并从本地 VPC 恢复。
  ///
  /// 同步调用原生 AirPlayVideoLayerBridge：
  /// - 激活：原生侧将一个不影响前台的辅助 AVPlayerLayer（使用视频_player 既有
  ///   AVPlayer，不参与命中测试）装入容器视图并插入 UIWindow 子视图 index 0，
  ///   被根视图（Flutter 画面）整体遮挡，保证 AirPlay 视频交接路径的渲染侧
  ///   条件成立。
  /// - 断开：移除挂入的所有 layer。
  void _onAirPlayActiveChanged(bool active) {
    final cc = chewieNotifier.value;
    final vpc = cc?.videoPlayerController;
    final vpcValue = vpc?.value;
    final url = vpc?.dataSource;
    final shortUrl = (url == null || url.length < 200) ? url : url.substring(0, 200);

    if (active) {
      _state = _state.copyWith(
        isCasting: true,
        isAirPlayActive: true,
        castDeviceName: airPlayRouteService.routeName ?? 'AirPlay',
      );

      // 重置外部视频确认门控：等待 AVPlayerLayer.isExternalPlaybackActive 推送
      // true 后才算视频交接给 AirPlay 接收端，3 秒宽限内未确认视为音频-only。
      _externalVideoConfirmed = false;
      _externalGraceTimer?.cancel();
      _externalGraceTimer = Timer(const Duration(seconds: 3), () {
        if (!_state.isAirPlayActive || _externalVideoConfirmed) return;
        final cc = chewieNotifier.value;
        final stillPlaying = cc?.videoPlayerController.value.isPlaying ?? false;
        if (!stillPlaying) return;
        appLogger.i('[Player] AirPlay 宽限 3s 内未确认外部视频，按音频-only 处理退出 overlay');
        _exitAirPlayOverlayDueToExternalFalse();
      });

      // 诊断日志：与 player_screen.dart 既有日志格式保持一致。
      appLogger.i('[Player] AirPlay 激活 currentUrl=$shortUrl, vpc.isPlaying=${vpcValue?.isPlaying}, '
          'vpc.isBuffering=${vpcValue?.isBuffering}, route=${airPlayRouteService.routeName}');

      // 挂载可见 AVPlayerLayer（仅 iOS）。
      // macOS 上 Dart 端走 video_player + AppDelegate 路径，layer 桥接不需要。
      if (Platform.isIOS && vpc != null) {
        final size = vpcValue?.size;
        final aspectRatio = (size != null && size.height > 0)
            ? (size.width / size.height)
            : 16.0 / 9.0;
        final playerId = _safePlayerId(vpc);
        if (playerId != null) {
          airPlayVideoLayerBridge.attachLayerWithPlayerKey(
            playerKey: playerId,
            aspectRatio: aspectRatio,
          );
        } else {
          // playerId 不可用（极少见，如未走标准初始化）回退为按视图层级查找。
          airPlayVideoLayerBridge.attachLayer(aspectRatio: aspectRatio);
        }
      }
    } else {
      _state = _state.copyWith(
        isCasting: false,
        isAirPlayActive: false,
        castDeviceName: null,
      );
      _externalGraceTimer?.cancel();
      _externalGraceTimer = null;
      _externalVideoConfirmed = false;
      appLogger.i('[Player] AirPlay 断开');
      // 移除挂入的所有 AVPlayerLayer（仅 iOS）。
      if (Platform.isIOS) {
        airPlayVideoLayerBridge.detachAllLayers();
      }
      _syncFromLocal();
    }
    notifyListeners();
  }

  /// 读取 `VideoPlayerController.playerId`（标记为 `@visibleForTesting` 但
  /// 在 iOS 端与 `video_player_avfoundation` 的 `playerId` 字段稳定对应）。
  /// 失败时返回 null，回退为按视图层级查找既有 AVPlayerLayer。
  int? _safePlayerId(VideoPlayerController vpc) {
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      return vpc.playerId;
    } catch (_) {
      return null;
    }
  }

  void _onAirPlayRouteNameChanged(String? name) {
    if (_state.isAirPlayActive) {
      _state = _state.copyWith(castDeviceName: name ?? 'AirPlay');
      notifyListeners();
    }
  }

  // ─── AVPlayerLayer.isExternalPlaybackActive 回调（仅 iOS） ─────────────────

  /// 处理 AVPlayer.isExternalPlaybackActive 变化。
  ///
  /// 关键门控：原生侧 `createAndAttachLayer` 会在挂载瞬间立即推送一次当前
  /// `isExternalPlaybackActive`（通常为 false，因为此时视频尚未交接）。若不
  /// 门控，激活瞬间 overlay 会被立刻清掉。因此必须先收到一次 true 后，再让
  /// false 触发清理。
  void _onExternalPlaybackActiveChanged(bool active) {
    if (active) {
      _externalVideoConfirmed = true;
      _externalGraceTimer?.cancel();
      _externalGraceTimer = null;
      // 若曾因宽限期退出 overlay 但 AirPlay 路由仍激活（音频-only 误判后视频
      // 又跟上），恢复 overlay。
      if (_state.isAirPlayActive && !_state.isCasting) {
        appLogger.i('[Player] AirPlay 视频已确认交接，恢复 overlay');
        _state = _state.copyWith(
          isCasting: true,
          isAirPlayActive: true,
          castDeviceName: airPlayRouteService.routeName ?? 'AirPlay',
        );
        notifyListeners();
      }
    } else if (_externalVideoConfirmed) {
      // 真正的"视频已不再在 AirPlay 上"：覆盖"一键断开踢掉外部播放"和
      // "TV 端主动结束"两种场景。
      _externalVideoConfirmed = false;
      appLogger.i('[Player] AirPlay 视频已退出（KVO false, 已确认）');
      _exitAirPlayOverlayDueToExternalFalse();
    }
  }

  /// 退出 overlay 但保留 KVO/路由监听，等待 CoreAudio 路由真正变化时再做完整清理。
  ///
  /// 注：不调 `detachAllLayers`——保留挂入的 AVPlayerLayer 让 KVO 持续工作，
  /// 若用户再次进入 AirPlay 路由可立即恢复。`detachAllLayers` 由
  /// `_onAirPlayActiveChanged(false)`（CoreAudio 路由真正变化时）触发。
  void _exitAirPlayOverlayDueToExternalFalse() {
    if (!_state.isAirPlayActive && !_state.isCasting) return;
    _externalGraceTimer?.cancel();
    _externalGraceTimer = null;
    _state = _state.copyWith(
      isCasting: false,
      isAirPlayActive: false,
      castDeviceName: null,
    );
    notifyListeners();
    _syncFromLocal();
  }

  // ─── 统一命令接口 ─────────────────────────────────────────────────────────

  /// 播放（投屏中路由到远端，否则本地）
  ///
  /// AirPlay 激活时走本地 VPC（castService.isCasting=false，但 _state.isCasting=true），
  /// AVPlayer 会自动将控制命令转发到 AirPlay 接收端。
  Future<void> play() async {
    if (castService.isCasting && !_state.isAirPlayActive) {
      await castService.play();
    } else {
      chewieNotifier.value?.play();
    }
  }

  /// 暂停
  Future<void> pause() async {
    if (castService.isCasting && !_state.isAirPlayActive) {
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
    if (castService.isCasting && !_state.isAirPlayActive) {
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
    _airPlayActiveSub?.cancel();
    _airPlayNameSub?.cancel();
    _externalActiveSub?.cancel();
    _externalGraceTimer?.cancel();
    _externalGraceTimer = null;
    super.dispose();
  }
}
