import 'dart:io';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/logger/app_logger.dart';

/// 保存结果 — 区分成功、权限拒绝、其他失败
enum SaveResult {
  success,
  accessDenied,
  failed,
}

/// 媒体保存服务 — 保存到相册 + 系统分享
class MediaSaveService {
  /// 请求相册访问权限，返回是否已授权
  Future<bool> _requestAccess() async {
    try {
      // Gal.hasAccess 仅检查当前权限状态，不弹窗
      final hasAccess = await Gal.hasAccess();
      if (hasAccess) return true;

      // Gal.requestAccess 会弹出系统授权对话框
      final granted = await Gal.requestAccess();
      if (granted) {
        appLogger.i('[MediaSave] 相册权限已授予');
        return true;
      } else {
        appLogger.w('[MediaSave] 用户拒绝相册权限');
        return false;
      }
    } catch (e) {
      appLogger.e('[MediaSave] 检查/请求相册权限异常', error: e);
      return false;
    }
  }

  /// 判断异常是否为权限拒绝
  bool _isAccessDenied(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('access_denied') ||
        msg.contains('permission') ||
        msg.contains('galexception');
  }

  /// 保存图片到相册
  Future<SaveResult> saveImageToGallery(Uint8List imageData, {String? album}) async {
    // 先请求权限
    if (!await _requestAccess()) {
      appLogger.w('[MediaSave] 保存图片失败：相册权限未授予');
      return SaveResult.accessDenied;
    }
    try {
      await Gal.putImageBytes(imageData, album: album ?? 'MeowTV');
      appLogger.i('[MediaSave] 图片已保存到相册');
      return SaveResult.success;
    } catch (e) {
      appLogger.e('[MediaSave] 保存图片失败', error: e);
      return _isAccessDenied(e) ? SaveResult.accessDenied : SaveResult.failed;
    }
  }

  /// 保存视频到相册
  Future<SaveResult> saveVideoToGallery(String filePath, {String? album}) async {
    // 先请求权限
    if (!await _requestAccess()) {
      appLogger.w('[MediaSave] 保存视频失败：相册权限未授予');
      return SaveResult.accessDenied;
    }
    try {
      await Gal.putVideo(filePath, album: album ?? 'MeowTV');
      appLogger.i('[MediaSave] 视频已保存到相册');
      return SaveResult.success;
    } catch (e) {
      appLogger.e('[MediaSave] 保存视频失败', error: e);
      return _isAccessDenied(e) ? SaveResult.accessDenied : SaveResult.failed;
    }
  }

  /// 保存 GIF 到相册
  Future<SaveResult> saveGifToGallery(String filePath, {String? album}) async {
    // 先请求权限
    if (!await _requestAccess()) {
      appLogger.w('[MediaSave] 保存 GIF 失败：相册权限未授予');
      return SaveResult.accessDenied;
    }
    try {
      await Gal.putVideo(filePath, album: album ?? 'MeowTV');
      appLogger.i('[MediaSave] GIF 已保存到相册');
      return SaveResult.success;
    } catch (e) {
      appLogger.e('[MediaSave] 保存 GIF 失败', error: e);
      return _isAccessDenied(e) ? SaveResult.accessDenied : SaveResult.failed;
    }
  }

  /// 分享图片
  Future<void> shareImage(Uint8List imageData) async {
    try {
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/meowtv_share_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(imageData);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: 'MeowTV 截图',
      ));
    } catch (e) {
      appLogger.e('[MediaSave] 分享图片失败', error: e);
    }
  }

  /// 分享视频
  Future<void> shareVideo(String filePath) async {
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(filePath)],
        text: 'MeowTV 录制',
      ));
    } catch (e) {
      appLogger.e('[MediaSave] 分享视频失败', error: e);
    }
  }

  /// 分享 GIF
  Future<void> shareGif(String filePath) async {
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(filePath)],
        text: 'MeowTV GIF',
      ));
    } catch (e) {
      appLogger.e('[MediaSave] 分享 GIF 失败', error: e);
    }
  }
}
