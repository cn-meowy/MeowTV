import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import '../../../core/logger/app_logger.dart';

/// 原生 AirPlay 视频 Layer 桥接。
///
/// 在 AirPlay 路由激活期间，原生侧将一个不影响前台的 `AVPlayerLayer`（使用
/// 视频_player 既有 `AVPlayer`，不参与命中测试）装入容器视图并插入 UIWindow
/// 子视图 index 0，被根视图（Flutter 画面）整体遮挡，保证 iOS AirPlay 视频
/// 交接路径的渲染侧条件成立。
///
/// 仅在 iOS / macOS 平台可用，其他平台为 no-op。
class AirPlayVideoLayerBridge {
  static const _channel = MethodChannel('com.meowtv.airplay_video_layer');
  static const _eventChannel = EventChannel('com.meowtv.airplay_video_layer/events');

  StreamSubscription? _eventSub;
  final _externalActiveController = StreamController<bool>.broadcast();

  bool _isLayerAttached = false;
  bool get isLayerAttached => _isLayerAttached;

  /// AVPlayerLayer.isExternalPlaybackActive 变化流（用于诊断）。
  Stream<bool> get externalActiveStream => _externalActiveController.stream;

  void start() {
    if (_eventSub != null) return;
    if (!Platform.isIOS && !Platform.isMacOS) return;
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (data) {
        final active = data as bool;
        appLogger.i('[AirPlayVideoLayer] externalPlaybackActive=$active');
        _externalActiveController.add(active);
      },
      onError: (e) {
        appLogger.w('[AirPlayVideoLayer] EventChannel 错误: $e');
      },
    );
  }

  void stop() {
    _eventSub?.cancel();
    _eventSub = null;
  }

  /// 挂载可见 AVPlayerLayer（Dart 侧不传 playerKey，由插件自动在视图层级中
  /// 查找既有 `video_player_avfoundation` 创建的不可见 AVPlayerLayer）。
  ///
  /// [aspectRatio] 用于按视频宽高比设置 layer frame（默认 16:9）。
  Future<bool> attachLayer({double aspectRatio = 16.0 / 9.0}) async {
    if (!Platform.isIOS && !Platform.isMacOS) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('attachLayer', {
        'aspectRatio': aspectRatio,
      }) ?? false;
      _isLayerAttached = ok;
      appLogger.i('[AirPlayVideoLayer] attachLayer 结果=$ok, aspectRatio=$aspectRatio');
      return ok;
    } catch (e) {
      appLogger.e('[AirPlayVideoLayer] attachLayer 调用失败', error: e);
      return false;
    }
  }

  /// 按 playerKey 挂载（Dart 侧 `VideoPlayerController.playerId`）。
  Future<bool> attachLayerWithPlayerKey({
    required int playerKey,
    double aspectRatio = 16.0 / 9.0,
  }) async {
    if (!Platform.isIOS && !Platform.isMacOS) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('attachLayerWithPlayerKey', {
        'playerKey': playerKey,
        'aspectRatio': aspectRatio,
      }) ?? false;
      _isLayerAttached = ok;
      appLogger.i('[AirPlayVideoLayer] attachLayerWithPlayerKey playerKey=$playerKey 结果=$ok');
      return ok;
    } catch (e) {
      appLogger.e('[AirPlayVideoLayer] attachLayerWithPlayerKey 调用失败', error: e);
      return false;
    }
  }

  /// 移除插件挂入的所有 layer。
  Future<void> detachAllLayers() async {
    if (!Platform.isIOS && !Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('detachAllLayers');
      _isLayerAttached = false;
      appLogger.i('[AirPlayVideoLayer] detachAllLayers 已调用');
    } catch (e) {
      appLogger.e('[AirPlayVideoLayer] detachAllLayers 调用失败', error: e);
    }
  }

  void dispose() {
    stop();
    _externalActiveController.close();
  }
}