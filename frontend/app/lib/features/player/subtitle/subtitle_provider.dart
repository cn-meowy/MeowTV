import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'subtitle_manager.dart';
import 'subtitle_source.dart';

final subtitleManagerProvider = ChangeNotifierProvider<SubtitleManager>((ref) {
  final manager = SubtitleManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

final subtitleSourceRegistryProvider = Provider<SubtitleSourceRegistry>((ref) {
  return SubtitleSourceRegistry();
});
