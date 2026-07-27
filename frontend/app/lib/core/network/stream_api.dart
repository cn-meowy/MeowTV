import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'api_constants.dart';
import '../../shared/models/m3u8_check_result.dart';

/// Stream API — m3u8 proxy and check operations.
class StreamApi {
  final ApiClient _client;

  StreamApi(this._client);

  /// 批量检测 m3u8 链接可用性
  /// 使用 POST 请求，后端通过 HEAD 并发检测
  ///
  /// [urls] 要检测的 m3u8 URL 列表（最多 50 个）
  /// 返回检测结果列表
  Future<List<M3u8CheckResult>> checkM3u8Urls(List<String> urls) async {
    if (urls.isEmpty) return [];

    try {
      final resp = await _client.post<Map<String, dynamic>>(
        ApiConstants.streamCheck,
        data: {'urls': urls},
      );

      final data = resp.data;
      if (data == null) {
        return [];
      }

      // 兼容标准响应格式 { code: 200, data: { results: [...] } }
      // 或直接格式 { results: [...] }
      Map<String, dynamic>? resultsData;
      if (data['code'] == 200 || data['code'] == 0) {
        resultsData = data['data'] as Map<String, dynamic>?;
      } else {
        resultsData = data;
      }

      if (resultsData == null) return [];

      final response = M3u8CheckResponse.fromJson(resultsData);
      return response.results;
    } on DioException catch (e) {
      // 网络错误时返回空列表，调用方应处理
      throw Exception('m3u8 check failed: ${e.message}');
    }
  }
}

// ---------- Riverpod provider ----------

final streamApiProvider = Provider<StreamApi>((ref) {
  return StreamApi(ref.read(apiClientProvider));
});
