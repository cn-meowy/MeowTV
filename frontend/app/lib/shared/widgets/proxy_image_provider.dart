import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

import '../../core/logger/app_logger.dart';

/// 前端代理模式下通过 dio + headers 下载图片到本地，
/// 复用 flutter_cache_manager 的缓存目录结构，然后用 Image.file() 显示。
///
/// 解决 CachedNetworkImage 的 httpHeaders 参数在移动端无法绕过豆瓣防盗链的问题。

/// 单张代理图片的下载状态
class ProxyImageState {
  final String url;
  final String? localPath;
  final bool isLoading;
  final bool hasError;

  const ProxyImageState({
    required this.url,
    this.localPath,
    this.isLoading = false,
    this.hasError = false,
  });

  ProxyImageState copyWith({
    String? localPath,
    bool? isLoading,
    bool? hasError,
  }) =>
      ProxyImageState(
        url: url,
        localPath: localPath ?? this.localPath,
        isLoading: isLoading ?? this.isLoading,
        hasError: hasError ?? this.hasError,
      );
}

/// 下载并缓存需要自定义 headers 的图片。
class ProxyImageNotifier extends StateNotifier<ProxyImageState> {
  final Dio _dio;

  /// 缓存目录，惰性初始化
  static Directory? _cacheDir;

  /// 正在下载中的 URL 集合，防止重复下载
  static final Set<String> _downloading = {};

  ProxyImageNotifier(this._dio, String url)
      : super(ProxyImageState(url: url));

  /// 下载图片到本地缓存目录。
  /// 如果本地已有缓存文件，直接返回路径；否则用 dio + headers 下载。
  Future<void> load(Map<String, String> headers) async {
    if (_downloading.contains(state.url)) return;
    _downloading.add(state.url);

    state = state.copyWith(isLoading: true, hasError: false);

    try {
      // 确保缓存目录存在
      _cacheDir ??= await _ensureCacheDir();
      final cacheKey = _cacheKey(state.url);
      final file = File('${_cacheDir!.path}/$cacheKey');

      // 缓存命中：文件存在且大小 > 0
      if (await file.exists() && await file.length() > 0) {
        if (mounted) {
          state = state.copyWith(localPath: file.path, isLoading: false);
        }
        return;
      }
      // appLogger.d('ProxyImage download url = ${state.url} , headers = $headers');
      // 用 dio + headers 下载
      final response = await _dio.get<List<int>>(
        state.url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          validateStatus: (s) => s != null && s < 400,
        ),
      );

      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          state = state.copyWith(isLoading: false, hasError: true);
        }
        return;
      }

      // 确保父目录存在
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }

      // 写入文件
      await file.writeAsBytes(Uint8List.fromList(bytes));

      if (mounted) {
        state = state.copyWith(localPath: file.path, isLoading: false);
      }
    } catch (e, stackTrace) {
      appLogger.e('ProxyImage download failed', error: e, stackTrace: stackTrace);
      if (mounted) {
        state = state.copyWith(isLoading: false, hasError: true);
      }
    } finally {
      _downloading.remove(state.url);
    }
  }

  /// 以 URL 的 SHA-256 hash 前 16 位 + 扩展名作为缓存文件名
  static String _cacheKey(String url) {
    final bytes = utf8.encode(url);
    final digest = sha256.convert(bytes);
    // 尝试推断扩展名
    final ext = _extensionFromUrl(url);
    return '${digest.toString().substring(0, 16)}$ext';
  }

  /// 从 URL 推断图片扩展名
  static String _extensionFromUrl(String url) {
    // 去掉 query 参数
    final path = Uri.parse(url).path;
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return '.jpg';
    if (path.endsWith('.png')) return '.png';
    if (path.endsWith('.webp')) return '.webp';
    if (path.endsWith('.gif')) return '.gif';
    return '.jpg'; // 默认
  }

  /// 确保缓存目录存在，复用 flutter_cache_manager 的基础临时目录
  static Future<Directory> _ensureCacheDir() async {
    final baseDir = await getTemporaryDirectory();
    final dir = Directory('${baseDir.path}/meowtv_proxy_img');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}

/// 为指定 URL 创建 ProxyImage provider 的工厂
///
/// 使用方式：
/// ```dart
/// final provider = proxyImageProvider(url);
/// final state = ref.watch(provider);
/// ref.read(provider.notifier).load(headers);
/// ```
final proxyImageProvider =
    StateNotifierProvider.family<ProxyImageNotifier, ProxyImageState, String>(
  (ref, url) {
    final dio = Dio(); // 独立 dio 实例，不携带 auth interceptor
    return ProxyImageNotifier(dio, url);
  },
);
