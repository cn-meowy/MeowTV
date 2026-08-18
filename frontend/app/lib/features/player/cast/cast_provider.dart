import 'package:dart_cast/dart_cast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'airplay_route_service.dart';
import 'airplay_video_layer_bridge.dart';
import 'cast_service.dart';

/// 投屏服务 Provider
final castServiceProvider = Provider<MeowCastService>((ref) {
  final service = MeowCastService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// 投屏状态 Provider
final castStateProvider = StreamProvider<CastState>((ref) {
  final service = ref.watch(castServiceProvider);
  return service.stateStream;
});

/// 投屏设备列表 Provider
final castDevicesProvider = StreamProvider<List<CastDevice>>((ref) {
  final service = ref.watch(castServiceProvider);
  return service.devicesStream;
});

/// AirPlay 路由服务 Provider（单例）
final airPlayRouteServiceProvider = Provider<AirPlayRouteService>((ref) {
  final service = AirPlayRouteService();
  service.start();
  ref.onDispose(() {
    service.stop();
  });
  return service;
});

/// AirPlay 视频 Layer 桥接 Provider（单例）。
/// 监听 KVO `isExternalPlaybackActive` 变化，用于诊断。
final airPlayVideoLayerBridgeProvider = Provider<AirPlayVideoLayerBridge>((ref) {
  final bridge = AirPlayVideoLayerBridge();
  bridge.start();
  ref.onDispose(() {
    bridge.detachAllLayers();
    bridge.stop();
  });
  return bridge;
});

/// AirPlay 路由激活状态 Provider
final airPlayActiveProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(airPlayRouteServiceProvider);
  return service.activeStream;
});
