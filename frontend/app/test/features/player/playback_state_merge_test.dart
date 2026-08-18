import 'package:flutter_test/flutter_test.dart';
import 'package:meowtv_mobile/features/player/playback/playback_controller.dart';

void main() {
  group('mergeLocalSnapshot (T1)', () {
    test('AirPlay 激活时合并本地进度，isCasting/isAirPlayActive 保持 true', () {
      const current = PlaybackState(
        isCasting: true,
        isAirPlayActive: true,
        castDeviceName: 'Apple TV',
        position: Duration(seconds: 10),
        duration: Duration(minutes: 5),
      );

      final merged = mergeLocalSnapshot(
        current: current,
        isPlaying: true,
        isBuffering: false,
        position: const Duration(seconds: 42),
        duration: const Duration(minutes: 5),
        speed: 1.0,
      );

      expect(merged.isCasting, isTrue,
          reason: 'AirPlay 激活期间必须保留 isCasting，否则 overlay 被刷掉');
      expect(merged.isAirPlayActive, isTrue);
      // 进度/播放/倍速从本地 VPC 同步
      expect(merged.isPlaying, isTrue);
      expect(merged.position, const Duration(seconds: 42));
      expect(merged.speed, 1.0);
    });

    test('非 AirPlay 时 isCasting 被重置为 false（DLNA/本地路径语义不变）', () {
      const current = PlaybackState(
        isCasting: true,
        isAirPlayActive: false,
        castDeviceName: '客厅 TV',
      );

      final merged = mergeLocalSnapshot(
        current: current,
        isPlaying: true,
        isBuffering: false,
        position: Duration.zero,
        duration: Duration.zero,
        speed: 1.0,
      );

      expect(merged.isCasting, isFalse);
      expect(merged.isAirPlayActive, isFalse);
    });

    test('初始状态（非 AirPlay、非投屏）合并后保持全 false', () {
      const current = PlaybackState();

      final merged = mergeLocalSnapshot(
        current: current,
        isPlaying: true,
        isBuffering: false,
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 2),
        speed: 1.25,
      );

      expect(merged.isCasting, isFalse);
      expect(merged.isAirPlayActive, isFalse);
      expect(merged.isPlaying, isTrue);
      expect(merged.position, const Duration(seconds: 5));
      expect(merged.speed, 1.25);
    });
  });
}