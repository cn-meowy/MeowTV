import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger/app_logger.dart';
import 'api_client.dart';
import 'api_constants.dart';
import '../../shared/models/search_result.dart';

/// SSE search callbacks — mirrors Web frontend SearchCallbacks.
typedef OnSearchResult = void Function(SearchResultItem item);
typedef OnSearchDone = void Function(SearchDoneData data);
typedef OnSearchComplete = void Function(SearchCompleteData data);
typedef OnSearchError = void Function(SearchErrorData data);

class SearchCallbacks {
  final OnSearchResult? onResult;
  final OnSearchDone? onDone;
  final OnSearchComplete? onComplete;
  final OnSearchError? onError;
  const SearchCallbacks({this.onResult, this.onDone, this.onComplete, this.onError});
}

/// SSE client for streaming search results using Dio with ResponseType.stream.
class SseClient {
  SseClient(this._apiClient);
  final ApiClient _apiClient;

  /// Emit a search-level error to the caller. Server errors use
  /// `resourceDomain: ''` so the UI can distinguish them from per-site errors.
  void _emitError(SearchCallbacks callbacks, String message) {
    appLogger.w('[SseClient] search error: $message');
    callbacks.onError?.call(SearchErrorData(resourceDomain: '', message: message));
  }

  /// Best-effort extract of the server `msg` field from a non-stream error
  /// response body. The server uses the unified `{code, msg, data}` format.
  Future<String> _extractServerMessage(ResponseBody body) async {
    try {
      final raw = await body.stream.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      if (raw.isEmpty) return '搜索请求失败';
      final decoded = jsonDecode(utf8.decode(raw, allowMalformed: true));
      if (decoded is Map<String, dynamic>) {
        final msg = decoded['msg'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
      return '搜索请求失败';
    } catch (_) {
      return '搜索请求失败';
    }
  }

  /// Execute SSE search. Cancel by cancelling [cancelToken].
  Future<void> searchSSE({
    required String query,
    List<String>? resources,
    String? doubanId,
    required SearchCallbacks callbacks,
    CancelToken? cancelToken,
  }) async {
    final body = <String, dynamic>{
      'q': query,
      'douban_id': ?doubanId,
      if (resources != null && resources.isNotEmpty) 'resources': resources,
    };

    final startedAt = DateTime.now();
    try {
      final response = await _apiClient.postStream(
        ApiConstants.resourceSearch,
        data: body,
        cancelToken: cancelToken,
      );

      final status = response.statusCode ?? 0;
      final contentType = response.headers.value('content-type') ?? '';
      appLogger.d(
        '[SseClient] response received: status=$status, '
        'content-type=$contentType, '
        'elapsed=${DateTime.now().difference(startedAt).inMilliseconds}ms',
      );

      if (status < 200 || status >= 300) {
        final msg = await _extractServerMessage(response.data!);
        _emitError(callbacks, '搜索失败 ($status): $msg');
        return;
      }

      final stream = response.data?.stream;
      if (stream == null) {
        _emitError(callbacks, '无法读取响应流');
        return;
      }

      // Use an incremental UTF-8 decoder so multi-byte characters (e.g.
      // Chinese titles) split across chunks decode correctly. Per-chunk
      // utf8.decode with allowMalformed silently corrupted such splits.
      final textStream = stream
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true));

      String buffer = '';
      String currentEventType = '';
      int eventCount = 0;
      DateTime? firstEventAt;

      await for (final chunk in textStream) {
        if (cancelToken?.isCancelled ?? false) break;

        buffer += chunk;

        // Normalize line endings: HTTP responses may use \r\n (CRLF).
        // Dart's utf8 decoder does NOT strip \r, so split('\n') leaves
        // trailing \r on lines, which breaks isEmpty checks, JSON parsing,
        // and event-type matching.  Strip all \r first.
        buffer = buffer.replaceAll('\r', '');

        // Parse SSE events
        final lines = buffer.split('\n');
        // The last element after split may be an incomplete line (no trailing \n).
        // Keep it in the buffer for the next chunk.
        buffer = lines.removeLast();

        for (final line in lines) {
          if (line.startsWith('event: ')) {
            currentEventType = line.substring(7).trim();
          } else if (line.startsWith('data: ')) {
            final dataStr = line.substring(6);
            try {
              final data = jsonDecode(dataStr);
              eventCount++;
              firstEventAt ??= DateTime.now();
              switch (currentEventType) {
                case 'result':
                  callbacks.onResult?.call(SearchResultItem.fromJson(data as Map<String, dynamic>));
                  break;
                case 'done':
                  callbacks.onDone?.call(SearchDoneData.fromJson(data as Map<String, dynamic>));
                  break;
                case 'complete':
                  callbacks.onComplete?.call(SearchCompleteData.fromJson(data as Map<String, dynamic>));
                  break;
                case 'error':
                  callbacks.onError?.call(SearchErrorData.fromJson(data as Map<String, dynamic>));
                  break;
              }
            } catch (e) {
              appLogger.d('[SseClient] skip malformed event line: $dataStr');
            }
            // Do NOT reset currentEventType here — a data line may be split
            // across chunks; the event type must remain available for the
            // continuation.  Reset only on the empty-line event boundary.
          } else if (line.isEmpty) {
            // Empty line signals event end — reset event type
            currentEventType = '';
          }
          // Non-empty, non-event/data lines (e.g. comments starting with ':')
          // are simply ignored per SSE spec.
        }
      }

      final firstDelay = firstEventAt == null
          ? -1
          : firstEventAt.difference(startedAt).inMilliseconds;
      appLogger.d(
        '[SseClient] stream completed: events=$eventCount, '
        'firstEventMs=$firstDelay, '
        'totalMs=${DateTime.now().difference(startedAt).inMilliseconds}',
      );
    } on DioException catch (e) {
      if (cancelToken?.isCancelled ?? false) return;
      // For non-2xx stream responses, Dio throws badResponse with the
      // server body still in e.response?.data. Prefer the server msg.
      final resp = e.response;
      if (resp?.data is ResponseBody) {
        final msg = await _extractServerMessage(resp!.data as ResponseBody);
        _emitError(
          callbacks,
          '搜索失败 (${resp.statusCode ?? 0}): $msg',
        );
        return;
      }
      _emitError(callbacks, '搜索请求失败: ${e.message ?? e.toString()}');
    } catch (e) {
      if (cancelToken?.isCancelled ?? false) return;
      _emitError(callbacks, e.toString());
    }
  }
}

// ---------- Riverpod provider ----------

final sseClientProvider = Provider<SseClient>((ref) {
  final apiClient = ref.read(apiClientProvider);
  return SseClient(apiClient);
});
