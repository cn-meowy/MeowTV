library;

/// M3u8 link check result model — mirrors backend response structure.

/// 单个 m3u8 链接检测结果
class M3u8CheckResult {
  final String url;
  final bool available;
  final int statusCode;
  final String error;

  const M3u8CheckResult({
    required this.url,
    required this.available,
    required this.statusCode,
    required this.error,
  });

  factory M3u8CheckResult.fromJson(Map<String, dynamic> j) => M3u8CheckResult(
        url: j['url'] as String? ?? '',
        available: j['available'] as bool? ?? false,
        statusCode: j['status_code'] as int? ?? 0,
        error: j['error'] as String? ?? '',
      );
}

/// 批量检测响应
class M3u8CheckResponse {
  final List<M3u8CheckResult> results;

  const M3u8CheckResponse({required this.results});

  factory M3u8CheckResponse.fromJson(Map<String, dynamic> j) {
    final resultsList = j['results'] as List<dynamic>? ?? [];
    return M3u8CheckResponse(
      results: resultsList
          .map((e) => M3u8CheckResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// URL 检测状态枚举
enum UrlCheckStatus {
  /// 未检测
  unchecked,
  /// 检测中
  checking,
  /// 可用
  available,
  /// 不可用
  unavailable,
}
