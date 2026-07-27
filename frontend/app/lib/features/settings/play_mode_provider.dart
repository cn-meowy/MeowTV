import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/secure_storage.dart';
import '../../shared/models/enums.dart';

/// 播放模式 Notifier
class PlayModeNotifier extends StateNotifier<PlayMode> {
  final SecureStorageService _storage;

  PlayModeNotifier(this._storage) : super(PlayMode.autoNext) {
    _load();
  }

  Future<void> _load() async {
    final modeStr = await _storage.getPlayMode();
    state = PlayMode.fromString(modeStr);
  }

  Future<void> setPlayMode(PlayMode mode) async {
    await _storage.setPlayMode(mode.toStorageString());
    state = mode;
  }
}

/// 连播模式 Provider
final playModeProvider =
    StateNotifierProvider<PlayModeNotifier, PlayMode>((ref) {
  return PlayModeNotifier(SecureStorageService.instance);
});
