import 'package:flutter/services.dart';
import '../../../core/logger/app_logger.dart';

/// 帧捕获平台通道
class FrameCaptureBridge {
  static const _channel = MethodChannel('com.meowtv.capture');

  /// 截取当前帧，返回 JPEG Uint8List
  Future<Uint8List?> captureFrame({int quality = 100}) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('captureFrame', {
        'quality': quality,
      });
      return result;
    } on PlatformException catch (e) {
      appLogger.e('[Capture] 截帧失败', error: e);
      return null;
    } on MissingPluginException {
      appLogger.w('[Capture] 截帧平台通道未注册');
      return null;
    }
  }

  /// 开始录制
  Future<bool> startRecording({
    String format = 'mp4',
    int fps = 30,
    int width = 1920,
    int height = 1080,
  }) async {
    try {
      await _channel.invokeMethod('startRecording', {
        'format': format,
        'fps': fps,
        'width': width,
        'height': height,
      });
      return true;
    } on PlatformException catch (e) {
      appLogger.e('[Capture] 录制启动失败', error: e);
      return false;
    } on MissingPluginException {
      appLogger.w('[Capture] 录制平台通道未注册');
      return false;
    }
  }

  /// 停止录制，返回文件路径
  Future<String?> stopRecording() async {
    try {
      final filePath = await _channel.invokeMethod<String>('stopRecording');
      return filePath;
    } on PlatformException catch (e) {
      appLogger.e('[Capture] 停止录制失败', error: e);
      return null;
    } on MissingPluginException {
      appLogger.w('[Capture] 录制平台通道未注册');
      return null;
    }
  }
}
