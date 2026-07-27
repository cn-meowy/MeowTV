import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../logger/app_logger.dart';
import 'stream_config.dart';

/// M3u8Parser — m3u8 解析器，对应后端 M3u8Parser
///
/// 负责：
/// - 获取并解析 m3u8 playlist（master / media）
/// - 选择最高码率变体
/// - 解析 TS 分片列表、加密信息
/// - 获取 AES-128 解密 key
class M3u8Parser {
  final HttpClient _httpClient;

  M3u8Parser() : _httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 30);

  /// 关闭 HttpClient
  void close() {
    _httpClient.close(force: true);
  }

  /// 解析 m3u8 URL，返回统一的分片列表
  /// 如果是 master playlist，自动选择最高码率的 media playlist 并解析
  Future<M3u8Info> parse(String m3u8URL) async {
    final content = await _fetchContent(m3u8URL);
    return parseContent(content, m3u8URL);
  }

  /// 解析已获取的 m3u8 文本内容，返回统一的分片列表。
  ///
  /// 当调用方已通过其他途径获取了 m3u8 文本（如 /proxy/ 路由降级检测到 m3u8 内容时），
  /// 可直接调用此方法，避免重复请求远程源。
  /// 如果是 master playlist，仍需远程获取 media playlist 内容。
  Future<M3u8Info> parseContent(String content, String m3u8URL) async {
    if (_isMasterPlaylist(content)) {
      // Master playlist
      final variants = _parseMasterPlaylist(content, m3u8URL);

      // 选择最高码率
      final best = _selectBestVariant(variants);
      if (best == null) {
        throw Exception('no variant found in master playlist');
      }

      // 递归解析 media playlist（仍需远程获取）
      final mediaURL = _resolveURL(m3u8URL, best.uri);
      final mediaContent = await _fetchContent(mediaURL);

      final result = _parseMediaPlaylist(mediaContent, mediaURL);
      return M3u8Info(
        isMaster: true,
        isVOD: result.isVOD,
        variants: variants,
        segments: result.segments,
        encryption: result.encryption,
        duration: result.duration,
        mediaURL: mediaURL,
        rawContent: mediaContent,
      );
    }

    // Media playlist
    final result = _parseMediaPlaylist(content, m3u8URL);
    return M3u8Info(
      isMaster: false,
      isVOD: result.isVOD,
      segments: result.segments,
      encryption: result.encryption,
      duration: result.duration,
      rawContent: content,
    );
  }

  /// 获取 AES-128 解密 key
  ///
  /// [referer] 用于防盗链，通常传入 m3u8 URL（源站检查同源 Referer）。
  /// 很多视频源的密钥服务器有防盗链检查，缺失 Referer/UA 时可能返回
  /// HTTP 200 + 非 16 字节的错误内容（如 HTML 错误页），导致解密失败。
  Future<Uint8List> fetchEncryptionKey(String keyURI, {String? referer}) async {
    final resp = await _httpClient.getUrl(Uri.parse(keyURI));

    // 设置防盗链关键头部：User-Agent 和 Referer
    // 与 VideoCacheProxy._proxySegmentFromOrigin 保持一致
    resp.headers.set('User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    if (referer != null) {
      resp.headers.set('Referer', referer);
    }

    final response = await resp.close();
    if (response.statusCode != HttpStatus.ok) {
      throw Exception('fetch encryption key failed: HTTP ${response.statusCode}');
    }
    final data = await _collectBytes(response);

    // 验证密钥长度：AES-128 密钥必须为 16 字节
    // 源站防盗链可能返回 HTTP 200 + 错误内容（HTML 错误页等），
    // 长度校验可及早发现并抛出异常，避免错误密钥被静默缓存
    if (data.length != 16) {
      throw Exception(
          'invalid AES-128 key length: ${data.length} bytes (expected 16), keyURI=$keyURI');
    }

    return Uint8List.fromList(data);
  }

  // ==================== 内部方法 ====================

  /// 获取 m3u8 文本内容
  Future<String> _fetchContent(String url) async {
    final resp = await _httpClient.getUrl(Uri.parse(url));
    final response = await resp.close();
    if (response.statusCode != HttpStatus.ok) {
      throw Exception('fetch m3u8 content failed: HTTP ${response.statusCode}');
    }
    final bytes = await _collectBytes(response);
    return utf8.decode(bytes);
  }

  /// 收集 HttpClientResponse 的所有字节
  Future<List<int>> _collectBytes(HttpClientResponse response) async {
    final builder = BytesBuilder();
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  /// 判断是否为 master playlist
  static bool _isMasterPlaylist(String content) {
    for (final line in content.split('\n')) {
      if (line.trim().startsWith('#EXT-X-STREAM-INF:')) {
        return true;
      }
    }
    return false;
  }

  /// 解析 master playlist
  List<VariantInfo> _parseMasterPlaylist(String content, String baseURL) {
    final variants = <VariantInfo>[];
    final lines = content.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;

      final attrs = parseHlsAttributes(line.substring('#EXT-X-STREAM-INF:'.length));

      var bandwidth = 0;
      if (attrs.containsKey('BANDWIDTH')) {
        bandwidth = int.tryParse(attrs['BANDWIDTH']!) ?? 0;
      }
      final resolution = attrs['RESOLUTION'] ?? '';

      // 解析宽高
      int? width;
      int? height;
      if (resolution.isNotEmpty) {
        final parts = resolution.split('x');
        if (parts.length == 2) {
          width = int.tryParse(parts[0]);
          height = int.tryParse(parts[1]);
        }
      }

      // 解析帧率
      double? frameRate;
      if (attrs.containsKey('FRAME-RATE')) {
        frameRate = double.tryParse(attrs['FRAME-RATE']!);
      }

      // 解析编码
      final codec = attrs['CODECS'];

      // 解析名称
      final name = attrs['NAME'];

      // 下一行非空行是 URI
      String? uri;
      for (var j = i + 1; j < lines.length; j++) {
        final nextLine = lines[j].trim();
        if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
          uri = _resolveURL(baseURL, nextLine);
          i = j;
          break;
        }
      }

      if (uri != null) {
        variants.add(VariantInfo(
          bandwidth: bandwidth,
          resolution: resolution,
          uri: uri,
          width: width,
          height: height,
          frameRate: frameRate,
          codec: codec,
          name: name,
        ));
      }
    }

    if (variants.isEmpty) {
      throw Exception('no variants found in master playlist');
    }
    return variants;
  }

  /// 解析 media playlist
  _MediaPlaylistResult _parseMediaPlaylist(String content, String baseURL) {
    final segments = <SegmentInfo>[];
    EncryptionInfo? encryption;
    var totalDuration = 0.0;
    var currentDuration = 0.0;
    var isVOD = false;
    var segIndex = 0;
    var nextSegIsDiscontinuity = false;
    var discontinuityCount = 0;

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();

      // 检测 EXT-X-ENDLIST（标识 VOD 结束）
      if (line.startsWith('#EXT-X-ENDLIST')) {
        isVOD = true;
        continue;
      }

      // 检测 EXT-X-DISCONTINUITY（PTS 不连续标记）
      if (line == '#EXT-X-DISCONTINUITY') {
        nextSegIsDiscontinuity = true;
        appLogger.d('[M3u8Parser] DISCONTINUITY detected before segment $segIndex');
        continue;
      }

      // 解析 EXT-X-KEY
      if (line.startsWith('#EXT-X-KEY:')) {
        final attrs = parseHlsAttributes(line.substring('#EXT-X-KEY:'.length));
        final method = attrs['METHOD'];
        if (method == 'NONE') {
          encryption = null;
          continue;
        }
        if (method == 'AES-128') {
          final uri = attrs['URI'];
          if (uri != null) {
            encryption = EncryptionInfo(
              method: method!,
              keyURI: _resolveURL(baseURL, uri),
              iv: attrs.containsKey('IV') ? _parseIV(attrs['IV']!) : null,
            );
          } else {
            encryption = EncryptionInfo(method: method!, keyURI: '');
          }
        }
        continue;
      }

      // 解析 EXTINF
      if (line.startsWith('#EXTINF:')) {
        final durStr = line.substring('#EXTINF:'.length).replaceAll(',', '').trim();
        currentDuration = double.tryParse(durStr) ?? 0.0;
        continue;
      }

      // 跳过其他标签和空行
      if (line.isEmpty || line.startsWith('#')) continue;

      // 分片 URL
      final segURL = _resolveURL(baseURL, line);
      if (nextSegIsDiscontinuity) {
        discontinuityCount++;
      }
      segments.add(SegmentInfo(
        url: segURL,
        duration: currentDuration,
        index: segIndex,
        encryption: encryption, // 关联当前加密状态
        isDiscontinuity: nextSegIsDiscontinuity,
      ));
      nextSegIsDiscontinuity = false;
      totalDuration += currentDuration;
      segIndex++;
    }

    if (segments.isEmpty) {
      throw Exception('no segments found in media playlist');
    }

    appLogger.i('[M3u8Parser] parsed ${segments.length} segments, $discontinuityCount with DISCONTINUITY');

    return _MediaPlaylistResult(
      segments: segments,
      encryption: encryption,
      duration: totalDuration,
      isVOD: isVOD,
    );
  }

  /// 选择最高码率的变体
  static VariantInfo? _selectBestVariant(List<VariantInfo> variants) {
    if (variants.isEmpty) return null;
    var best = variants[0];
    for (var i = 1; i < variants.length; i++) {
      if (variants[i].bandwidth > best.bandwidth) {
        best = variants[i];
      }
    }
    return best;
  }

  /// 将相对路径转为绝对 URL — 对应后端 resolveURL
  static String _resolveURL(String baseURL, String ref) {
    // 已经是绝对 URL
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return ref;
    }

    try {
      final base = Uri.parse(baseURL);
      if (!base.hasScheme || !base.hasAuthority) {
        appLogger.w('[M3u8Parser] _resolveURL: baseURL 不是有效的绝对 URL: $baseURL, ref: $ref');
        // 尝试将 ref 当作绝对路径拼接（如果 ref 以 / 开头）
        if (ref.startsWith('/') && baseURL.startsWith('http')) {
          final uri = Uri.parse(baseURL);
          return '${uri.scheme}://${uri.host}${uri.hasPort && uri.port != 0 ? ':${uri.port}' : ''}$ref';
        }
        return ref;
      }
      final refUri = Uri.parse(ref);
      final resolved = base.resolveUri(refUri).toString();
      // 验证解析结果是否为绝对 URL
      if (!resolved.startsWith('http://') && !resolved.startsWith('https://')) {
        appLogger.w('[M3u8Parser] _resolveURL: 解析结果不是绝对 URL: resolved=$resolved, baseURL=$baseURL, ref=$ref');
      }
      return resolved;
    } catch (e) {
      appLogger.w('[M3u8Parser] _resolveURL: URL 解析异常: baseURL=$baseURL, ref=$ref', error: e);
      // 降级：如果 ref 以 / 开头且 baseURL 是 http URL，手动拼接
      if (ref.startsWith('/') && baseURL.startsWith('http')) {
        try {
          final uri = Uri.parse(baseURL);
          return '${uri.scheme}://${uri.host}${uri.hasPort && uri.port != 0 ? ':${uri.port}' : ''}$ref';
        } catch (_) {}
      }
      return ref;
    }
  }


  /// 解析 IV 值 (0x 开头的十六进制) — 对应后端 parseIV
  static Uint8List? _parseIV(String ivStr) {
    var str = ivStr;
    if (str.startsWith('0x') || str.startsWith('0X')) {
      str = str.substring(2);
    }
    try {
      final data = hexDecode(str); // 使用 stream_config.dart 中的共享方法
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  /// 选择指定变体并解析其 media playlist
  Future<M3u8Info> selectVariant(M3u8Info masterInfo, VariantInfo variant) async {
    if (!masterInfo.isMaster) return masterInfo;
    final mediaURL = _resolveURL(masterInfo.mediaURL, variant.uri);
    final mediaContent = await _fetchContent(mediaURL);
    final result = _parseMediaPlaylist(mediaContent, mediaURL);
    return M3u8Info(
      isMaster: true,
      isVOD: result.isVOD,
      variants: masterInfo.variants,
      segments: result.segments,
      encryption: result.encryption,
      duration: result.duration,
      mediaURL: mediaURL,
      rawContent: mediaContent,
    );
  }
}

/// media playlist 解析结果（内部使用）
class _MediaPlaylistResult {
  final List<SegmentInfo> segments;
  final EncryptionInfo? encryption;
  final double duration;
  final bool isVOD;

  const _MediaPlaylistResult({
    required this.segments,
    this.encryption,
    this.duration = 0,
    this.isVOD = false,
  });
}
