import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../logger/app_logger.dart';
import '../stream/m3u8_parser.dart';
import '../stream/segment_cache_manager.dart';
import '../stream/stream_cache_manager.dart';
import '../stream/stream_config.dart';
import '../stream/stream_session.dart';

/// 本地 HTTP 代理服务器 — 边下边播核心。
///
/// 使用 dart:io HttpServer 替代 shelf 框架，更轻量稳定。
/// 路由：
/// - /hls/{cacheKey} — m3u8 playlist（StreamSession 获取重写后的 m3u8）
/// - /hls-segment/{cacheKey}/{segIndex} — TS 分片（已缓存直接返回，未缓存透传+后台下载）
/// - /hls-key/{cacheKey}?keyuri=xxx — AES-128 Key（返回解密 key）
/// - /proxy/{cacheKey} — MP4 直链代理（远程流式+写盘缓存）
class VideoCacheProxyServer {
  VideoCacheProxyServer._();
  static final VideoCacheProxyServer instance = VideoCacheProxyServer._();

  HttpServer? _server;
  int? _port;
  bool _isRunning = false;

  /// LAN 模式标记（合并为单服务器后仅用于兼容旧调用方）。
  int? _lanPort;
  bool _isLanRunning = false;

  /// cacheKey → 原始 URL 映射
  final Map<String, String> _keyUrlMap = {};

  /// cacheKey → StreamSession 映射
  final Map<String, StreamSession> _sessions = {};

  /// Session 创建完成回调（cacheKey → 通知监听者）
  final Map<String, void Function(StreamSession)> _onSessionCreatedCallbacks = {};

  /// M3u8Parser 共享实例
  M3u8Parser? _parser;

  /// 当前正在代理缓存的 key 集合
  final Set<String> _activeProxyKeys = {};

  /// 当前正在处理的请求（供 _preprocessRange 转发防盗链头部使用）
  HttpRequest? _currentRequest;

  /// 共享的 HttpClient（MP4 代理用）
  HttpClient? _remoteClient;
  HttpClient get remoteClient => _remoteClient ??= HttpClient();

  /// 本机网卡地址缓存（小写归一化），用于「源 IP 命中本机接口」判定。
  /// 缓存避免每次请求都调用 [NetworkInterface.list]，仅在快速私有段检查
  /// 失败后懒加载，并以 [_localInterfaceIpsTtl] 过期重新拉取。
  Set<String>? _localInterfaceIps;
  DateTime? _localInterfaceIpsAt;
  static const Duration _localInterfaceIpsTtl = Duration(seconds: 60);

  /// 获取代理服务器端口
  int? get port => _port;

  /// 是否正在运行
  bool get isRunning => _isRunning;

  /// 当前正在代理缓存的 key 数量
  int get activeProxyCount => _activeProxyKeys.length;

  /// 检查指定 key 是否正在被代理缓存
  bool isActivelyProxying(String key) => _activeProxyKeys.contains(key);

  /// 启动代理服务器（绑定 0.0.0.0，本机和投屏设备均可访问）。
  ///
  /// 局域网 IP 过滤由 [_handleRequest] 在入口处统一执行；
  /// 放行规则见 [_isPrivateAddress] 与 [isAllowedClientForTest]：
  /// 1. 源地址为 loopback / RFC1918 / fe80 / ::1（[_isPrivateAddress]）。
  /// 2. 源地址命中设备自身任一网卡地址（覆盖 iOS VPN/utun 公网段自连场景）。
  /// 3. Host 头指向 loopback（localhost / 127.* / ::1）。
  Future<void> start() async {
    if (_isRunning) return;

    try {
      _server = await HttpServer.bind('0.0.0.0', 0); // port=0 让 OS 分配随机端口
      _port = _server!.port;
      _isRunning = true;
      _parser = M3u8Parser();
      appLogger.i('[VideoCacheProxy] 代理服务器已启动 (0.0.0.0)，端口: $_port');

      // 监听请求
      _server!.listen(_handleRequest, onError: (error) {
        appLogger.e('[VideoCacheProxy] 服务器错误', error: error);
      });
    } catch (e) {
      appLogger.e('[VideoCacheProxy] 代理服务器启动失败', error: e);
      _isRunning = false;
      rethrow;
    }
  }

  /// 兼容旧调用方：单服务器后等价于 [start]，仅记录 LAN 端口引用。
  ///
  /// 历史背景：早期实现中 LAN 投屏需要独立的 0.0.0.0 服务器。
  /// 合并为单服务器后此方法仅为兼容 [player_screen.dart] 中的现有调用而保留。
  Future<void> startLan() async {
    await start();
    _isLanRunning = true;
    _lanPort = _port;
  }

  /// 停止代理服务器
  Future<void> stop() async {
    if (!_isRunning) return;
    await _server?.close(force: true);
    _server = null;
    _port = null;
    _isRunning = false;

    // 停止所有 Session
    for (final session in _sessions.values) {
      session.stop();
    }
    _sessions.clear();
    _keyUrlMap.clear();
    _activeProxyKeys.clear();
    _onSessionCreatedCallbacks.clear();

    _remoteClient?.close(force: true);
    _remoteClient = null;
    _parser?.close();
    _parser = null;

    appLogger.i('[VideoCacheProxy] 代理服务器已停止');
  }

  /// 注册 URL 映射（播放前调用）
  Future<void> register(String cacheKey, String url) async {
    _keyUrlMap[cacheKey] = url;
    appLogger.d('[VideoCacheProxy] 注册映射: $cacheKey -> $url');
  }

  /// 注销 URL 映射（播放结束后调用）
  void unregister(String cacheKey) {
    _keyUrlMap.remove(cacheKey);
    _activeProxyKeys.remove(cacheKey);
    _onSessionCreatedCallbacks.remove(cacheKey);
    _sessions.remove(cacheKey)?.stop();
    appLogger.d('[VideoCacheProxy] 注销映射: $cacheKey');
  }

  /// 构建代理 URL — 供 Player.open 使用
  ///
  /// [lanIp] 非空时返回 LAN IP URL（投屏设备可访问），为空时回退 localhost。
  String proxyUrl(String cacheKey, {String? lanIp}) {
    assert(_isRunning && _port != null);
    final host = (lanIp != null && lanIp.isNotEmpty) ? lanIp : 'localhost';
    return 'http://$host:$_port/proxy/$cacheKey';
  }

  /// 根据原始 URL 类型构建代理 URL。
  ///
  /// m3u8 走 /hls/ 路由（重写 playlist），MP4 走 /proxy/ 路由（直链代理）。
  String proxyUrlForType(String cacheKey, String originalUrl, {String? lanIp}) {
    assert(_isRunning && _port != null);
    final host = (lanIp != null && lanIp.isNotEmpty) ? lanIp : 'localhost';
    final prefix = _isHlsUrl(originalUrl) ? 'hls' : 'proxy';
    return 'http://$host:$_port/$prefix/$cacheKey';
  }

  /// 构建强制 HLS 代理 URL — 供方案B 边下边播使用。
  ///
  /// 始终走 /hls/ 路由，由代理服务器负责内容检测和降级。
  /// 边下边播模式需要解析 m3u8 才能调度分片下载，
  /// 即使原始 URL 实际是 MP4，/hls/ 路由也能通过内容嗅探降级处理。
  ///
  /// 解决 ExoPlayer 在 Android 上的 UnrecognizedInputFormatException：
  /// 当 [_isHlsUrl] 误判 m3u8 URL 为 MP4 时，/proxy/ 路由返回的 m3u8 文本
  /// 会被 ExoPlayer 的 ProgressiveMediaSource 用 MP4 Extractor 解析而失败；
  /// /hls/ 路由返回的 m3u8 文本则会被 ExoPlayer 的 HLS 解析器正确处理。
  ///
  /// [lanIp] 非空时返回 LAN IP URL（投屏设备可访问），为空时回退 localhost。
  String hlsProxyUrl(String cacheKey, {String? lanIp}) {
    assert(_isRunning && _port != null);
    final host = (lanIp != null && lanIp.isNotEmpty) ? lanIp : 'localhost';
    return 'http://$host:$_port/hls/$cacheKey';
  }

  /// 构建 LAN 模式的 HLS 代理 URL（兼容旧调用方）。
  ///
  /// 等价于 [hlsProxyUrl] 传入 [lanIp]。
  String lanHlsProxyUrl(String cacheKey, String lanIp) {
    return hlsProxyUrl(cacheKey, lanIp: lanIp);
  }

  /// 构建 LAN 模式的代理 URL（兼容旧调用方）。
  String lanProxyUrlForType(String cacheKey, String originalUrl, String lanIp) {
    return proxyUrlForType(cacheKey, originalUrl, lanIp: lanIp);
  }

  /// LAN 代理服务器端口
  int? get lanPort => _lanPort;

  /// LAN 代理服务器是否运行中
  bool get isLanRunning => _isLanRunning;

  /// 判断远程地址是否为私有/局域网地址。
  ///
  /// 允许：127.x（loopback）、10.x、172.16-31.x、192.168.x、IPv6 fe80/::1。
  /// 这是入口过滤的快速路径，仅覆盖 RFC1918/loopback 段；
  /// 完整的放行判定（含 iOS VPN/utun 公网段自连 + Host 头兜底）见
  /// [isAllowedClientForTest] 与 [_handleRequest]。
  bool _isPrivateAddress(InternetAddress addr) {
    if (addr.isLoopback) return true;
    final ip = addr.address;
    if (addr.type == InternetAddressType.IPv6) {
      return ip.startsWith('fe80') || ip == '::1';
    }
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]) ?? -1;
    final b = int.tryParse(parts[1]) ?? -1;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }

  /// 获取本机网卡地址集合（带 TTL 缓存）。
  ///
  /// 仅在 [_handleRequest] 快速私有段检查失败后懒调用，避免拖慢热路径。
  /// 拉取失败（权限、平台不支持等）时返回空集合并记警告日志，调用方按
  /// 「接口匹配」不命中处理。
  Future<Set<String>> _getLocalInterfaceIps() async {
    final now = DateTime.now();
    final cached = _localInterfaceIps;
    final at = _localInterfaceIpsAt;
    if (cached != null && at != null && now.difference(at) < _localInterfaceIpsTtl) {
      return cached;
    }
    try {
      final list = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
      );
      final ips = <String>{};
      for (final iface in list) {
        for (final addr in iface.addresses) {
          ips.add(addr.address.toLowerCase());
        }
      }
      _localInterfaceIps = ips;
      _localInterfaceIpsAt = now;
      return ips;
    } catch (e) {
      appLogger.w('[VideoCacheProxy] 获取本机网卡地址失败', error: e);
      _localInterfaceIps = <String>{};
      _localInterfaceIpsAt = now;
      return _localInterfaceIps!;
    }
  }

  /// 判断客户端是否允许访问本地代理服务器（纯函数，可单测）。
  ///
  /// 放行规则（按顺序短路）：
  /// 1. [remoteIp] 为 loopback / RFC1918 / fe80 / ::1（[_isPrivateAddress] 等价判断）。
  /// 2. [remoteIp]（小写）命中 [localInterfaceIps]：TCP 握手能完成且源为本机接口，
  ///    必为自连流量。覆盖 iOS VPN/utun 分配公网段地址时 AVPlayer（mediaserverd）
  ///    通过公网源 IP 自连的场景。
  /// 3. [hostHeader] 归一化后指向 loopback（localhost / 127.* / ::1，可带端口、IPv6 括号）。
  ///
  /// 注意：Host 头可由客户端伪造，但本威胁模型本就允许任意 LAN 设备访问
  /// （投屏场景），且端口随机、手机通常在 NAT 后，风险可接受；日志留痕。
  ///
  /// 为可测试性设计为静态方法 + 显式参数注入；测试请使用
  /// `isAllowedClientForTest`（ForTest 后缀与项目内既有约定一致）。
  static bool isAllowedClientForTest(
    String remoteIp,
    String? hostHeader,
    Set<String> localInterfaceIps,
  ) {
    final remoteLower = remoteIp.toLowerCase();
    if (_isPrivateAddressString(remoteLower)) return true;
    if (localInterfaceIps.contains(remoteLower)) return true;
    if (_isLoopbackHost(hostHeader)) return true;
    return false;
  }

  /// 字符串形式的私有/局域网地址判定（与 [_isPrivateAddress] 逻辑对齐）。
  static bool _isPrivateAddressString(String ip) {
    if (ip == '::1') return true;
    if (ip.startsWith('fe80')) return true;
    if (ip == '127.0.0.1' || ip.startsWith('127.')) return true;
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]) ?? -1;
    final b = int.tryParse(parts[1]) ?? -1;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }

  /// 归一化 Host 头并判定是否指向 loopback。
  ///
  /// 处理：去端口（小写）、IPv6 括号形式 `[::1]:port`、`localhost` 大小写。
  static bool _isLoopbackHost(String? hostHeader) {
    if (hostHeader == null || hostHeader.isEmpty) return false;
    var h = hostHeader.toLowerCase();
    if (h.startsWith('[')) {
      final end = h.indexOf(']');
      if (end > 0) h = h.substring(1, end);
    } else {
      final colon = h.indexOf(':');
      if (colon > 0) h = h.substring(0, colon);
    }
    if (h == 'localhost' || h == '::1') return true;
    if (h.startsWith('127.')) return true;
    return false;
  }

  /// 放行判定结果，含放行原因（用于日志区分）。
  Future<_AllowResult> _checkExtendedAllowance(
    InternetAddress remoteAddress,
    String? hostHeader,
    String path,
  ) async {
    final remoteIp = remoteAddress.address.toLowerCase();

    final localIps = await _getLocalInterfaceIps();
    if (localIps.contains(remoteIp)) {
      return const _AllowResult._(true, AllowReason.interfaceMatch);
    }

    if (_isLoopbackHost(hostHeader)) {
      return const _AllowResult._(true, AllowReason.loopbackHost);
    }

    return const _AllowResult._(false, AllowReason.none);
  }

  /// 判断 URL 是否为 HLS m3u8 类型 — 仅匹配路径后缀，避免误判查询参数中的 .m3u8
  static bool _isHlsUrl(String url) {
    try {
      final path = Uri.parse(url).path.toLowerCase();
      return path.endsWith('.m3u8') || path.endsWith('.m3u8/');
    } catch (_) {
      return false; // URL 解析失败，不应假设为 HLS
    }
  }

  /// 通过 HEAD 请求嗅探 URL 的 Content-Type，判断是否为 HLS m3u8。
  ///
  /// 当 [_isHlsUrl] 路径检查无法确定时（如动态 URL 无 .m3u8 后缀），
  /// 可用此方法通过 HTTP HEAD 请求检查 Content-Type 做更准确的判断。
  ///
  /// 返回值：
  /// - true：Content-Type 包含 mpegurl 或 m3u8
  /// - false：Content-Type 不含 m3u8 标识，或 HEAD 请求失败
  static Future<bool> isHlsUrlWithProbe(String url, {Duration timeout = const Duration(seconds: 3)}) async {
    // 先做快速路径检查
    if (_isHlsUrl(url)) return true;

    // 路径不含 .m3u8 → HEAD 请求嗅探 Content-Type
    try {
      final client = HttpClient()..connectionTimeout = timeout;
      final req = await client.headUrl(Uri.parse(url));
      final resp = await req.close();
      await resp.drain<void>();
      client.close(force: true);

      final contentType = resp.headers.value('Content-Type') ?? '';
      return contentType.contains('mpegurl') || contentType.contains('m3u8');
    } catch (_) {
      return false; // 嗅探失败，保守返回 false
    }
  }

  /// 暂停所有活跃的代理缓存（退出播放页时调用）。
  ///
  /// 改为遍历 [_sessions]（全部 session），不再依赖 [_activeProxyKeys]：
  /// 旧实现按 _activeProxyKeys 匹配 session 不可靠，_handleHlsSegment 写入的
  /// 事务键 $cacheKey-segment-$i 永远匹配不到 _sessions，_handleProxy 的 finally
  /// 又会把 bare cacheKey 移除，导致退出时集合为空什么也停不了。
  ///
  /// [exceptKey] 非空时跳过该 cacheKey 的暂停（投屏中 TV 正在拉流，
  /// 保留当前投屏 session 继续预下载）。
  Future<void> pauseActiveProxying({String? exceptKey}) async {
    var pausedCount = 0;
    for (final entry in _sessions.entries.toList()) {
      final key = entry.key;
      if (exceptKey != null && key == exceptKey) {
        continue;
      }
      try {
        entry.value.pause();
        pausedCount++;
      } catch (e) {
        appLogger.e('[VideoCacheProxy] 暂停代理缓存失败: $key', error: e);
      }
    }
    // 清理 exceptKey 之外的瞬态事务键，避免遗留影响下次判定
    final staleKeys = _activeProxyKeys
        .where((k) => exceptKey == null || !(k == exceptKey || k.startsWith('$exceptKey-segment-')))
        .toList();
    for (final k in staleKeys) {
      _activeProxyKeys.remove(k);
    }
    appLogger.i(
        '[VideoCacheProxy] 已暂停所有活跃代理缓存: paused=$pausedCount, exceptKey=$exceptKey, clearedKeys=${staleKeys.length}');
  }

  /// 恢复指定 key 的代理缓存（进入播放页时调用）
  Future<void> resumeProxyCache(String cacheKey) async {
    if (!_activeProxyKeys.contains(cacheKey)) {
      _activeProxyKeys.add(cacheKey);
    }
    // 启动或恢复 Session
    final session = _sessions[cacheKey];
    if (session != null && session.state != SessionState.active) {
      session.start();
    }
    appLogger.i('[VideoCacheProxy] 已恢复代理缓存: $cacheKey');
  }

  /// 获取 URL 映射
  String? getUrl(String cacheKey) => _keyUrlMap[cacheKey];

  /// 注册 Session 创建完成回调。
  ///
  /// 由于 [register] 仅存储 URL 映射，[StreamSession] 在视频播放器首次请求
  /// `/hls/{cacheKey}` 时才异步创建。调用方可通过此回调在 Session 创建后
  /// 执行后续初始化（如清晰度管理器）。
  void onSessionCreated(String cacheKey, void Function(StreamSession) callback) {
    _onSessionCreatedCallbacks[cacheKey] = callback;
    // 如果 session 已存在，立即回调
    final existing = _sessions[cacheKey];
    if (existing != null) {
      callback(existing);
    }
  }

  /// 注销 Session 创建完成回调
  void removeSessionCreatedCallback(String cacheKey) {
    _onSessionCreatedCallbacks.remove(cacheKey);
  }

  /// 获取指定 cacheKey 的 StreamSession（可能为 null）
  StreamSession? getSession(String cacheKey) {
    return _sessions[cacheKey];
  }

  // ==================== 测试辅助（仅单测使用） ====================

  /// 注入测试用 session（仅供单元测试使用）。
  @visibleForTesting
  void injectSessionForTest(String cacheKey, StreamSession session) {
    _sessions[cacheKey] = session;
  }

  /// 清除所有测试注入的 session（仅供单元测试使用）。
  @visibleForTesting
  void clearSessionsForTest() {
    _sessions.clear();
    _activeProxyKeys.clear();
  }

  /// 读取当前活跃代理 key 集合（仅供单元测试使用）。
  @visibleForTesting
  Set<String> get activeProxyKeysForTest =>
      Set<String>.unmodifiable(_activeProxyKeys);

  /// 主动预创建 Session（投屏前调用），确保 m3u8 已解析、duration 可用。
  ///
  /// [StreamSession] 正常在视频播放器首次请求 `/hls/{cacheKey}` 时才异步创建，
  /// 投屏刚启动时 [getSession] 可能返回 null，导致 duration 兜底失效、
  /// 预热分片不执行。本方法在投屏前主动触发 m3u8 解析并创建 session，
  /// 让后续 [getSession] 调用能立即拿到可用的 session。
  ///
  /// 返回创建（或复用）的 session；URL 未注册或解析失败时返回 null。
  Future<StreamSession?> ensureSession(String cacheKey) async {
    final url = getUrl(cacheKey);
    if (url == null) return null;
    return await _getOrCreateSession(cacheKey, url);
  }

  // ==================== HTTP 请求处理 ====================

  /// 构造 proxyBaseUrl 用于重写 m3u8 分片 URL。
  ///
  /// 单服务器后统一使用请求自带的 Host + 实际端口：
  /// - 本地播放器：`Host: localhost:port` → 重写为 `localhost:port`
  /// - 投屏设备：`Host: 192.168.x.x:port` → 重写为 `192.168.x.x:port`
  ///
  /// 注意：mpv/FFmpeg 发送的 Host 头可能不含端口号（即使原始请求 URL 包含端口），
  /// 因此必须显式附加代理服务器的实际端口，否则重写后的 TS URL 缺少端口
  /// 会导致 mpv 回连端口 80 失败（Connection refused）。
  String _resolveProxyBaseUrl(HttpRequest request) {
    final hostHeader = request.headers.host;
    final localPort = request.connectionInfo?.localPort;
    final port = localPort ?? _port;
    if (hostHeader != null && hostHeader.isNotEmpty) {
      return hostHeader.contains(':')
          ? 'http://$hostHeader'
          : 'http://$hostHeader:$port';
    }
    return 'http://0.0.0.0:$port';
  }

  /// 处理 HTTP 请求 — 替代 shelf 的 _handleRequest
  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    appLogger.d('[VideoCacheProxy] ${request.method} ${request.uri}');

    // IP 过滤：服务器绑定 0.0.0.0 是为了让投屏设备能连进来，公网访问必须在入口处拒绝。
    // 放行规则（见 [_isPrivateAddress] / [isAllowedClientForTest]）：
    //   1) 源 IP 为 loopback / RFC1918 / fe80 / ::1（快速路径）。
    //   2) 源 IP 命中本机任一网卡地址 — 覆盖 iOS VPN/utun 公网段自连场景。
    //   3) Host 头指向 loopback（localhost / 127.* / ::1）— 兜底。
    final remoteAddress = request.connectionInfo?.remoteAddress;
    if (remoteAddress != null) {
      final _AllowResult allowed;
      if (_isPrivateAddress(remoteAddress)) {
        allowed = const _AllowResult._(true, AllowReason.privateRange);
      } else {
        allowed = await _checkExtendedAllowance(remoteAddress, request.headers.host, path);
      }
      if (!allowed.allowed) {
        appLogger.w('[VideoCacheProxy] 拒绝非局域网访问: $remoteAddress, path=$path');
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      if (allowed.reason != AllowReason.privateRange) {
        appLogger.i(
            '[VideoCacheProxy] 放行自连流量(${allowed.reason.name}): $remoteAddress, path=$path');
      }
    }

    try {
      // 路由: /proxy/{cacheKey} — MP4 直链
      if (path.startsWith('/proxy/')) {
        final cacheKey = path.substring('/proxy/'.length);
        await _handleProxy(request, cacheKey);
        return;
      }

      // 路由: /hls/{cacheKey} — m3u8 playlist
      if (path.startsWith('/hls/')) {
        final cacheKey = path.substring('/hls/'.length);
        await _handleHlsPlaylist(request, cacheKey);
        return;
      }

      // 路由: /hls-dlna/{cacheKey} — DLNA 投屏专用 m3u8（已废弃）
      // plan 1786714898308：代理层是透传密文，TV 端与读远程源一样自己拉 key 自己解密。
      // 因此本地播放器与 TV 统一使用 /hls/{cacheKey} 路由，无需再单独提供 /hls-dlna/。
      // 保留注释仅为提醒：旧 TV 缓存或第三方 m3u8 链接可能仍指向 /hls-dlna/，将落到下方 404。
      if (path.startsWith('/hls-dlna/')) {
        _sendNotFound(request, '/hls-dlna/ is deprecated, use /hls/');
        return;
      }

      // 路由: /hls-segment/{cacheKey}/{segIndex} — TS 分片
      if (path.startsWith('/hls-segment/')) {
        final remaining = path.substring('/hls-segment/'.length);
        final slashIdx = remaining.indexOf('/');
        if (slashIdx > 0) {
          final cacheKey = remaining.substring(0, slashIdx);
          final segIndexStr = remaining.substring(slashIdx + 1);
          final segIndex = int.tryParse(segIndexStr);
          if (segIndex != null) {
            await _handleHlsSegment(request, cacheKey, segIndex);
            return;
          }
        }
      }

      // 路由: /hls-key/{cacheKey} — HLS 加密密钥文件
      if (path.startsWith('/hls-key/')) {
        final cacheKey = path.substring('/hls-key/'.length);
        if (cacheKey.isNotEmpty) {
          await _handleHlsKey(request, cacheKey);
          return;
        }
      }

      // 未知路由
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Unknown path: $path')
        ..close();
    } catch (e, stackTrace) {
      appLogger.e('[VideoCacheProxy] 请求处理异常: $path', error: e, stackTrace: stackTrace);
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Internal server error')
          ..close();
      } catch (_) {
        // 响应已发送，忽略
      }
    }
  }

  // ==================== HLS Playlist 处理 ====================

  /// 处理 m3u8 playlist 请求
  Future<void> _handleHlsPlaylist(HttpRequest request, String cacheKey) async {
    final url = getUrl(cacheKey);
    if (url == null) {
      _sendNotFound(request, 'Unknown cache key: $cacheKey');
      return;
    }

    try {
      // 获取或创建 StreamSession
      final session = await _getOrCreateSession(cacheKey, url);
      if (session == null) {
        // Session 创建失败 — 可能是远程内容不是 m3u8 格式（如 MP4 直链）。
        // 降级为流式代理转发，确保非 HLS 内容也能正常播放。
        // 这在使用 hlsProxyUrl()（方案B 始终走 /hls/ 路由）时尤为重要：
        // 当原始 URL 实际是 MP4 时，m3u8 解析必然失败，需要降级处理。
        appLogger.w('[VideoCacheProxy] /hls/ Session 创建失败，降级为代理转发: $cacheKey, url=$url');
        await _handleProxy(request, cacheKey);
        return;
      }

      // 确保调度器在运行
      // 仅 created / idle 可自动重启：paused（退出播放页）不重启，
      // saving/expired/error 也不重启，避免在错误状态上继续下载。
      if (session.state == SessionState.created || session.state == SessionState.idle) {
        session.start();
      }

      // 构建代理服务器基础 URL（按请求来源端口选择 localhost/lan 端口，
      // 确保投屏设备拿到的分片 URL 指向其能访问的 lan server 端口）
      final proxyBaseUrl = _resolveProxyBaseUrl(request);

      // 使用完全重建的 m3u8（从解析数据重新生成，确保 HLS 标签完整）
      // 解决 Android 上 mpv/FFmpeg HLS demuxer 因标签缺失导致 PTS 重建错误、
      // 播放位置反复跳回开头的问题
      final rewrittenM3U8 = session.buildRewrittenM3U8(proxyBaseUrl, urlKey: cacheKey);

      // m3u8 playlist 不支持 Range 请求，强制返回完整内容（200 OK）。
      // 某些 DLNA 渲染器/libmpv 会发 Range: bytes=0-，若上游返回 206 会导致
      // dart_cast MediaProxy 的 m3u8 重写条件失败（要求 200），分片 URL 不被
      // 重写 → TV 请求原始相对路径 → 404。此处强制 200 规避该问题。
      request.response
        ..headers.contentType = ContentType('application', 'vnd.apple.mpegurl')
        ..headers.set('Cache-Control', 'no-cache, no-store')
        ..write(rewrittenM3U8)
        ..close();
    } catch (e) {
      appLogger.e('[VideoCacheProxy] m3u8 处理失败: $cacheKey', error: e);
      _sendError(request, 'Failed to process m3u8');
    }
  }

  // ==================== HLS Segment 处理 ====================

  /// 处理 TS 分片请求
  Future<void> _handleHlsSegment(HttpRequest request, String cacheKey, int segIndex) async {
    final url = getUrl(cacheKey);
    if (url == null) {
      appLogger.w('[VideoCacheProxy] Unknown cache key: $cacheKey, known keys: ${_keyUrlMap.keys.toList()}');
      _sendNotFound(request, 'Unknown cache key: $cacheKey');
      return;
    }

    final session = _sessions[cacheKey];
    if (session == null) {
      appLogger.w('[VideoCacheProxy] Session not found: $cacheKey, known sessions: ${_sessions.keys.toList()}');
      _sendNotFound(request, 'Session not found: $cacheKey');
      return;
    }

    final cacheManager = session.cacheManager;
    _activeProxyKeys.add('$cacheKey-segment-$segIndex');

    try {
      // 记录播放器实际请求的分片索引，用于即时 seek 检测
      // 相比依赖前端周期性进度上报，通过播放器实际请求行为能更早检测到 seek
      // recordSegmentRequest 内部会在检测到 seek 时通知调度器重排任务队列
      session.recordSegmentRequest(segIndex);

      // 如果分片还在 Pending/Failed 状态，通知调度器优先下载
      var status = cacheManager.getStatus(segIndex);
      if (status == SegmentStatus.pending || status == SegmentStatus.failed) {
        // 仅在 active 时才尝试让调度器下载：paused（退出播放页）不重启调度器，
        // 也不在 onDone 上空等 10s（调度器不在时 onDone 永不完成），直接落入后续
        // 缓存命中检查 → 未缓存则 _proxySegmentFromOrigin 透传。
        // 同样的重启门槛：仅 created / idle 可被请求处理器自动重启。
        if (session.state == SessionState.active) {
          session.notifyUrgentSegment(segIndex);

          // 等待分片下载完成（最多 10 秒），优先使用调度器下载的缓存数据。
          // 避免透传时因防盗链/UA 检查导致远程源返回非 TS 数据。
          appLogger.d('[VideoCacheProxy] 等待分片下载: segIndex=$segIndex, status=$status');
          try {
            final seg = cacheManager.getSegment(segIndex);
            if (seg != null && !seg.isDone) {
              await seg.onDone.timeout(const Duration(seconds: 10));
            }
          } on TimeoutException {
            appLogger.w('[VideoCacheProxy] 等待分片下载超时，尝试透传: segIndex=$segIndex');
          } catch (e) {
            appLogger.w('[VideoCacheProxy] 等待分片下载异常，尝试透传: segIndex=$segIndex', error: e);
          }
        } else if (session.state == SessionState.created || session.state == SessionState.idle) {
          // 调度器可能已停止（如 pauseActiveProxying 后被 resumeProxyCache / start 重启前），
          // 需要临时重启（与原行为一致，但状态门槛收紧）
          session.start();
        }
      }

      // 分片已缓存：直接返回缓存数据
      status = cacheManager.getStatus(segIndex);
      if (status == SegmentStatus.done) {
        final data = await cacheManager.getSegmentData(segIndex);
        if (data != null) {
          // 诊断日志：TS 分片应以 0x47 同步字节开头。
          // 若密钥错误导致解密后乱码，首字节不会是 0x47。
          appLogger.i('[VideoCacheProxy] 返回缓存分片: segIndex=$segIndex, bytes=${data.length}, '
              'hexPrefix=${_bytesToHex(data, 4)}');
          await _sendSegmentData(request, data);
          return;
        }
      }

      // 分片未缓存：反向代理透传到原始视频源 URL
      appLogger.d('[VideoCacheProxy] 透传分片: segIndex=$segIndex, status=$status');
      await _proxySegmentFromOrigin(request, session, segIndex);
    } catch (e) {
      appLogger.e('[VideoCacheProxy] TS 分片处理失败: $cacheKey-$segIndex', error: e);
      _sendError(request, 'Failed to process TS segment');
    } finally {
      _activeProxyKeys.remove('$cacheKey-segment-$segIndex');
    }
  }

  /// 发送分片数据，支持 Range 请求
  Future<void> _sendSegmentData(HttpRequest request, Uint8List data) async {
    final rangeHeader = request.headers.value('range');

    request.response.headers.set('Content-Type', 'video/mp2t');
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.headers.set('Accept-Ranges', 'bytes');

    if (rangeHeader == null) {
      // 无 Range 请求，返回完整数据
      request.response
        ..headers.contentLength = data.length
        ..add(data)
        ..close();
      return;
    }

    // 解析 Range: bytes=start-end
    final range = _parseRangeHeader(rangeHeader, data.length);
    if (range == null) {
      request.response
        ..headers.contentLength = data.length
        ..add(data)
        ..close();
      return;
    }

    final (start, end) = range;
    final bytesToRead = end - start + 1;

    request.response
      ..statusCode = HttpStatus.partialContent
      ..headers.contentLength = bytesToRead
      ..headers.set('Content-Range', 'bytes $start-$end/${data.length}')
      ..add(data.sublist(start, end + 1))
      ..close();
  }

  /// 反向代理透传到原始视频源 URL — 对应后端 proxySegmentFromOrigin
  /// 使用共享 HttpClient 复用 TCP 连接
  /// 透传时同时写入磁盘缓存，避免重复下载
  Future<void> _proxySegmentFromOrigin(HttpRequest request, StreamSession session, int segIndex) async {
    final m3u8Info = session.m3u8Info;
    if (segIndex >= m3u8Info.segments.length) {
      _sendError(request, 'Segment index out of range', HttpStatus.badRequest);
      return;
    }

    final segURL = m3u8Info.segments[segIndex].url;
    final cacheManager = session.cacheManager;

    // 检查分片是否正在被 Worker 下载或已完成，避免与 Worker 竞态写入
    final currentStatus = cacheManager.getStatus(segIndex);
    final shouldCache = currentStatus == SegmentStatus.pending ||
        currentStatus == SegmentStatus.failed;

    try {
      final client = remoteClient;

      final remoteReq = await client.getUrl(Uri.parse(segURL));

      // 透传 Range 头
      final rangeHeader = request.headers.value('range');
      if (rangeHeader != null) {
        remoteReq.headers.set('Range', rangeHeader);
      }

      // 转发防盗链关键头部：Referer 和 User-Agent
      // 很多视频源检查这些头部，缺失时返回 403 或重定向到错误页面
      final referer = request.headers.value('referer');
      if (referer != null) {
        remoteReq.headers.set('Referer', referer);
      } else {
        // fallback：使用 m3u8 URL 作为 Referer（视频源通常接受同源 Referer）
        remoteReq.headers.set('Referer', session.m3u8URL);
      }

      final ua = request.headers.value('user-agent');
      if (ua != null) {
        remoteReq.headers.set('User-Agent', ua);
      } else {
        remoteReq.headers.set('User-Agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      }

      final remoteResp = await remoteReq.close();

      appLogger.d('[VideoCacheProxy] 透传响应: segment=$segIndex, status=${remoteResp.statusCode}, '
          'contentType=${remoteResp.headers.value('Content-Type')}, '
          'contentLength=${remoteResp.headers.value('Content-Length')}');

      if (remoteResp.statusCode != HttpStatus.ok && remoteResp.statusCode != HttpStatus.partialContent) {
        appLogger.w('[VideoCacheProxy] 透传上游错误: segment=$segIndex, status=${remoteResp.statusCode}, url=$segURL');
        _sendError(request, 'Upstream error', remoteResp.statusCode);
        return;
      }

      // 设置响应头
      final contentType = remoteResp.headers.value('Content-Type');
      request.response.headers.contentType = contentType != null
          ? ContentType.parse(contentType)
          : ContentType('video', 'mp2t');

      final contentLength = remoteResp.headers.value('Content-Length');
      if (contentLength != null) {
        request.response.headers.contentLength = int.parse(contentLength);
      }

      final contentRange = remoteResp.headers.value('Content-Range');
      if (contentRange != null) {
        request.response.headers.set('Content-Range', contentRange);
      }

      request.response.headers.set('Accept-Ranges', 'bytes');
      request.response.headers.set('Cache-Control', 'no-cache');
      request.response.statusCode = remoteResp.statusCode;

      // 仅对完整请求（非 Range）且分片未被 Worker 下载时写入缓存
      // Range 请求只返回部分数据，不适合缓存整个分片
      final isFullRequest = rangeHeader == null;

      if (shouldCache && isFullRequest) {
        // 逐块读取：同时写入客户端响应和磁盘缓存
        final builder = BytesBuilder();
        await for (final chunk in remoteResp) {
          request.response.add(chunk);
          builder.add(chunk);
        }
        request.response.close();

        // 异步写入缓存（不阻塞响应）
        final data = Uint8List.fromList(builder.toBytes());
        _writeSegmentCache(cacheManager, segIndex, data);
      } else {
        // 不写缓存：直接流式转发
        await remoteResp.pipe(request.response);
      }
    } catch (e) {
      appLogger.e('[VideoCacheProxy] 反代透传失败: segment=$segIndex, url=$segURL', error: e);
      _sendError(request, 'Failed to proxy segment', HttpStatus.badGateway);
    }
  }

  /// 异步写入分片缓存（不阻塞响应，失败时静默处理）
  Future<void> _writeSegmentCache(
    SegmentCacheManager cacheManager,
    int segIndex,
    Uint8List data,
  ) async {
    try {
      // 再次检查状态，可能 Worker 已完成下载
      final status = cacheManager.getStatus(segIndex);
      if (status == SegmentStatus.done) {
        appLogger.d('[VideoCacheProxy] 透传缓存写入跳过：分片已完成: segIndex=$segIndex');
        return;
      }
      await cacheManager.markSegmentDone(segIndex, data);
      appLogger.d('[VideoCacheProxy] 透传缓存写入成功: segIndex=$segIndex, bytes=${data.length}');
    } catch (e) {
      // 缓存写入失败不影响播放，静默处理
      appLogger.w('[VideoCacheProxy] 透传缓存写入失败: segIndex=$segIndex', error: e);
    }
  }

  // ==================== HLS Key 处理 ====================

  /// 处理 AES-128 Key 请求
  Future<void> _handleHlsKey(HttpRequest request, String cacheKey) async {
    final session = _sessions[cacheKey];
    if (session == null) {
      _sendNotFound(request, 'Session not found: $cacheKey');
      return;
    }

    final keyURI = request.uri.queryParameters['keyuri'];
    if (keyURI == null || keyURI.isEmpty) {
      _sendError(request, 'keyuri is required', HttpStatus.badRequest);
      return;
    }

    // 1. 先从 session 缓存中查找（精确匹配 + 规范化匹配）
    var keyData = session.proxyKey(keyURI);

    // 2. 缓存未命中：尝试远程获取 key（降级方案）
    if (keyData == null) {
      appLogger.w('[VideoCacheProxy] 加密 key 缓存未命中，尝试远程获取: cacheKey=$cacheKey, keyURI=$keyURI');
      keyData = await session.fetchKeyRemotelyFetchKey(keyURI);
    }

    if (keyData == null) {
      appLogger.e('[VideoCacheProxy] 加密 key 获取失败（缓存+远程均失败）: cacheKey=$cacheKey, keyURI=$keyURI');
      _sendNotFound(request, 'Encryption key not found');
      return;
    }

    appLogger.i('[VideoCacheProxy] 返回加密 key: cacheKey=$cacheKey, keyURI=$keyURI, '
        'bytes=${keyData.length}, hex=${_bytesToHex(keyData, 8)}');
    request.response
      ..headers.contentType = ContentType('application', 'octet-stream')
      ..headers.set('Cache-Control', 'no-cache')
      ..headers.contentLength = keyData.length
      ..add(keyData)
      ..close();
  }

  // ==================== MP4 代理处理 ====================

  /// 处理 MP4 直链代理请求。
  ///
  /// 当远程响应的 Content-Type 为 m3u8 时，自动降级到 HLS 处理流程，
  /// 解决 `_isHlsUrl` 仅通过 URL 后缀判断导致非标准 m3u8 URL 误走 MP4 代理的问题。
  ///
  /// Range 预处理：将 mpv 发送的后缀范围 bytes=-N 转换为标准范围，
  /// 确保上游服务器（包括旧版后端）能正确响应。
  Future<void> _handleProxy(HttpRequest request, String cacheKey) async {
    final url = getUrl(cacheKey);
    if (url == null) {
      _sendNotFound(request, 'Unknown cache key: $cacheKey');
      return;
    }

    _currentRequest = request;
    _activeProxyKeys.add(cacheKey);

    try {
      final client = remoteClient;

      // ── Range 预处理 ──
      var rangeHeader = request.headers.value('range');
      String? originalRange; // 记录原始 Range 用于日志

      if (rangeHeader != null) {
        originalRange = rangeHeader;
        rangeHeader = await _preprocessRange(rangeHeader, url, client);
        if (rangeHeader == null) {
          // Range 格式异常，返回 400 让 mpv 重新请求
          appLogger.w('[Proxy/MP4] invalid Range header from mpv: $originalRange, returning 400');
          _sendError(request, 'Invalid Range header', HttpStatus.badRequest);
          return;
        }
        if (rangeHeader != originalRange) {
          appLogger.i('[Proxy/MP4] suffix range converted: $originalRange -> $rangeHeader');
        }
      }

      final remoteReq = await client.getUrl(Uri.parse(url));

      // 转发（可能已预处理的）Range 头
      if (rangeHeader != null) {
        remoteReq.headers.set('Range', rangeHeader);
      }

      // 转发防盗链头部
      final referer = request.headers.value('referer');
      if (referer != null) {
        remoteReq.headers.set('Referer', referer);
      }
      final ua = request.headers.value('user-agent');
      if (ua != null) {
        remoteReq.headers.set('User-Agent', ua);
      }

      final remoteResp = await remoteReq.close();

      // 检测远程响应是否为 m3u8 内容（Content-Type 或内容前缀检测）
      final contentTypeStr = remoteResp.headers.value('Content-Type') ?? '';
      final isM3u8ContentType = contentTypeStr.contains('mpegurl') || contentTypeStr.contains('m3u8');

      appLogger.i('[Proxy/MP4] response: cacheKey=$cacheKey, '
          'status=${remoteResp.statusCode}, contentType=$contentTypeStr, '
          'isM3u8=$isM3u8ContentType, '
          'originalRange=$originalRange, '
          'sentRange=$rangeHeader, '
          'upstreamContentRange=${remoteResp.headers.value("Content-Range")}');

      if (isM3u8ContentType && remoteResp.statusCode == HttpStatus.ok) {
        // m3u8 内容：降级到 HLS 处理流程
        appLogger.i('[VideoCacheProxy] 检测到 m3u8 内容，降级到 HLS 处理: $cacheKey');
        await _handleProxyAsHls(request, cacheKey, url, remoteResp);
        return;
      }

      // 非 m3u8 内容：正常 MP4 代理
      final totalBytes = remoteResp.contentLength > 0 ? remoteResp.contentLength : -1;

      // 设置响应头
      request.response.headers.contentType = contentTypeStr.isNotEmpty
          ? ContentType.parse(contentTypeStr)
          : ContentType.parse(_contentType(url));

      request.response.headers.set('Accept-Ranges', 'bytes');

      final contentRange = remoteResp.headers.value('Content-Range');
      if (contentRange != null) {
        request.response.headers.set('Content-Range', contentRange);
      }

      if (totalBytes > 0) {
        request.response.headers.contentLength = totalBytes;
      }

      request.response.statusCode = rangeHeader != null ? HttpStatus.partialContent : HttpStatus.ok;

      // 流式转发
      await remoteResp.pipe(request.response);
    } catch (e) {
      appLogger.e('[VideoCacheProxy] MP4 代理失败: $cacheKey', error: e);
      _sendError(request, 'Failed to proxy', HttpStatus.badGateway);
    } finally {
      _activeProxyKeys.remove(cacheKey);
      _currentRequest = null;
    }
  }

  /// 将 /proxy/ 请求降级为 HLS 处理。
  ///
  /// 当 `_handleProxy` 检测到远程响应为 m3u8 内容时调用。
  /// 读取远程响应的 m3u8 文本，创建 StreamSession，重写 m3u8 后返回给 mpv。
  Future<void> _handleProxyAsHls(
    HttpRequest request,
    String cacheKey,
    String m3u8URL,
    HttpClientResponse remoteResp,
  ) async {
    try {
      // 读取远程响应的 m3u8 内容
      final bytes = await _collectBytes(remoteResp);
      final m3u8Content = utf8.decode(bytes);

      // 额外验证：检查内容是否以 #EXTM3U 开头（m3u8 标识）
      final trimmed = m3u8Content.trim();
      if (!trimmed.startsWith('#EXTM3U')) {
        appLogger.w('[VideoCacheProxy] Content-Type 为 m3u8 但内容不以 #EXTM3U 开头，按普通内容处理');
        // 不符合 m3u8 格式，当作普通内容返回
        request.response
          ..headers.contentType = ContentType('application', 'vnd.apple.mpegurl')
          ..headers.set('Cache-Control', 'no-cache, no-store')
          ..headers.contentLength = bytes.length
          ..add(bytes)
          ..close();
        return;
      }

      // 获取或创建 StreamSession（传入已获取的 m3u8 内容，避免重复请求）
      final session = await _getOrCreateSession(cacheKey, m3u8URL, m3u8Content: m3u8Content);
      if (session == null) {
        // Session 创建失败，返回原始 m3u8 内容（兜底）
        appLogger.w('[VideoCacheProxy] HLS Session 创建失败，返回原始 m3u8: $cacheKey');
        request.response
          ..headers.contentType = ContentType('application', 'vnd.apple.mpegurl')
          ..headers.set('Cache-Control', 'no-cache, no-store')
          ..headers.contentLength = m3u8Content.length
          ..write(m3u8Content)
          ..close();
        return;
      }

      // 确保调度器在运行
      // 仅 created / idle 可自动重启：paused（退出播放页）不重启，
      // saving/expired/error 也不重启，避免在错误状态上继续下载。
      if (session.state == SessionState.created || session.state == SessionState.idle) {
        session.start();
      }

      // 构建代理服务器基础 URL（按请求来源端口选择 localhost/lan 端口）
      final proxyBaseUrl = _resolveProxyBaseUrl(request);

      // 使用完全重建的 m3u8（从解析数据重新生成，确保 HLS 标签完整）
      final rewrittenM3U8 = session.buildRewrittenM3U8(proxyBaseUrl, urlKey: cacheKey);

      appLogger.i('[VideoCacheProxy] HLS 降级成功，返回重写后 m3u8: $cacheKey, '
          'segments=${session.m3u8Info.segments.length}');

      request.response
        ..headers.contentType = ContentType('application', 'vnd.apple.mpegurl')
        ..headers.set('Cache-Control', 'no-cache, no-store')
        ..write(rewrittenM3U8)
        ..close();
    } catch (e) {
      appLogger.e('[VideoCacheProxy] HLS 降级处理失败: $cacheKey', error: e);
      _sendError(request, 'Failed to process HLS content');
    }
  }

  /// 收集 HttpClientResponse 的所有字节
  Future<Uint8List> _collectBytes(HttpClientResponse response) async {
    final builder = BytesBuilder();
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return Uint8List.fromList(builder.toBytes());
  }

  // ==================== Session 管理 ====================

  /// 获取或创建 StreamSession。
  ///
  /// [m3u8Content] 已获取的 m3u8 文本内容（可选），传入时避免重复请求远程源。
  Future<StreamSession?> _getOrCreateSession(String cacheKey, String m3u8URL, {String? m3u8Content}) async {
    // 已有 Session
    if (_sessions.containsKey(cacheKey)) {
      appLogger.i('[VideoCacheProxy] 复用已有 session: cacheKey=$cacheKey, '
          'keyCached=${_sessions[cacheKey]!.keyCacheCount}, '
          'state=${_sessions[cacheKey]!.state}');
      return _sessions[cacheKey];
    }
    appLogger.i('[VideoCacheProxy] 新建 session: cacheKey=$cacheKey, m3u8URL=$m3u8URL');

    try {
      _parser ??= M3u8Parser();

      // 获取分片存储目录
      final appDir = await getApplicationDocumentsDirectory();
      final segmentDir = '${appDir.path}/play_cache/stream/$cacheKey';

      // 创建 Session（传入已获取的 m3u8 内容，避免重复请求）
      final session = await StreamSession.create(
        m3u8URL: m3u8URL,
        parser: _parser!,
        segmentDir: segmentDir,
        m3u8Content: m3u8Content,
      );

      _sessions[cacheKey] = session;

      // 通知 Session 创建完成回调（如清晰度管理器初始化）
      _onSessionCreatedCallbacks[cacheKey]?.call(session);

      // 创建新 session 后，检查缓存是否超限，自动清理最早的缓存
      StreamCacheManager.instance.autoEvictIfNeeded().catchError((e) {
        appLogger.e('[VideoCacheProxy] 自动缓存清理失败', error: e);
        return 0;
      });

      return session;
    } catch (e) {
      appLogger.e('[VideoCacheProxy] 创建 StreamSession 失败: $cacheKey, url=$m3u8URL', error: e);
      return null;
    }
  }

  // ==================== 工具方法 ====================

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

  /// 解析 Range 请求头 - 对应后端 parseRange
  /// 使用 indexOf 只分割第一个 '-'，避免负号等字符干扰
  (int, int)? _parseRangeHeader(String rangeHeader, int fileSize) {
    final rangeSpec = rangeHeader.replaceFirst('bytes=', '');
    if (rangeSpec == rangeHeader) return null; // 没有替换成功

    final dashIdx = rangeSpec.indexOf('-');
    if (dashIdx < 0) return null;

    final startStr = rangeSpec.substring(0, dashIdx).trim();
    final endStr = rangeSpec.substring(dashIdx + 1).trim();

    int start, end;
    if (startStr.isEmpty) {
      start = 0;
    } else {
      start = int.tryParse(startStr) ?? (-1);
      if (start < 0 || start >= fileSize) return null;
    }

    if (endStr.isEmpty) {
      end = fileSize - 1;
    } else {
      end = int.tryParse(endStr) ?? (-1);
      if (end < start || end >= fileSize) return null;
    }

    return (start, end);
  }

  /// 预处理 Range 请求头，修正 mpv 发送的非标准格式。
  ///
  /// - 后缀范围 bytes=-N → 先 HEAD 获取 Content-Length，转换为 bytes=(CL-N)-(CL-1)
  /// - 格式异常 → 返回 null（调用方应返回 400）
  /// - 标准格式 → 原样返回
  Future<String?> _preprocessRange(String rangeHeader, String url, HttpClient client) async {
    final rangeSpec = rangeHeader.replaceFirst('bytes=', '');
    if (rangeSpec == rangeHeader) return null; // 没有 bytes= 前缀

    final dashIdx = rangeSpec.indexOf('-');
    if (dashIdx < 0) return null; // 没有 - 分隔符

    final startStr = rangeSpec.substring(0, dashIdx).trim();
    final endStr = rangeSpec.substring(dashIdx + 1).trim();

    // 后缀范围：bytes=-N（start 为空，end 非空）
    if (startStr.isEmpty && endStr.isNotEmpty) {
      final suffixLen = int.tryParse(endStr);
      if (suffixLen == null || suffixLen <= 0) return null;

      // HEAD 请求获取文件总大小
      try {
        final headReq = await client.headUrl(Uri.parse(url));
        // 转发防盗链头部
        final referer = _currentRequest?.headers.value('referer');
        if (referer != null) {
          headReq.headers.set('Referer', referer);
        }
        final ua = _currentRequest?.headers.value('user-agent');
        if (ua != null) {
          headReq.headers.set('User-Agent', ua);
        }
        final headResp = await headReq.close();
        // 消费响应体
        await headResp.drain<void>();

        final contentLength = headResp.contentLength;
        if (contentLength <= 0) {
          appLogger.w('[Proxy/MP4] HEAD request returned no Content-Length for suffix range: $url');
          return rangeHeader; // 无法转换，原样返回
        }

        final start = contentLength - suffixLen;
        if (start < 0) {
          return 'bytes=0-${contentLength - 1}'; // 后缀长度超过文件大小，从头开始
        }
        return 'bytes=$start-${contentLength - 1}';
      } catch (e) {
        appLogger.w('[Proxy/MP4] HEAD request failed for suffix range conversion: $e');
        return rangeHeader; // HEAD 失败，原样返回
      }
    }

    // 标准范围：bytes=start-end 或 bytes=start-
    if (startStr.isNotEmpty) {
      final start = int.tryParse(startStr);
      if (start == null || start < 0) return null; // start 格式异常
    }
    if (endStr.isNotEmpty) {
      final end = int.tryParse(endStr);
      if (end == null || end < 0) return null; // end 格式异常
    }

    // 标准格式，原样返回
    return rangeHeader;
  }

  /// 推断 Content-Type
  String _contentType(String url) {
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('.mp4')) return 'video/mp4';
    if (lowerUrl.contains('.webm')) return 'video/webm';
    if (lowerUrl.contains('.mkv')) return 'video/x-matroska';
    if (lowerUrl.contains('.m3u8')) return 'application/vnd.apple.mpegurl';
    if (lowerUrl.contains('.ts')) return 'video/MP2T';
    if (lowerUrl.contains('.m4v')) return 'video/x-m4v';
    return 'application/octet-stream';
  }

  /// 发送 404 响应
  void _sendNotFound(HttpRequest request, String message) {
    request.response
      ..statusCode = HttpStatus.notFound
      ..write(message)
      ..close();
  }

  /// 发送错误响应
  void _sendError(HttpRequest request, String message, [int statusCode = HttpStatus.internalServerError]) {
    request.response
      ..statusCode = statusCode
      ..write(message)
      ..close();
  }
}

/// 放行来源枚举 — 用于 [_handleRequest] 日志区分命中哪条规则。
///
/// `privateRange` 对应快速路径 [_isPrivateAddress]，不打印单独放行日志；
/// `interfaceMatch` / `loopbackHost` 为新增扩展放行规则。
enum AllowReason {
  none,
  privateRange,
  interfaceMatch,
  loopbackHost,
}

class _AllowResult {
  const _AllowResult._(this.allowed, this.reason);
  final bool allowed;
  final AllowReason reason;
}
