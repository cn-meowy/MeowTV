import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'audio_track_manager.dart';

final audioTrackManagerProvider = ChangeNotifierProvider<AudioTrackManager>((ref) {
  final manager = AudioTrackManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});
