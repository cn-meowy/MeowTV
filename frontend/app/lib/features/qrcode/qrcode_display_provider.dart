import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/logger/app_logger.dart';
import '../../core/utils/platform_util.dart';
import '../auth/auth_provider.dart';

/// TV 端二维码显示状态
enum QRCodeDisplayStatus {
  idle,
  loading, // 正在请求登录码
  displaying, // 正在显示二维码，等待扫码
  confirmed, // 扫码确认成功
  expired, // 二维码已过期
  error, // 发生错误
}

/// TV 端二维码显示状态数据
class QRCodeDisplayState {
  final QRCodeDisplayStatus status;
  final String? code;
  final String? qrUrl;
  final int? expiresIn;
  final String? error;

  const QRCodeDisplayState({
    this.status = QRCodeDisplayStatus.idle,
    this.code,
    this.qrUrl,
    this.expiresIn,
    this.error,
  });

  QRCodeDisplayState copyWith({
    QRCodeDisplayStatus? status,
    String? code,
    String? qrUrl,
    int? expiresIn,
    String? error,
  }) =>
      QRCodeDisplayState(
        status: status ?? this.status,
        code: code ?? this.code,
        qrUrl: qrUrl ?? this.qrUrl,
        expiresIn: expiresIn ?? this.expiresIn,
        error: error,
      );
}

/// TV 端二维码显示 Notifier
/// 负责请求登录码、显示二维码、轮询确认结果
class QRCodeDisplayNotifier extends StateNotifier<QRCodeDisplayState> {
  final ApiClient _api;
  final AuthNotifier _authNotifier;
  Timer? _pollTimer;
  int _pollCount = 0;
  static const _maxPollCount = 60; // 最多轮询 60 次（约 5 分钟）

  QRCodeDisplayNotifier(this._api, this._authNotifier)
      : super(const QRCodeDisplayState());

  /// 请求登录码
  Future<void> requestCode() async {
    state = const QRCodeDisplayState(status: QRCodeDisplayStatus.loading);

    try {
      final deviceId = await PlatformUtil.getDeviceId();
      final deviceName = await PlatformUtil.getDeviceName();
      // Use postNoAuth: qrcode request is made before login, must bypass
      // the _refreshFailed/_logoutNotified short-circuit check.
      final resp = await _api.postNoAuth<Map<String, dynamic>>(
        ApiConstants.qrcodeRequest,
        data: {
          'device_id': deviceId,
          'device_name': deviceName,
        },
      );

      final body = resp.data!;
      if (body['code'] != 200 && body['code'] != 0) {
        state = QRCodeDisplayState(
          status: QRCodeDisplayStatus.error,
          error: body['msg'] ?? '请求登录码失败',
        );
        return;
      }

      final data = body['data'] as Map<String, dynamic>;
      final code = data['code'] as String;
      final qrUrl = data['qr_url'] as String;
      final expiresIn = data['expires_in'] as int?;

      state = QRCodeDisplayState(
        status: QRCodeDisplayStatus.displaying,
        code: code,
        qrUrl: qrUrl,
        expiresIn: expiresIn,
      );

      appLogger.i('TV 端登录码请求成功: code=$code');

      // 开始轮询
      _startPolling();
    } catch (e) {
      appLogger.e('请求登录码失败', error: e);
      state = QRCodeDisplayState(
        status: QRCodeDisplayStatus.error,
        error: '请求登录码失败: $e',
      );
    }
  }

  /// 开始轮询确认结果
  void _startPolling() {
    _pollCount = 0;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _poll(),
    );
  }

  /// 轮询一次
  Future<void> _poll() async {
    final code = state.code;
    if (code == null) {
      _stopPolling();
      return;
    }

    _pollCount++;
    if (_pollCount > _maxPollCount) {
      _stopPolling();
      state = state.copyWith(status: QRCodeDisplayStatus.expired);
      return;
    }

    try {
      // Use postNoAuth: qrcode poll is made before login completes
      final resp = await _api.postNoAuth<Map<String, dynamic>>(
        ApiConstants.qrcodePoll,
        data: {'code': code},
      );

      final body = resp.data!;
      if (body['code'] != 200 && body['code'] != 0) {
        return; // 继续轮询
      }

      final data = body['data'] as Map<String, dynamic>;
      final status = data['status'] as String;

      if (status == 'confirmed') {
        _stopPolling();

        final accessToken = data['access_token'] as String?;
        final refreshToken = data['refresh_token'] as String?;

        if (accessToken != null && refreshToken != null) {
          // 保存 token
          await SecureStorageService.instance.setAccessToken(accessToken);
          await SecureStorageService.instance.setRefreshToken(refreshToken);
          await SecureStorageService.instance.setLoggedIn(true);

          // 通知 auth 状态更新
          _authNotifier.onQRCodeLoginSuccess(accessToken, refreshToken);

          state = state.copyWith(status: QRCodeDisplayStatus.confirmed);
          appLogger.i('TV 端扫码登录成功');
        } else {
          state = state.copyWith(
            status: QRCodeDisplayStatus.error,
            error: '登录返回数据不完整',
          );
        }
      } else if (status == 'expired') {
        _stopPolling();
        state = state.copyWith(status: QRCodeDisplayStatus.expired);
      }
      // status == 'waiting' → 继续轮询
    } catch (e) {
      appLogger.w('轮询登录结果失败: $e');
      // 网络错误继续轮询
    }
  }

  /// 停止轮询
  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 重新请求（二维码过期后调用）
  Future<void> refresh() async {
    _stopPolling();
    await requestCode();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}

final qrcodeDisplayProvider =
    StateNotifierProvider<QRCodeDisplayNotifier, QRCodeDisplayState>((ref) {
  final apiClient = ref.read(apiClientProvider);
  final authNotifier = ref.watch(authProvider.notifier);
  return QRCodeDisplayNotifier(apiClient, authNotifier);
});
