import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'media_capture_manager.dart';

final captureManagerProvider = ChangeNotifierProvider<MediaCaptureManager>((ref) {
  final manager = MediaCaptureManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});
