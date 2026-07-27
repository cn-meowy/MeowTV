import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    try {
      final response = await _apiClient.postStream(
        ApiConstants.resourceSearch,
        data: body,
        cancelToken: cancelToken,
      );

      final stream = response.data?.stream;
      if (stream == null) {
        callbacks.onError?.call(SearchErrorData(resourceDomain: '', message: '无法读取响应流'));
        return;
      }

      String buffer = '';
      String currentEventType = '';

      await for (final chunk in stream) {
        if (cancelToken?.isCancelled ?? false) break;

        buffer += utf8.decode(chunk, allowMalformed: true);

        // Normalize line endings: HTTP responses may use \r\n (CRLF).
        // Dart's utf8.decode does NOT strip \r, so split('\n') leaves
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
            } catch (_) {
              // JSON parse error — ignore
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
    } catch (e) {
      if (cancelToken?.isCancelled ?? false) return;
      callbacks.onError?.call(SearchErrorData(resourceDomain: '', message: e.toString()));
    }
  }
}

// ---------- Riverpod provider ----------

final sseClientProvider = Provider<SseClient>((ref) {
  final apiClient = ref.read(apiClientProvider);
  return SseClient(apiClient);
});
