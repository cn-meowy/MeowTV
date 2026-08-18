import 'dart:convert';
import 'package:dio/dio.dart';

/// 从异常对象中提取用户可读的错误消息。
/// 原始异常应由调用方通过 appLogger 单独记录。
String extractErrorMessage(Object error) {
  if (error is DioException) return _dioErrorMessage(error);
  // 非 Dio 异常(FormatException / TypeError / StateError 等)
  return '加载失败，请稍后重试';
}

String _dioErrorMessage(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return '连接超时，请检查网络后重试';
    case DioExceptionType.connectionError:
      return '无法连接服务器，请检查网络或服务器地址';
    case DioExceptionType.badResponse:
      final msg = _extractBackendMsg(e.response?.data);
      if (msg != null) return msg;
      return '加载失败 (${e.response?.statusCode ?? '未知'})';
    case DioExceptionType.cancel:
      return '请求已取消';
    default:
      return '网络请求失败，请稍后重试';
  }
}

/// 解析后端统一错误格式 {"code":4xx,"msg":"错误描述"} 的 msg 字段。
String? _extractBackendMsg(dynamic data) {
  try {
    if (data is Map<String, dynamic>) {
      final msg = data['msg'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    if (data is String && data.isNotEmpty) {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final msg = json['msg'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
  } catch (_) {}
  return null;
}
