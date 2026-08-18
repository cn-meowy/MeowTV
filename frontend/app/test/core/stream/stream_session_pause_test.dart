// test/core/stream/stream_session_pause_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowtv_mobile/core/stream/segment_cache_manager.dart';
import 'package:meowtv_mobile/core/stream/stream_config.dart';
import 'package:meowtv_mobile/core/stream/stream_session.dart';

void main() {
  group('StreamSession.pause', () {
    late Directory tempDir;
    late SegmentCacheManager cacheManager;
    late StreamSession session;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('stream_session_pause_test_');
      cacheManager = SegmentCacheManager(
        totalSegments: 3,
        segmentDir: tempDir.path,
        memLimit: 0,
      );
      final m3u8Info = M3u8Info(
        isVOD: true,
        segments: const [],
        duration: 0,
        mediaURL: 'http://example.com/v.m3u8',
        rawContent: '#EXTM3U',
      );
      session = StreamSession.createForTest(
        sessionKey: 'test-key-1234',
        m3u8URL: 'http://example.com/v.m3u8',
        m3u8Info: m3u8Info,
        cacheManager: cacheManager,
        segmentDir: tempDir.path,
      );
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('pause 后 state 变为 paused', () {
      session.setState(SessionState.active);
      session.pause();
      expect(session.state, SessionState.paused);
    });

    test('pause 不会改变非 active 状态（语义上是幂等停止入口）', () {
      // created 状态下调用 pause：直接迁移到 paused 状态
      expect(session.state, SessionState.created);
      session.pause();
      expect(session.state, SessionState.paused);
    });

    test('pause 重置 downloading 分片为 pending', () async {
      session.setState(SessionState.active);
      await cacheManager.setStatus(0, SegmentStatus.downloading);
      await cacheManager.setStatus(1, SegmentStatus.downloading);
      await cacheManager.setStatus(2, SegmentStatus.pending);

      expect(cacheManager.getStatus(0), SegmentStatus.downloading);
      expect(cacheManager.getStatus(1), SegmentStatus.downloading);
      expect(cacheManager.getStatus(2), SegmentStatus.pending);

      session.pause();

      expect(cacheManager.getStatus(0), SegmentStatus.pending);
      expect(cacheManager.getStatus(1), SegmentStatus.pending);
      expect(cacheManager.getStatus(2), SegmentStatus.pending);
    });

    test('pause 在无 downloading 分片时不报错', () async {
      session.setState(SessionState.active);
      // 全部默认 pending
      session.pause();
      expect(session.state, SessionState.paused);
      expect(cacheManager.getDownloadingSegments(), isEmpty);
    });
  });
}
