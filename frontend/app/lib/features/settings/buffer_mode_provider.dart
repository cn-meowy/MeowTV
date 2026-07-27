import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/secure_storage.dart';
import '../../shared/models/enums.dart';

/// 自动缓存大小限制
enum AutoCacheSizeLimit {
  size500MB, // 500MB
  size1GB, // 1GB
  size2GB, // 2GB
  size5GB, // 5GB
}

/// AutoCacheSizeLimit 枚举扩展
extension AutoCacheSizeLimitExtension on AutoCacheSizeLimit {
  static AutoCacheSizeLimit fromString(String? value) {
    switch (value) {
      case '500mb':
        return AutoCacheSizeLimit.size500MB;
      case '1gb':
        return AutoCacheSizeLimit.size1GB;
      case '2gb':
        return AutoCacheSizeLimit.size2GB;
      case '5gb':
        return AutoCacheSizeLimit.size5GB;
      default:
        return AutoCacheSizeLimit.size1GB; // 默认 1GB
    }
  }

  String toStorageString() {
    switch (this) {
      case AutoCacheSizeLimit.size500MB:
        return '500mb';
      case AutoCacheSizeLimit.size1GB:
        return '1gb';
      case AutoCacheSizeLimit.size2GB:
        return '2gb';
      case AutoCacheSizeLimit.size5GB:
        return '5gb';
    }
  }

  int get bytes {
    switch (this) {
      case AutoCacheSizeLimit.size500MB:
        return 500 * 1024 * 1024;
      case AutoCacheSizeLimit.size1GB:
        return 1024 * 1024 * 1024;
      case AutoCacheSizeLimit.size2GB:
        return 2 * 1024 * 1024 * 1024;
      case AutoCacheSizeLimit.size5GB:
        return 5 * 1024 * 1024 * 1024;
    }
  }

  String get label {
    switch (this) {
      case AutoCacheSizeLimit.size500MB:
        return '500MB';
      case AutoCacheSizeLimit.size1GB:
        return '1GB';
      case AutoCacheSizeLimit.size2GB:
        return '2GB';
      case AutoCacheSizeLimit.size5GB:
        return '5GB';
    }
  }
}

/// 缓冲模式状态
class BufferModeState {
  final BufferMode mode;
  final BufferQuality quality;
  final AutoCacheSizeLimit autoCacheSizeLimit; // 新增

  const BufferModeState({
    this.mode = BufferMode.strategyB,
    this.quality = BufferQuality.auto,
    this.autoCacheSizeLimit = AutoCacheSizeLimit.size1GB, // 默认 1GB
  });

  BufferModeState copyWith({
    BufferMode? mode,
    BufferQuality? quality,
    AutoCacheSizeLimit? autoCacheSizeLimit, // 新增
  }) =>
      BufferModeState(
        mode: mode ?? this.mode,
        quality: quality ?? this.quality,
        autoCacheSizeLimit: autoCacheSizeLimit ?? this.autoCacheSizeLimit, // 新增
      );
}

/// 缓冲模式配置 Notifier
class BufferModeNotifier extends StateNotifier<BufferModeState> {
  final SecureStorageService _storage;

  BufferModeNotifier(this._storage) : super(const BufferModeState()) {
    _load();
  }

  Future<void> _load() async {
    final modeStr = await _storage.getBufferMode();
    final qualityStr = await _storage.getBufferQuality();
    final sizeLimitStr = await _storage.getAutoCacheSizeLimit(); // 新增
    state = BufferModeState(
      mode: BufferMode.fromString(modeStr),
      quality: BufferQuality.fromString(qualityStr),
      autoCacheSizeLimit: AutoCacheSizeLimitExtension.fromString(sizeLimitStr), // 新增
    );
  }

  Future<void> setMode(BufferMode mode) async {
    await _storage.setBufferMode(mode.toStorageString());
    state = state.copyWith(mode: mode);
  }

  Future<void> setQuality(BufferQuality quality) async {
    await _storage.setBufferQuality(quality.toStorageString());
    state = state.copyWith(quality: quality);
  }

  // 新增 setAutoCacheSizeLimit 方法
  Future<void> setAutoCacheSizeLimit(AutoCacheSizeLimit limit) async {
    await _storage.setAutoCacheSizeLimit(limit.toStorageString());
    state = state.copyWith(autoCacheSizeLimit: limit);
  }
}

final bufferModeProvider =
    StateNotifierProvider<BufferModeNotifier, BufferModeState>((ref) {
  return BufferModeNotifier(SecureStorageService.instance);
});
