import 'package:flutter/services.dart';

/// 轻量级文件选择器，通过 MethodChannel 调用平台原生文件选取功能。
/// 替代 file_picker 第三方包，避免依赖冲突。
class NativeFilePicker {
  static const _channel = MethodChannel('com.meowtv/file_picker');

  /// 打开系统文件选择器，选取单个文件。
  ///
  /// [mimeTypes] 为 MIME 类型过滤列表，如 `['text/plain', 'application/x-subrip']`。
  /// 返回选中文件的 URI 字符串，用户取消时返回 null。
  static Future<String?> pickFile({List<String>? mimeTypes}) async {
    try {
      final result = await _channel.invokeMethod<String>('pickFile', {
        'mimeTypes': mimeTypes,
      });
      return result;
    } on PlatformException {
      return null;
    }
  }

  /// 读取指定 URI 的文件内容为字符串。
  ///
  /// [uri] 为 [pickFile] 返回的文件 URI。
  /// 返回文件文本内容，读取失败时返回 null。
  static Future<String?> readFileContent(String uri) async {
    try {
      final result = await _channel.invokeMethod<String>('readFileContent', {
        'uri': uri,
      });
      return result;
    } on PlatformException {
      return null;
    }
  }
}
