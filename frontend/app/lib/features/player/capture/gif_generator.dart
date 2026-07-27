import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/logger/app_logger.dart';

/// GIF 生成结果
class GifResult {
  final String filePath;
  final int width;
  final int height;
  final int frameCount;
  final int fileSize;

  const GifResult({
    required this.filePath,
    required this.width,
    required this.height,
    this.frameCount = 0,
    this.fileSize = 0,
  });
}

/// GIF 生成器 - 基于 ffmpeg_kit_flutter_new
class GifGenerator {
  /// 从视频片段生成 GIF
  /// 使用两遍 palette 优化，生成高质量 GIF
  Future<GifResult?> generate({
    required String videoPath,
    required Duration start,
    required Duration end,
    int fps = 10,
    int width = 480,
    int quality = 50,
    void Function(double progress)? onProgress,
  }) async {
    try {
      // 校验视频路径
      if (videoPath.isEmpty) {
        appLogger.e('[GifGenerator] 视频路径为空，无法生成 GIF');
        return null;
      }

      // 防护：网络流 URL 不能直接传给 ffmpeg（min flavor 不含 HLS/http 协议支持）
      if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
        appLogger.e('[GifGenerator] 不支持从网络流 URL 生成 GIF，请先录制视频再从录制文件生成');
        return null;
      }

      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}/meowtv_gif_${DateTime.now().millisecondsSinceEpoch}.gif';

      final startTime = start.inMilliseconds / 1000.0;
      final endTime = end.inMilliseconds / 1000.0;

      // 使用参数列表代替拼接字符串，避免引号/空格/特殊字符问题
      final arguments = <String>[
        '-y',
        '-ss', startTime.toStringAsFixed(3),
        '-to', endTime.toStringAsFixed(3),
        '-i', videoPath,
        '-vf', 'fps=$fps,scale=$width:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=256:stats_mode=diff[p];[s1][p]paletteuse=dither=sierra2_4a',
        '-loop', '0',
        outputPath,
      ];

      appLogger.i('[GifGenerator] 执行参数: $arguments');

      // 注册进度回调
      if (onProgress != null) {
        final totalMs = end.inMilliseconds - start.inMilliseconds;
        FFmpegKitConfig.enableStatisticsCallback((stats) {
          if (totalMs <= 0) return;
          final time = stats.getTime();
          onProgress((time / totalMs).clamp(0.0, 1.0));
        });
      }

      // 注册日志回调，便于调试
      FFmpegKitConfig.enableLogCallback((log) {
        final msg = log.getMessage();
        if (msg.contains('Error') || msg.contains('error') || msg.contains('failed')) {
          appLogger.w('[GifGenerator] ffmpeg log: $msg');
        }
      });

      final session = await FFmpegKit.executeWithArguments(arguments);
      final returnCode = await session.getReturnCode();

      // 清理回调
      FFmpegKitConfig.enableStatisticsCallback(null);
      FFmpegKitConfig.enableLogCallback(null);

      if (!ReturnCode.isSuccess(returnCode)) {
        // 获取失败日志
        final output = await session.getOutput();
        final outputStr = output ?? '';
        appLogger.e('[GifGenerator] GIF 生成失败, returnCode: $returnCode, output: ${outputStr.substring(0, outputStr.length.clamp(0, 500))}');
        return null;
      }

      final file = File(outputPath);
      if (!await file.exists()) {
        appLogger.e('[GifGenerator] GIF 文件不存在: $outputPath');
        return null;
      }

      final fileSize = await file.length();
      appLogger.i('[GifGenerator] GIF 生成成功: $outputPath, 大小: $fileSize bytes');

      return GifResult(
        filePath: outputPath,
        width: width,
        height: 0,
        fileSize: fileSize,
      );
    } catch (e) {
      appLogger.e('[GifGenerator] GIF 生成异常', error: e);
      return null;
    }
  }
}
