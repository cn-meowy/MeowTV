import 'package:dart_cast/dart_cast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
