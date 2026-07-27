import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'quality_manager.dart';

/// QualityManager provider
final qualityManagerProvider = ChangeNotifierProvider<QualityManager>((ref) {
  final manager = QualityManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// 连接状态 provider
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});
