import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pip_service.dart';

/// PiP 可用性 Provider（异步，启动时检查一次）
final pipAvailableProvider = FutureProvider<bool>((ref) async {
  return PipService.instance.isAvailable;
});

/// PiP 激活状态 Provider
final pipActiveProvider = StateProvider<bool>((ref) => false);
