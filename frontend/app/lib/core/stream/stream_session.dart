import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../logger/app_logger.dart';
import 'm3u8_parser.dart';
import 'segment_cache_manager.dart';
import 'stream_config.dart';
import 'stream_scheduler.dart';
import 'stream_worker.dart';

/// 生成会话 key：SHA256(m3u8URL) 前16位 — 对应后端 GenerateSessionKey
String generateSessionKey(String m3u8URL) {
  final bytes = utf8.encode(m3u8URL);
  final digest = sha256.convert(bytes);
  return digest.toString().substring(0, 16);
}

/// StreamSession — 每个 m3u8 URL 对应的会话，对应后端 StreamSession
///
/// 负责：
/// - m3u8 解析和重写
/// - 分片缓存管理
/// - 调度器管理
/// - 加密 Key 代理
class StreamSession {
  final String sessionKey;
  final String m3u8URL;
  final M3u8Info m3u8Info;
  final SegmentCacheManager cacheManager;

  /// 共享 HttpClient — Worker 和调度器复用 TCP 连接
  final HttpClient _httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 60);

  StreamScheduler? _scheduler;
  SessionState _state = SessionState.created;
  // ignore: unused_field
  final DateTime _createdAt;
  DateTime _lastAccess;
  final String segmentDir;

  /// 加密 Key 缓存：keyURI -> keyData
  final Map<String, Uint8List> _keyCache = {};

  /// 已缓存的加密 key 数量（诊断用）
  int get keyCacheCount => _keyCache.length;

  StreamSession._({
    required this.sessionKey,
    required this.m3u8URL,
    required this.m3u8Info,
    required this.cacheManager,
    required this.segmentDir,
  })  : _createdAt = DateTime.now(),
        _lastAccess = DateTime.now();

  /// 构造测试用 StreamSession（不发起网络请求、不要求磁盘目录存在）。
  ///
  /// 仅供单元测试使用（[pause] 行为验证），生产代码应通过 [create] 创建。
  @visibleForTesting
  static StreamSession createForTest({
    required String sessionKey,
    required String m3u8URL,
    required M3u8Info m3u8Info,
    required SegmentCacheManager cacheManager,
    required String segmentDir,
  }) {
    return StreamSession._(
      sessionKey: sessionKey,
      m3u8URL: m3u8URL,
      m3u8Info: m3u8Info,
      cacheManager: cacheManager,
      segmentDir: segmentDir,
    );
  }

  /// 创建 StreamSession — 对应后端 NewStreamSession
  ///
  /// [m3u8URL] 原始 m3u8 URL
  /// [parser] M3u8Parser 实例
  /// [segmentDir] 分片临时目录
  /// [m3u8Content] 已获取的 m3u8 文本内容（可选，避免重复请求远程源）
  static Future<StreamSession> create({
    required String m3u8URL,
    required M3u8Parser parser,
    required String segmentDir,
    String? m3u8Content,
  }) async {
    // 生成会话 key
    final sessionKey = generateSessionKey(m3u8URL);

    // 解析 m3u8（使用已获取的内容或远程获取）
    final m3u8Info = m3u8Content != null
        ? await parser.parseContent(m3u8Content, m3u8URL)
        : await parser.parse(m3u8URL);

    // 验证是否为 VOD 流
    if (!m3u8Info.isVOD) {
      throw Exception('only VOD streams are supported (missing EXT-X-ENDLIST)');
    }

    // 创建临时目录
    final dir = Directory(segmentDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // 初始化分片缓存管理器
    final totalSegments = m3u8Info.segments.length;
    final cacheManager = SegmentCacheManager(
      totalSegments: totalSegments,
      segmentDir: segmentDir,
    );

    final session = StreamSession._(
      sessionKey: sessionKey,
      m3u8URL: m3u8URL,
      m3u8Info: m3u8Info,
      cacheManager: cacheManager,
      segmentDir: segmentDir,
    );

    // 获取加密 key（失败时抛出异常，阻止创建无效 session）
    await session._fetchEncryptionKeys(parser);

    appLogger.i('[StreamSession] 创建: sessionKey=$sessionKey, totalSegments=$totalSegments, duration=${m3u8Info.duration.toStringAsFixed(1)}s, '
        'encrypted=${m3u8Info.encryption != null}, keyCached=${session._keyCache.length}');

    return session;
  }

  /// 获取所有加密 key
  Future<void> _fetchEncryptionKeys(M3u8Parser parser) async {
    // 全局加密 key
    if (m3u8Info.encryption != null && m3u8Info.encryption!.method == 'AES-128') {
      var keyURI = m3u8Info.encryption!.keyURI;

      // 如果 keyURI 是相对路径，尝试解析为绝对 URL
      if (!keyURI.startsWith('http://') && !keyURI.startsWith('https://')) {
        final resolved = _tryResolveURL(m3u8URL, keyURI);
        if (resolved != null) {
          appLogger.d('[StreamSession] _fetchEncryptionKeys: 全局 keyURI 相对路径解析: $keyURI -> $resolved');
          // 回填绝对 URL
          _backfillKeyURI(keyURI, resolved);
          keyURI = resolved;
        } else {
          appLogger.w('[StreamSession] _fetchEncryptionKeys: 全局 keyURI 为相对路径且无法解析: $keyURI, m3u8URL=$m3u8URL');
        }
      }

      if (!_keyCache.containsKey(keyURI)) {
        try {
          final keyData = await parser.fetchEncryptionKey(keyURI, referer: m3u8URL);
          _keyCache[keyURI] = keyData;
          m3u8Info.encryption!.key = keyData;
          appLogger.i('[StreamSession] 全局加密 key 获取成功: keyURI=$keyURI, bytes=${keyData.length}, '
              'hex=${_bytesToHex(keyData, 8)}');
        } catch (e) {
          appLogger.e('[StreamSession] 获取全局加密 key 失败: $keyURI, m3u8URL=$m3u8URL', error: e);
          // 关键修复：密钥获取失败必须抛出异常，阻止创建无效 session。
          // 否则 session 中 encryption.key 为 null，但 m3u8 重写仍生成
          // #EXT-X-KEY:URI=... 指向代理，AVPlayer 请求密钥时拿到错误数据
          // -> 用错误密钥解密 TS -> 乱码 -> fmt? (kCMFormatDescriptionError_InvalidFormat)
          rethrow;
        }
      } else {
        m3u8Info.encryption!.key = _keyCache[keyURI];
        appLogger.i('[StreamSession] 全局加密 key 命中缓存: keyURI=$keyURI, bytes=${_keyCache[keyURI]!.length}');
      }
    }

    // 分片级加密 key
    for (var i = 0; i < m3u8Info.segments.length; i++) {
      final seg = m3u8Info.segments[i];
      if (seg.encryption == null || seg.encryption!.method != 'AES-128') continue;

      // 如果分片加密与全局加密相同，复用
      if (m3u8Info.encryption != null && seg.encryption!.keyURI == m3u8Info.encryption!.keyURI) {
        seg.encryption!.key = m3u8Info.encryption!.key;
        continue;
      }

      var keyURI = seg.encryption!.keyURI;

      // 如果 keyURI 是相对路径，尝试解析为绝对 URL
      if (!keyURI.startsWith('http://') && !keyURI.startsWith('https://')) {
        final resolved = _tryResolveURL(m3u8URL, keyURI);
        if (resolved != null) {
          appLogger.d('[StreamSession] _fetchEncryptionKeys: 分片 $i keyURI 相对路径解析: $keyURI -> $resolved');
          _backfillKeyURI(keyURI, resolved);
          keyURI = resolved;
        } else {
          appLogger.w('[StreamSession] _fetchEncryptionKeys: 分片 $i keyURI 为相对路径且无法解析: $keyURI, m3u8URL=$m3u8URL');
        }
      }

      if (_keyCache.containsKey(keyURI)) {
        seg.encryption!.key = _keyCache[keyURI];
      } else {
        try {
          final keyData = await parser.fetchEncryptionKey(keyURI, referer: m3u8URL);
          _keyCache[keyURI] = keyData;
          seg.encryption!.key = keyData;
          appLogger.i('[StreamSession] 分片加密 key 获取成功: segment=$i, keyURI=$keyURI, bytes=${keyData.length}, '
              'hex=${_bytesToHex(keyData, 8)}');
        } catch (e) {
          appLogger.e('[StreamSession] 获取分片加密 key 失败: segment=$i, keyURI=$keyURI, m3u8URL=$m3u8URL', error: e);
          // 密钥获取失败必须抛出异常，阻止创建无效 session（同全局密钥逻辑）
          rethrow;
        }
      }
    }
  }

  // ==================== 启停管理 ====================

  /// 启动 Session 和调度器
  void start([StreamConfig? config]) {
    final effectiveConfig = config ?? StreamConfig.defaults;

    // 检查是否所有分片已通过磁盘缓存恢复完成
    if (cacheManager.isAllDone) {
      _state = SessionState.completed;
      appLogger.i('[StreamSession] 磁盘缓存恢复完成: sessionKey=$sessionKey, total=${cacheManager.totalSegments}');
      return;
    }

    // 创建并启动调度中心
    final sessionRef = StreamSessionRef(
      m3u8Info: m3u8Info,
      m3u8URL: m3u8URL,
      cacheManager: cacheManager,
      httpClient: _httpClient,
    );
    _scheduler = StreamScheduler(
      session: sessionRef,
      config: effectiveConfig,
    );
    _scheduler!.start();
    _state = SessionState.active;
  }

  /// 停止 Session
  void stop() {
    _scheduler?.stop();
    _scheduler = null;
    _state = SessionState.idle;
    appLogger.i('[StreamSession] 停止: sessionKey=$sessionKey');
  }

  /// 暂停 Session（退出播放页）：停止调度器；
  /// 将 downloading 分片重置为 pending（保证恢复后调度器能重新入队，不会卡死）；
  /// 状态置为 paused，请求处理器不再自动重启。
  void pause() {
    _scheduler?.stop();
    _scheduler = null;
    for (final idx in cacheManager.getDownloadingSegments()) {
      cacheManager.resetDownloadingToPending(idx);
    }
    _state = SessionState.paused;
    appLogger.i('[StreamSession] 暂停: sessionKey=$sessionKey');
  }

  /// 清理资源
  Future<void> cleanup(bool keepDisk) async {
    stop();
    await cacheManager.cleanup(keepDisk);
  }

  // ==================== m3u8 重写 ====================

  /// 获取重写后的 m3u8 内容 — 对应后端 GetRewrittenM3U8
  ///
  /// [proxyBaseUrl] 代理服务器基础 URL（如 http://localhost:PORT）
  /// 返回重写后的 m3u8 文本，TS URL 和 Key URI 替换为本地代理 URL
  String getRewrittenM3U8(String proxyBaseUrl, {required String urlKey}) {
    _refreshLastAccess();

    try {
      return _rewriteM3U8(m3u8Info, urlKey, proxyBaseUrl);
    } catch (e) {
      appLogger.e('[StreamSession] m3u8 重写失败: sessionKey=$sessionKey, urlKey=$urlKey', error: e);
      return m3u8Info.rawContent; // 兜底返回原始内容
    }
  }

  /// 行级替换重写 m3u8 — 对应后端 rewriteM3U8
  ///
  /// 规则：
  /// - #EXT-X-KEY: 保留，将 KeyURI 重写为本地代理接口
  /// - TS URL（非空且非 # 开头）：替换为 /hls-segment/{urlKey}/{index}
  /// - #EXT-X-DISCONTINUITY: 由 SegmentInfo.isDiscontinuity 驱动，在对应分片前插入
  /// - 其他行：原样保留
  ///
  /// [urlKey] 用于构建代理 URL 路径的 key，由调用方传入（通常为 cacheKey），
  /// 确保与 VideoCacheProxyServer 路由匹配一致。
  String _rewriteM3U8(
    M3u8Info info,
    String urlKey,
    String proxyBaseUrl,
  ) {
    final sb = StringBuffer();
    var segIndex = 0;

    for (final rawLine in info.rawContent.split('\n')) {
      final line = rawLine.trim();

      // 跳过原始 DISCONTINUITY 标记（由 SegmentInfo.isDiscontinuity 驱动重新插入）
      if (line == '#EXT-X-DISCONTINUITY') {
        continue;
      }

      // 重写 EXT-X-KEY 的 URI 属性为本地代理接口
      if (line.startsWith('#EXT-X-KEY:')) {
        sb.writeln(_rewriteExtXKey(line, urlKey, proxyBaseUrl));
        continue;
      }

      // 替换 TS URL（非空且非 # 开头）
      if (line.isNotEmpty && !line.startsWith('#')) {
        // 如果此分片有 DISCONTINUITY 标记，在 EXTINF/URL 前插入
        if (segIndex < info.segments.length && info.segments[segIndex].isDiscontinuity) {
          sb.writeln('#EXT-X-DISCONTINUITY');
          appLogger.d('[StreamSession] inserting DISCONTINUITY before segment $segIndex');
        }
        final proxyURL = '$proxyBaseUrl/hls-segment/$urlKey/$segIndex';
        sb.writeln(proxyURL);
        if (segIndex < 3) {
          appLogger.d('[StreamSession] 重写 TS URL: index=$segIndex, original=$line, proxy=$proxyURL');
        }
        segIndex++;
        continue;
      }

      // 其他行原样保留
      sb.writeln(rawLine);
    }

    appLogger.d('[StreamSession] m3u8 重写完成: urlKey=$urlKey, totalSegments=$segIndex');
    return sb.toString();
  }

  /// 构建完全重写的 m3u8 — 不依赖原始文本行级替换，从解析数据重新生成。
  ///
  /// 解决 Android 上 mpv/FFmpeg HLS demuxer 的 PTS 重建问题：
  /// - 原始 m3u8 可能缺少 #EXT-X-TARGETDURATION 或 #EXT-X-MEDIA-SEQUENCE
  /// - 行级替换可能遗漏或重复关键标签
  /// - 从解析数据重建可确保标签完整性和顺序正确
  ///
  /// 生成格式（严格遵循 HLS RFC 8216）：
  /// ```
  /// #EXTM3U
  /// #EXT-X-VERSION:3
  /// #EXT-X-TARGETDURATION:<maxDuration>
  /// #EXT-X-MEDIA-SEQUENCE:0
  /// #EXT-X-PLAYLIST-TYPE:VOD
  /// [#EXT-X-KEY:METHOD=AES-128,URI="...",IV=...]
  /// #EXTINF:<duration>,
  /// /hls-segment/<urlKey>/0
  /// [#EXT-X-DISCONTINUITY]
  /// #EXTINF:<duration>,
  /// /hls-segment/<urlKey>/1
  /// ...
  /// #EXT-X-ENDLIST
  /// ```
  String buildRewrittenM3U8(String proxyBaseUrl, {required String urlKey}) {
    _refreshLastAccess();

    final sb = StringBuffer();

    // ── 头部标签 ──
    sb.writeln('#EXTM3U');
    sb.writeln('#EXT-X-VERSION:3');

    // #EXT-X-TARGETDURATION：取所有分片时长的最大值向上取整
    // 这是 HLS 规范要求的标签，FFmpeg 的 HLS demuxer 依赖它计算时间线
    final maxDuration = m3u8Info.segments.fold<double>(
      0.0, (max, seg) => seg.duration > max ? seg.duration : max,
    );
    sb.writeln('#EXT-X-TARGETDURATION:${maxDuration.ceil()}');

    // #EXT-X-MEDIA-SEQUENCE：固定为 0（VOD 流从第一个分片开始）
    // FFmpeg 的 HLS demuxer 依赖此标签确定分片起始序号，
    // 缺失时默认为 0，但显式声明可避免某些 FFmpeg 版本的解析差异
    sb.writeln('#EXT-X-MEDIA-SEQUENCE:0');

    // #EXT-X-PLAYLIST-TYPE:VOD — 明确告知 demuxer 这是点播流
    // VOD 类型意味着 playlist 不会更新，demuxer 不需要重新获取 playlist
    // 这可以防止 demuxer 在 seek 时重新请求 playlist 导致 PTS 重建错误
    if (m3u8Info.isVOD) {
      sb.writeln('#EXT-X-PLAYLIST-TYPE:VOD');
    }

    // ── 全局加密 key（如果所有分片使用相同加密）──
    if (m3u8Info.encryption != null && m3u8Info.encryption!.method == 'AES-128') {
      sb.writeln(_buildExtXKeyLine(m3u8Info.encryption!, urlKey, proxyBaseUrl));
    }

    // ── 分片列表 ──
    var lastEncryption = m3u8Info.encryption;
    for (var i = 0; i < m3u8Info.segments.length; i++) {
      final seg = m3u8Info.segments[i];

      // DISCONTINUITY 标记
      if (seg.isDiscontinuity) {
        sb.writeln('#EXT-X-DISCONTINUITY');
      }

      // 分片级加密 key 变更检测
      // 当分片的加密信息与上一个分片不同时，需要插入新的 #EXT-X-KEY
      if (seg.encryption != null && seg.encryption != lastEncryption) {
        sb.writeln(_buildExtXKeyLine(seg.encryption!, urlKey, proxyBaseUrl));
        lastEncryption = seg.encryption;
      } else if (seg.encryption == null && lastEncryption != null) {
        // 加密结束：插入 METHOD=NONE
        sb.writeln('#EXT-X-KEY:METHOD=NONE');
        lastEncryption = null;
      }

      // EXTINF + 分片 URL
      sb.writeln('#EXTINF:${seg.duration},');
      sb.writeln('$proxyBaseUrl/hls-segment/$urlKey/$i');
    }

    // ── 结束标签 ──
    if (m3u8Info.isVOD) {
      sb.writeln('#EXT-X-ENDLIST');
    }

    appLogger.i('[StreamSession] 完全重建 m3u8: urlKey=$urlKey, '
        'segments=${m3u8Info.segments.length}, '
        'targetDuration=${maxDuration.ceil()}, '
        'isVOD=${m3u8Info.isVOD}');

    return sb.toString();
  }

  /// 构建 #EXT-X-KEY 行 — 用于 buildRewrittenM3U8
  String _buildExtXKeyLine(EncryptionInfo enc, String urlKey, String proxyBaseUrl) {
    final proxyKeyURI = '$proxyBaseUrl/hls-key/$urlKey?keyuri=${Uri.encodeQueryComponent(enc.keyURI)}';
    final sb = StringBuffer();
    sb.write('#EXT-X-KEY:METHOD=${enc.method}');
    sb.write(',URI="$proxyKeyURI"');
    if (enc.iv != null) {
      sb.write(',IV=0x${enc.iv!.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    }
    return sb.toString();
  }

  /// 重写 EXT-X-KEY 行中的 URI — 对应后端 rewriteExtXKey
  String _rewriteExtXKey(String line, String urlKey, String proxyBaseUrl) {
    final attrs = parseHlsAttributes(line.substring('#EXT-X-KEY:'.length));
    final rawKeyURI = attrs['URI'];
    if (rawKeyURI == null || rawKeyURI.isEmpty) {
      return line; // 没有 URI 属性（如 METHOD=NONE），原样返回
    }

    // 确保 keyURI 为绝对 URL：如果 m3u8 解析时 _resolveURL 未能将相对路径转为绝对 URL，
    // 这里用 m3u8URL 作为 base 再次尝试解析
    var keyURI = rawKeyURI;
    if (!keyURI.startsWith('http://') && !keyURI.startsWith('https://')) {
      final resolved = _tryResolveURL(m3u8URL, keyURI);
      if (resolved != null) {
        appLogger.d('[StreamSession] _rewriteExtXKey: 将相对 keyURI 解析为绝对 URL: $keyURI -> $resolved');
        keyURI = resolved;
        // 回填到 m3u8Info 的 encryption 中，确保 proxyKey 能找到
        _backfillKeyURI(rawKeyURI, keyURI);
      } else {
        appLogger.w('[StreamSession] _rewriteExtXKey: 无法将相对 keyURI 解析为绝对 URL: $keyURI, m3u8URL=$m3u8URL');
      }
    }

    // 构建代理 Key URI
    final proxyKeyURI = '$proxyBaseUrl/hls-key/$urlKey?keyuri=${Uri.encodeQueryComponent(keyURI)}';

    // 在原始行中替换 URI="..." 为代理 URI
    final oldURIPart = 'URI="$rawKeyURI"';
    final newURIPart = 'URI="$proxyKeyURI"';
    var result = line.replaceFirst(oldURIPart, newURIPart);

    // 如果精确替换失败（可能引号风格不同），重建属性行
    if (result == line) {
      final sb = StringBuffer();
      sb.write('#EXT-X-KEY:');
      if (attrs.containsKey('METHOD')) {
        sb.write('METHOD=${attrs['METHOD']}');
      }
      sb.write(',URI="$proxyKeyURI"');
      if (attrs.containsKey('IV')) {
        sb.write(',IV=${attrs['IV']}');
      }
      // 其他未知属性原样追加
      for (final entry in attrs.entries) {
        if (entry.key == 'METHOD' || entry.key == 'URI' || entry.key == 'IV') continue;
        sb.write(',${entry.key}=${entry.value}');
      }
      result = sb.toString();
    }

    return result;
  }

  /// 尝试将相对 URL 解析为绝对 URL
  static String? _tryResolveURL(String baseURL, String ref) {
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return ref;
    }
    try {
      final base = Uri.parse(baseURL);
      if (!base.hasScheme || !base.hasAuthority) return null;
      final refUri = Uri.parse(ref);
      final resolved = base.resolveUri(refUri).toString();
      if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
        return resolved;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 回填 keyURI：将 m3u8Info 中仍为相对路径的 keyURI 更新为绝对 URL
  void _backfillKeyURI(String relativeURI, String absoluteURI) {
    // 更新全局加密信息
    if (m3u8Info.encryption != null && m3u8Info.encryption!.keyURI == relativeURI) {
      m3u8Info.encryption!.keyURI = absoluteURI;
    }
    // 更新分片级加密信息
    for (final seg in m3u8Info.segments) {
      if (seg.encryption != null && seg.encryption!.keyURI == relativeURI) {
        seg.encryption!.keyURI = absoluteURI;
      }
    }
    // 迁移 _keyCache 中的条目
    if (_keyCache.containsKey(relativeURI) && !_keyCache.containsKey(absoluteURI)) {
      _keyCache[absoluteURI] = _keyCache[relativeURI]!;
    }
  }


  // ==================== 加密 Key 代理 ====================

  /// 代理 AES-128 解密 key — 对应后端 ProxyKey
  ///
  /// [keyURI] 原始 key URI（可能是绝对 URL 或相对路径）
  /// 返回解密 key 数据
  Uint8List? proxyKey(String keyURI) {
    _refreshLastAccess();

    // 1. 精确匹配：从缓存中查找
    if (_keyCache.containsKey(keyURI)) {
      return _keyCache[keyURI];
    }

    // 2. 精确匹配：检查全局加密 key
    if (m3u8Info.encryption != null &&
        m3u8Info.encryption!.keyURI == keyURI &&
        m3u8Info.encryption!.key != null) {
      return m3u8Info.encryption!.key;
    }

    // 3. 精确匹配：检查分片级加密 key
    for (final seg in m3u8Info.segments) {
      if (seg.encryption != null &&
          seg.encryption!.keyURI == keyURI &&
          seg.encryption!.key != null) {
        return seg.encryption!.key;
      }
    }

    // 4. 模糊匹配：URL 规范化比较（处理相对路径 vs 绝对 URL 的差异）
    final result = _findKeyByNormalizedURI(keyURI);
    if (result != null) {
      appLogger.i('[StreamSession] 通过规范化匹配找到加密 key: requestKeyURI=$keyURI, matchedKeyURI=${result.$1}');
      // 回填缓存，下次精确匹配即可命中
      _keyCache[keyURI] = result.$2;
      return result.$2;
    }

    appLogger.w('[StreamSession] 加密 key 未找到: sessionKey=$sessionKey, keyURI=$keyURI, '
        'cachedKeys=${_keyCache.keys.toList()}, '
        'globalKeyURI=${m3u8Info.encryption?.keyURI}');
    return null;
  }

  /// 通过 URL 规范化比较查找 key
  ///
  /// 处理以下场景：
  /// - 请求的 keyURI 是绝对 URL，但缓存中是相对路径（或反之）
  /// - URL 末尾斜杠差异
  /// - scheme/大小写差异
  ///
  /// 返回 (matchedKeyURI, keyData) 或 null
  (String, Uint8List)? _findKeyByNormalizedURI(String keyURI) {
    final normalizedRequest = _normalizeKeyURI(keyURI);

    // 在 _keyCache 中查找
    for (final entry in _keyCache.entries) {
      if (_normalizeKeyURI(entry.key) == normalizedRequest) {
        return (entry.key, entry.value);
      }
    }

    // 在全局加密信息中查找
    if (m3u8Info.encryption != null && m3u8Info.encryption!.key != null) {
      if (_normalizeKeyURI(m3u8Info.encryption!.keyURI) == normalizedRequest) {
        return (m3u8Info.encryption!.keyURI, m3u8Info.encryption!.key!);
      }
    }

    // 在分片级加密信息中查找
    for (final seg in m3u8Info.segments) {
      if (seg.encryption != null && seg.encryption!.key != null) {
        if (_normalizeKeyURI(seg.encryption!.keyURI) == normalizedRequest) {
          return (seg.encryption!.keyURI, seg.encryption!.key!);
        }
      }
    }

    // 额外尝试：如果请求的 keyURI 是相对路径，尝试用 m3u8URL 解析为绝对 URL 后再匹配
    if (!keyURI.startsWith('http://') && !keyURI.startsWith('https://')) {
      final absoluteURI = _tryResolveURL(m3u8URL, keyURI);
      if (absoluteURI != null) {
        final normalizedAbsolute = _normalizeKeyURI(absoluteURI);
        for (final entry in _keyCache.entries) {
          if (_normalizeKeyURI(entry.key) == normalizedAbsolute) {
            return (entry.key, entry.value);
          }
        }
        if (m3u8Info.encryption != null && m3u8Info.encryption!.key != null) {
          if (_normalizeKeyURI(m3u8Info.encryption!.keyURI) == normalizedAbsolute) {
            return (m3u8Info.encryption!.keyURI, m3u8Info.encryption!.key!);
          }
        }
        for (final seg in m3u8Info.segments) {
          if (seg.encryption != null && seg.encryption!.key != null) {
            if (_normalizeKeyURI(seg.encryption!.keyURI) == normalizedAbsolute) {
              return (seg.encryption!.keyURI, seg.encryption!.key!);
            }
          }
        }
      }
    }

    return null;
  }

  /// 规范化 key URI 用于比较
  static String _normalizeKeyURI(String uri) {
    var normalized = uri.toLowerCase().trim();
    // 移除末尾斜杠
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    // 移除默认端口
    normalized = normalized.replaceFirst(RegExp(r':80/$'), '/');
    normalized = normalized.replaceFirst(RegExp(r':443/$'), '/');
    // 移除 fragment
    final hashIdx = normalized.indexOf('#');
    if (hashIdx >= 0) {
      normalized = normalized.substring(0, hashIdx);
    }
    return normalized;
  }

  /// 远程获取加密 key（降级方案，供 _handleHlsKey 调用）
  ///
  /// 当 proxyKey 精确匹配和规范化匹配都失败时，
  /// 尝试直接从远程源站获取 key。
  Future<Uint8List?> fetchKeyRemotelyFetchKey(String keyURI) async {
    _refreshLastAccess();

    // 确保 keyURI 是绝对 URL
    var absoluteURI = keyURI;
    if (!keyURI.startsWith('http://') && !keyURI.startsWith('https://')) {
      final resolved = _tryResolveURL(m3u8URL, keyURI);
      if (resolved != null) {
        absoluteURI = resolved;
      } else {
        appLogger.w('[StreamSession] 无法将相对 keyURI 解析为绝对 URL，无法远程获取: $keyURI');
        return null;
      }
    }

    // 检查是否已经尝试过且失败（避免重复请求）
    if (_keyCache.containsKey(absoluteURI)) {
      return _keyCache[absoluteURI];
    }

    try {
      appLogger.i('[StreamSession] 远程获取加密 key: $absoluteURI');
      final parser = M3u8Parser();
      try {
        final keyData = await parser.fetchEncryptionKey(absoluteURI, referer: m3u8URL);
        // 缓存结果（同时缓存相对路径和绝对路径形式）
        _keyCache[absoluteURI] = keyData;
        if (absoluteURI != keyURI) {
          _keyCache[keyURI] = keyData;
        }
        appLogger.i('[StreamSession] 远程获取加密 key 成功: $absoluteURI, bytes=${keyData.length}');
        return keyData;
      } finally {
        parser.close();
      }
    } catch (e) {
      appLogger.e('[StreamSession] 远程获取加密 key 失败: $absoluteURI', error: e);
      return null;
    }
  }

  // ==================== 辅助方法 ====================

  /// 将字节数据转换为十六进制字符串（仅前 maxBytes 字节），用于诊断日志
  static String _bytesToHex(Uint8List data, int maxBytes) {
    final len = data.length < maxBytes ? data.length : maxBytes;
    final sb = StringBuffer();
    for (var i = 0; i < len; i++) {
      sb.write(data[i].toRadixString(16).padLeft(2, '0'));
    }
    if (data.length > maxBytes) sb.write('...');
    return sb.toString();
  }

  // ==================== 状态管理 ====================

  /// 刷新最后访问时间
  void _refreshLastAccess() {
    _lastAccess = DateTime.now();
  }

  /// 获取会话状态
  SessionState get state => _state;

  /// 设置会话状态
  void setState(SessionState newState) {
    _state = newState;
  }

  /// 获取最后访问时间
  DateTime get lastAccess => _lastAccess;

  /// 获取分片目录
  String get segmentDirPath => segmentDir;

  /// 获取 StreamSessionRef（供 Worker/Scheduler 使用）
  StreamSessionRef get ref => StreamSessionRef(
        m3u8Info: m3u8Info,
        m3u8URL: m3u8URL,
        cacheManager: cacheManager,
        httpClient: _httpClient,
      );

  /// 通知紧急分片下载
  void notifyUrgentSegment(int segmentIndex) {
    _scheduler?.notifyUrgentSegment(segmentIndex);
  }

  // ==================== Seek 即时检测 ====================

  /// 播放器最近一次请求的分片索引 — 对应后端 UserProgress.LastRequestIndex
  /// 用于即时 seek 检测，比依赖前端周期性进度上报更及时
  int _lastRequestIndex = 0;

  /// 记录播放器实际请求的分片索引，用于即时 seek 检测 — 对应后端 RecordSegmentRequest
  ///
  /// 当播放器请求的分片索引与上次请求索引差值 > 3 时，视为 seek，
  /// 立即通知调度器重排任务队列，并更新调度器的播放位置。
  ///
  /// 相比依赖前端周期性进度上报（UpdateProgress），通过播放器实际请求行为
  /// 能更早检测到 seek，减少 seek 后的缓冲等待时间。
  void recordSegmentRequest(int segmentIndex) {
    final delta = (segmentIndex - _lastRequestIndex).abs();
    final oldIndex = _lastRequestIndex;
    _lastRequestIndex = segmentIndex;
    _refreshLastAccess();

    // seek 检测：请求分片索引与上次请求差值 > 3
    if (delta > 3 && oldIndex > 0) {
      _scheduler?.notifySeek(segmentIndex);
      appLogger.i('[StreamSession] seek detected by segment request, notifying scheduler: '
          'oldIndex=$oldIndex, newIndex=$segmentIndex, delta=$delta');
    } else {
      // 非 seek，仅更新调度器播放位置使窗口计算更准确
      _scheduler?.updateCurrentPosition(segmentIndex);
    }
  }
}
