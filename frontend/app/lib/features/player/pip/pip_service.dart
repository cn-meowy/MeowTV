import 'dart:io';
import 'package:fl_pip/fl_pip.dart';
import '../../../core/logger/app_logger.dart';

/// 画中画服务 — 封装 fl_pip 插件调用
class PipService {
  PipService._();
  static final PipService instance = PipService._();

  final FlPiP _pip = FlPiP();

  /// 当前平台是否支持 PiP
  Future<bool> get isAvailable async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      return await _pip.isAvailable;
    } catch (e) {
      appLogger.w('[PipService] isAvailable check failed: $e');
      return false;
    }
  }

  /// 当前是否处于 PiP 模式
  bool get isActive {
    final info = _pip.status.value;
    return info?.status == PiPStatus.enabled;
  }

  /// 进入画中画模式
  Future<bool> enterPip() async {
    try {
      await _pip.enable(
        android: const FlPiPAndroidConfig(
          aspectRatio: Rational.landscape(),
        ),
        ios: const FlPiPiOSConfig(),
      );
      appLogger.i('[PipService] enterPip success');
      return true;
    } catch (e) {
      appLogger.e('[PipService] enterPip failed: $e');
      return false;
    }
  }

  /// 退出画中画模式
  Future<void> exitPip() async {
    try {
      await _pip.disable();
      appLogger.i('[PipService] exitPip success');
    } catch (e) {
      appLogger.e('[PipService] exitPip failed: $e');
    }
  }
}
