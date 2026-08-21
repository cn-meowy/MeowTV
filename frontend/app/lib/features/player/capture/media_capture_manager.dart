import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import '../../../core/logger/app_logger.dart';
import 'frame_capture_bridge.dart';
import 'media_save_service.dart';
import 'gif_generator.dart';

/// 捕获状态
enum CaptureState {
  idle,
  recording,
  processing,
}

/// 截图结果
class CaptureResult {
  final Uint8List imageData;
  final String filePath;
  final int width;
  final int height;

  const CaptureResult({
    required this.imageData,
    required this.filePath,
    required this.width,
    required this.height,
  });
}

/// 录制结果
class RecordResult {
  final String filePath;
  final Duration duration;
  final int fileSize;

  const RecordResult({
    required this.filePath,
    required this.duration,
    this.fileSize = 0,
  });
}

/// 媒体捕获管理器 — 统一管理截图/录制/GIF 生命周期
class MediaCaptureManager extends ChangeNotifier {
  final FrameCaptureBridge _bridge = FrameCaptureBridge();
  final MediaSaveService _saveService = MediaSaveService();
  final GifGenerator _gifGenerator = GifGenerator();

  CaptureState captureState = CaptureState.idle;

  /// 录制时长
  Duration recordDuration = Duration.zero;

  /// 录制计时器
  Timer? _recordTimer;

  /// 截图自动保存计时器
  Timer? _autoSaveTimer;

  /// 最后一次截图结果
  CaptureResult? lastScreenshot;

  /// 最后一次录制结果
  RecordResult? lastRecording;

  /// GIF 生成进度 (0.0 - 1.0)
  double gifProgress = 0.0;

  /// 最后一次 GIF 生成路径
  String? lastGifPath;

  /// 当前播放的视频源路径/URL（由 PlayerScreen 设置，供 GIF 生成使用）
  String? currentVideoPath;

  /// 当前视频总时长（由 PlayerScreen 设置，供 GIF 面板使用）
  Duration? currentVideoDuration;

  /// 最后一次错误信息（UI 层可监听并显示 Toast）
  String? lastError;

  /// 是否有未处理的错误
  bool get hasError => lastError != null;

  /// 清除错误状态（静默，不触发 notifyListeners，避免连锁通知导致已 dispose 的监听者崩溃）
  void clearError() {
    lastError = null;
  }

  /// 设置错误信息并通知监听者（供外部调用，避免直接访问 notifyListeners）
  void setError(String message) {
    lastError = message;
    notifyListeners();
  }

  /// 设置当前视频源信息（由 PlayerScreen 调用）
  void setVideoSource(String? path, {Duration? duration}) {
    currentVideoPath = path;
    currentVideoDuration = duration;
    notifyListeners();
  }

  /// 截图
  Future<CaptureResult?> screenshot() async {
    if (captureState != CaptureState.idle) return null;

    try {
      final imageData = await _bridge.captureFrame(quality: 100);
      if (imageData == null) {
        appLogger.w('[Capture] 截帧返回空数据');
        lastError = '截图失败：平台通道未响应，请确认当前平台支持截图功能';
        notifyListeners();
        return null;
      }

      // 保存到临时文件
      final filePath = await _saveToTempFile(imageData, 'jpg');

      // 解析图片宽高
      final dimensions = await _parseJpegDimensions(imageData);

      final result = CaptureResult(
        imageData: imageData,
        filePath: filePath,
        width: dimensions?.$1 ?? 0,
        height: dimensions?.$2 ?? 0,
      );

      lastScreenshot = result;
      notifyListeners();

      // 1.5 秒后自动保存到相册
      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(const Duration(milliseconds: 1500), () {
        if (lastScreenshot == result) {
          _handleSaveResult(
            _saveService.saveImageToGallery(imageData),
            '截图',
          );
        }
      });

      return result;
    } catch (e) {
      appLogger.e('[Capture] 截图失败', error: e);
      lastError = '截图失败：$e';
      notifyListeners();
      return null;
    }
  }

  /// 开始录制
  Future<bool> startRecording() async {
    if (captureState != CaptureState.idle) return false;

    final success = await _bridge.startRecording(
      format: 'mp4',
      fps: 30,
      width: 1920,
      height: 1080,
    );

    if (success) {
      captureState = CaptureState.recording;
      recordDuration = Duration.zero;
      _startRecordTimer();
      notifyListeners();
      appLogger.i('[Capture] 录制开始');
    } else {
      lastError = '录制启动失败，请确认当前平台支持录制功能';
      notifyListeners();
    }

    return success;
  }

  /// 停止录制
  Future<RecordResult?> stopRecording() async {
    if (captureState != CaptureState.recording) return null;

    _recordTimer?.cancel();
    captureState = CaptureState.processing;
    notifyListeners();

    try {
      final filePath = await _bridge.stopRecording();
      if (filePath == null) {
        appLogger.w('[Capture] 停止录制返回空路径');
        lastError = '录制停止失败：未获取到录制文件';
        captureState = CaptureState.idle;
        notifyListeners();
        return null;
      }

      // 检查录制时长是否过短
      if (recordDuration.inSeconds < 1) {
        appLogger.w('[Capture] 录制时间过短: ${recordDuration.inMilliseconds}ms');
        lastError = '录制时间过短，请至少录制 1 秒';
        captureState = CaptureState.idle;
        notifyListeners();
        return null;
      }

      final result = RecordResult(
        filePath: filePath,
        duration: recordDuration,
      );

      lastRecording = result;
      captureState = CaptureState.idle;
      notifyListeners();

      appLogger.i('[Capture] 录制完成: $filePath, 时长: ${recordDuration.inSeconds}s');
      return result;
    } catch (e) {
      appLogger.e('[Capture] 停止录制失败', error: e);
      lastError = '停止录制失败：$e';
      captureState = CaptureState.idle;
      notifyListeners();
      return null;
    }
  }

  /// 生成 GIF
  Future<String?> generateGif({
    required String videoPath,
    required Duration start,
    required Duration end,
    int fps = 10,
    int width = 480,
    int quality = 50,
  }) async {
    try {
      gifProgress = 0.0;
      notifyListeners();

      final result = await _gifGenerator.generate(
        videoPath: videoPath,
        start: start,
        end: end,
        fps: fps,
        width: width,
        quality: quality,
        onProgress: (progress) {
          gifProgress = progress;
          notifyListeners();
        },
      );

      if (result == null) {
        gifProgress = 0.0;
        lastError = 'GIF 生成失败，请检查视频源是否可用';
        notifyListeners();
        return null;
      }

      gifProgress = 1.0;
      lastGifPath = result.filePath;
      notifyListeners();
      return result.filePath;
    } catch (e) {
      appLogger.e('[Capture] GIF 生成失败', error: e);
      gifProgress = 0.0;
      lastError = 'GIF 生成异常：$e';
      notifyListeners();
      return null;
    }
  }

  /// 保存截图到相册
  Future<bool> saveScreenshotToGallery() async {
    if (lastScreenshot == null) return false;
    return _handleSaveResult(
      _saveService.saveImageToGallery(lastScreenshot!.imageData),
      '截图',
    );
  }

  /// 分享截图
  Future<void> shareScreenshot() async {
    if (lastScreenshot == null) return;
    await _saveService.shareImage(lastScreenshot!.imageData);
  }

  /// 保存录制到相册
  Future<bool> saveRecordingToGallery() async {
    if (lastRecording == null) return false;
    return _handleSaveResult(
      _saveService.saveVideoToGallery(lastRecording!.filePath),
      '录制视频',
    );
  }

  /// 分享录制
  Future<void> shareRecording() async {
    if (lastRecording == null) return;
    await _saveService.shareVideo(lastRecording!.filePath);
  }

  /// 保存 GIF 到相册
  Future<bool> saveGifToGallery(String gifPath) async {
    return _handleSaveResult(
      _saveService.saveGifToGallery(gifPath),
      'GIF',
    );
  }

  /// 分享 GIF
  Future<void> shareGif(String gifPath) async {
    await _saveService.shareGif(gifPath);
  }

  /// 录制计时器
  void _startRecordTimer() {
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      recordDuration += const Duration(seconds: 1);
      notifyListeners();

      // 60 秒自动停止
      if (recordDuration.inSeconds >= 60) {
        stopRecording();
      }
    });
  }

  /// 写入临时文件
  Future<String> _saveToTempFile(Uint8List data, String ext) async {
    final tempDir = Directory.systemTemp;
    final filePath = '${tempDir.path}/meowtv_capture_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(filePath).writeAsBytes(data);
    return filePath;
  }

  /// 从图片数据解析宽高
  Future<(int, int)?> _parseJpegDimensions(Uint8List data) async {
    final completer = Completer<(int, int)?>();
    ui.decodeImageFromList(data, (image) {
      completer.complete((image.width, image.height));
      image.dispose();
    });
    try {
      return await completer.future.timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  /// 清除截图预览
  void dismissScreenshot() {
    lastScreenshot = null;
    _autoSaveTimer?.cancel();
    notifyListeners();
  }

  /// 清除录制预览
  void dismissRecording() {
    lastRecording = null;
    notifyListeners();
  }

  /// 清除 GIF 预览
  void dismissGif() {
    lastGifPath = null;
    notifyListeners();
  }

  /// 处理保存结果，权限拒绝时设置用户友好提示
  Future<bool> _handleSaveResult(Future<SaveResult> resultFuture, String label) async {
    final result = await resultFuture;
    switch (result) {
      case SaveResult.success:
        appLogger.i('[Capture] $label已保存到相册');
        return true;
      case SaveResult.accessDenied:
        lastError = '保存$label失败：相册权限未授予，请在系统设置中允许 PurrTV 访问相册';
        notifyListeners();
        return false;
      case SaveResult.failed:
        lastError = '保存$label失败，请稍后重试';
        notifyListeners();
        return false;
    }
  }

  /// 重置
  void reset({bool notify = true}) {
    _recordTimer?.cancel();
    _autoSaveTimer?.cancel();
    captureState = CaptureState.idle;
    recordDuration = Duration.zero;
    lastScreenshot = null;
    lastRecording = null;
    lastGifPath = null;
    gifProgress = 0.0;
    lastError = null;
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _autoSaveTimer?.cancel();
    super.dispose();
  }
}
