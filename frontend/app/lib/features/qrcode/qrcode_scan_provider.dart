import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/logger/app_logger.dart';

/// 扫码状态
enum QRCodeScanStatus {
  idle,
  scanning,
  confirming,
  success,
  error,
}

/// 扫码状态数据
class QRCodeScanState {
  final QRCodeScanStatus status;
  final String? code;
  final String? error;

  const QRCodeScanState({
    this.status = QRCodeScanStatus.idle,
    this.code,
    this.error,
  });

  QRCodeScanState copyWith({
    QRCodeScanStatus? status,
    String? code,
    String? error,
  }) =>
      QRCodeScanState(
        status: status ?? this.status,
        code: code ?? this.code,
        error: error,
      );
}

/// 扫码确认 Notifier
class QRCodeScanNotifier extends StateNotifier<QRCodeScanState> {
  final ApiClient _api;

  QRCodeScanNotifier(this._api) : super(const QRCodeScanState());

  /// 扫到二维码后调用，提取 code 并确认
  Future<void> confirmScan(String scannedCode) async {
    // 从扫码内容中提取6位验证码
    final code = _extractCode(scannedCode);
    if (code == null) {
      state = const QRCodeScanState(
        status: QRCodeScanStatus.error,
        error: '无效的二维码内容',
      );
      return;
    }

    state = QRCodeScanState(
      status: QRCodeScanStatus.confirming,
      code: code,
    );

    try {
      await _api.post(
        ApiConstants.qrcodeScan,
        data: {'code': code},
      );
      if (!mounted) return;
      state = QRCodeScanState(
        status: QRCodeScanStatus.success,
        code: code,
      );
      appLogger.i('扫码确认成功, code=$code');
    } catch (e) {
      appLogger.e('扫码确认失败', error: e);
      if (!mounted) return;
      state = QRCodeScanState(
        status: QRCodeScanStatus.error,
        code: code,
        error: '确认失败: $e',
      );
    }
  }

  /// 重置状态，允许重新扫码
  void reset() {
    state = const QRCodeScanState(status: QRCodeScanStatus.scanning);
  }

  /// 从二维码内容中提取登录码
  ///
  /// 后端 generateRandomCode 生成 8 位字母数字混合码（大写字母+数字，
  /// 字符集 ABCDEFGHJKMNPQRSTUVWXYZ23456789，排除易混淆的 0/O/1/I/L）。
  /// 二维码内容可能为纯登录码，也可能是 URL 格式如：
  /// - https://xxx?code=K3MNP9XR
  /// - meowtv://qr-login?code=K3MNP9XR （后端生成的自定义 scheme）
  /// 严格匹配：完整 8 位登录码
  static final _codeRegex = RegExp(r'^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$');

  /// 子串匹配：从任意内容中提取 8 位登录码（兜底用）
  static final _codeSearchRegex = RegExp(r'[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}');

  String? _extractCode(String content) {
    final trimmed = content.trim();

    // 1. 纯 8 位登录码
    if (_codeRegex.hasMatch(trimmed)) {
      return trimmed;
    }

    // 2. meowtv:// 自定义 scheme — 手动解析 query 参数
    //    避免 Uri.tryParse 对非标准 scheme 解析不可靠的问题
    if (trimmed.startsWith('meowtv://')) {
      final queryStart = trimmed.indexOf('?');
      if (queryStart != -1) {
        final queryString = trimmed.substring(queryStart + 1);
        // Uri.splitQueryString 可以正确解析类似 "code=K3MNP9XR&q=xxx" 的字符串
        final params = Uri.splitQueryString(queryString);
        final code = params['code'] ?? params['q'];
        if (code != null && _codeRegex.hasMatch(code)) {
          return code;
        }
      }
    }

    // 3. 标准 HTTP/HTTPS URL 格式
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final codeParam = uri.queryParameters['code'] ?? uri.queryParameters['q'];
      if (codeParam != null && _codeRegex.hasMatch(codeParam)) {
        return codeParam;
      }
    }

    // 4. 兜底：从内容中子串匹配 8 位登录码
    final match = _codeSearchRegex.firstMatch(trimmed);
    if (match != null) {
      return match.group(0);
    }

    return null;
  }
}

final qrcodeScanProvider =
    StateNotifierProvider<QRCodeScanNotifier, QRCodeScanState>((ref) {
  final apiClient = ref.read(apiClientProvider);
  return QRCodeScanNotifier(apiClient);
});
