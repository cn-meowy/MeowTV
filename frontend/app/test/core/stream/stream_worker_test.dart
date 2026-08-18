// test/core/stream/stream_worker_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowtv_mobile/core/stream/stream_worker.dart';

void main() {
  group('StreamWorker.isRetryableErrorForTest', () {
    test('HandshakeException（dart:io 类型）可重试', () {
      final e = HandshakeException('Connection terminated during handshake');
      expect(StreamWorker.isRetryableErrorForTest(e), isTrue);
    });

    test('包含 HandshakeException 字符串的普通 Exception 可重试（兜底）', () {
      // _doDownloadSegment 会把底层异常包装成 Exception('download segment failed: $e')
      final e = Exception(
          'download segment failed: HandshakeException: Connection terminated during handshake');
      expect(StreamWorker.isRetryableErrorForTest(e), isTrue);
    });

    test('包含 TLS / SSL 字符串的异常可重试', () {
      expect(StreamWorker.isRetryableErrorForTest(Exception('TLS handshake failed')), isTrue);
      expect(StreamWorker.isRetryableErrorForTest(Exception('SSL error')), isTrue);
    });

    test('TimeoutException / SocketException / HttpException 可重试', () {
      expect(StreamWorker.isRetryableErrorForTest(TimeoutException('timed out')), isTrue);
      expect(
        StreamWorker.isRetryableErrorForTest(
          SocketException('Connection refused'),
        ),
        isTrue,
      );
      expect(
        StreamWorker.isRetryableErrorForTest(HttpException('HTTP 500')),
        isTrue,
      );
    });

    test('既有的可重试字符串仍被覆盖', () {
      expect(StreamWorker.isRetryableErrorForTest(Exception('Connection reset by peer')), isTrue);
      expect(StreamWorker.isRetryableErrorForTest(Exception('broken pipe')), isTrue);
      expect(StreamWorker.isRetryableErrorForTest(Exception('HTTP 503 Service Unavailable')), isTrue);
      expect(StreamWorker.isRetryableErrorForTest(Exception('HTTP 429 Too Many Requests')), isTrue);
    });

    test('不可重试的错误返回 false', () {
      expect(StreamWorker.isRetryableErrorForTest(Exception('HTTP 404 Not Found')), isFalse);
      expect(StreamWorker.isRetryableErrorForTest(Exception('some random error')), isFalse);
      expect(StreamWorker.isRetryableErrorForTest(ArgumentError('bad arg')), isFalse);
    });
  });
}
