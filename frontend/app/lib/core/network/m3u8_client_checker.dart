import 'dart:async';
import 'package:dio/dio.dart';

import '../../core/logger/app_logger.dart';
import '../../shared/models/m3u8_check_result.dart';

/// 客户端本地 m3u8 链接检测器
/// 通过 HTTP HEAD/GET 请求检测 URL 可用性
class M3u8ClientChecker {
  final Dio _dio;

  /// 检测超时时间（毫秒）
  static const _checkTimeoutMs = 10000;

  M3u8ClientChecker() : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(milliseconds: _checkTimeoutMs),
    receiveTimeout: const Duration(milliseconds: _checkTimeoutMs),
    sendTimeout: const Duration(milliseconds: _checkTimeoutMs),
  ));

  /// 检测单个 m3u8 URL 是否可用
  /// 使用 HEAD 请求，如果失败则尝试 GET（只获取状态码）
  Future<M3u8CheckResult> checkUrl(String url) async {
    appLogger.d('[M3u8ClientChecker] checking URL: $url');

    try {
      // 尝试 HEAD 请求
      final response = await _dio.head<String>(url);
      final statusCode = response.statusCode ?? 0;

      if (statusCode >= 200 && statusCode < 300) {
        appLogger.d('[M3u8ClientChecker] URL available: $url (status: $statusCode)');
        return M3u8CheckResult(
          url: url,
          available: true,
          statusCode: statusCode,
          error: '',
        );
      } else {
        appLogger.d('[M3u8ClientChecker] URL unavailable: $url (status: $statusCode)');
        return M3u8CheckResult(
          url: url,
          available: false,
          statusCode: statusCode,
          error: 'HTTP $statusCode',
        );
      }
    } on DioException catch (e) {
      appLogger.w('[M3u8ClientChecker] HEAD failed for $url: ${e.type}');
      // HEAD 失败，尝试 GET 请求
      final getResult = await _tryGetRequest(url);
      if (getResult != null) return getResult;

      // 所有方法都失败
      final errorMsg = _errorMessage(e);
      appLogger.w('[M3u8ClientChecker] URL check failed: $url ($errorMsg)');
      return M3u8CheckResult(
        url: url,
        available: false,
        statusCode: e.response?.statusCode ?? 0,
        error: errorMsg,
      );
    } catch (e) {
      appLogger.e('[M3u8ClientChecker] Unexpected error checking $url', error: e);
      return M3u8CheckResult(
        url: url,
        available: false,
        statusCode: 0,
        error: e.toString(),
      );
    }
  }

  /// 尝试 GET 请求（只获取状态码，不下载内容）
  Future<M3u8CheckResult?> _tryGetRequest(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          receiveDataWhenStatusError: false,
        ),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) {
        return M3u8CheckResult(
          url: url,
          available: true,
          statusCode: statusCode,
          error: '',
        );
      } else {
        return M3u8CheckResult(
          url: url,
          available: false,
          statusCode: statusCode,
          error: 'HTTP $statusCode',
        );
      }
    } catch (_) {
      return null;
    }
  }

  /// 批量检测 m3u8 URLs
  /// [urls] 要检测的 URL 列表
  /// [concurrency] 并发数，默认 5
  Future<List<M3u8CheckResult>> checkUrls(List<String> urls, {int concurrency = 5}) async {
    if (urls.isEmpty) return [];

    // 使用信号量控制并发
    final semaphore = _Semaphore(concurrency);
    final futures = urls.map((url) async {
      await semaphore.acquire();
      try {
        return await checkUrl(url);
      } finally {
        semaphore.release();
      }
    }).toList();

    return Future.wait(futures);
  }

  String _errorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时';
      case DioExceptionType.sendTimeout:
        return '发送超时';
      case DioExceptionType.receiveTimeout:
        return '接收超时';
      case DioExceptionType.connectionError:
        return '连接错误';
      case DioExceptionType.badResponse:
        return '响应错误：${e.response?.statusCode}';
      case DioExceptionType.cancel:
        return '请求取消';
      default:
        return e.message ?? '未知错误';
    }
  }
}

/// 简单信号量实现用于控制并发
class _Semaphore {
  final int maxCount;
  int _currentCount = 0;
  final List<Completer<void>> _waitQueue = [];

  _Semaphore(this.maxCount);

  Future<void> acquire() async {
    if (_currentCount < maxCount) {
      _currentCount++;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeAt(0);
      completer.complete();
    } else {
      _currentCount--;
    }
  }
}
