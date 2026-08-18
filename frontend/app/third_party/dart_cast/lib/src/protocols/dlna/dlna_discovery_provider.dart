import 'dart:async';
import 'dart:io';

import '../../core/cast_device.dart';
import '../../core/discovery_provider.dart';
import '../../utils/logger.dart';
import '../../utils/network_utils.dart';
import 'dlna_device.dart';
import 'ssdp_discovery.dart';

/// Function type for creating a UDP socket for SSDP discovery.
typedef RawDatagramSocketFactory =
    Future<RawDatagramSocket> Function(dynamic host, int port);

/// Function type for fetching a URL and returning its body.
typedef HttpFetcher = Future<String> Function(String url);

/// Discovers DLNA (UPnP) media renderers via SSDP M-SEARCH.
///
/// Sends multicast M-SEARCH queries for AVTransport and MediaRenderer
/// services, parses responses, fetches device description XML, and
/// emits [CastDevice] lists as devices are found.
class DlnaDiscoveryProvider implements DeviceDiscoveryProvider {
  final RawDatagramSocketFactory _socketFactory;
  final HttpFetcher _httpFetcher;

  RawDatagramSocket? _socket;
  StreamController<List<CastDevice>>? _controller;
  Timer? _searchTimer;
  final Map<String, CastDevice> _devices = {};

  /// Creates a [DlnaDiscoveryProvider].
  ///
  /// Optional [socketFactory] and [httpFetcher] can be provided for testing.
  DlnaDiscoveryProvider({
    RawDatagramSocketFactory? socketFactory,
    HttpFetcher? httpFetcher,
  }) : _socketFactory = socketFactory ?? RawDatagramSocket.bind,
       _httpFetcher = httpFetcher ?? _defaultHttpFetch;

  @override
  CastProtocol get protocol => CastProtocol.dlna;

  @override
  Stream<List<CastDevice>> startDiscovery({
    Duration timeout = const Duration(seconds: 10),
  }) {
    stopDiscovery();
    _devices.clear();
    _controller = StreamController<List<CastDevice>>();

    _doDiscovery(timeout);

    return _controller!.stream;
  }

  Future<void> _doDiscovery(Duration timeout) async {
    try {
      CastLogger.info('DLNA: binding UDP socket for SSDP discovery');
      // iOS 14+ Local Network Privacy：尽量绑具体接口 IPv4（命中用户实际
      // WiFi / 网卡），避免 wildcard socket 在未授权时直抛 EHOSTUNREACH。
      // 若枚举失败（罕见：无 LAN 接口、纯 VPN）回退 anyIPv4 保留原行为。
      final localIp = await NetworkUtils.getLocalIpAddress();
      final bindAddress =
          localIp != null ? InternetAddress(localIp) : InternetAddress.anyIPv4;
      CastLogger.debug(
        'DLNA: binding socket to ${bindAddress.address} (localIp=$localIp)',
      );
      _socket = await _socketFactory(bindAddress, 0);
      final socket = _socket!;
      socket.broadcastEnabled = true;
      socket.multicastLoopback = false;

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            _handleResponse(String.fromCharCodes(datagram.data));
          }
        }
      });

      // Send M-SEARCH for MediaRenderer
      final searchTarget = SsdpConstants.searchTargets[2]; // MediaRenderer
      final mSearch = SsdpMessage.mSearch(searchTarget, 3);
      final data = mSearch.codeUnits;
      final address = InternetAddress(SsdpConstants.multicastAddress);

      CastLogger.info(
        'DLNA: sending M-SEARCH to ${SsdpConstants.multicastAddress}:${SsdpConstants.multicastPort}',
      );
      // 首发送：用局部变量而非 `_socket!`，避免异常路径上 `_socket` 被
      // 同时改写产生竞态。`SocketException`（iOS EHOSTUNREACH / 用户拒绝
      // 本地网络授权）一律吞掉 —— 授权可能在几秒后才被用户点确认，让
      // 探针继续 `listen` 收包；上层 mDNS 路径上 LocalNetworkProbe 已
      // 触发过系统弹窗，正常用户已经授权。
      //
      // 但同时记录结果：若两次发送全部失败（最典型场景：iOS 缺
      // `com.apple.developer.networking.multicast` entitlement，send 静默
      // 被内核拦截），timeout 时把最后一次错误 `addError` 上抛给
      // MeowCastService，让 cast_panel 的"iOS 设置 → 本地网络"提示
      // 能正确显示。否则"零设备 + 无错结束"无法区分"真无设备"与
      // "组播被拦截"，UI 永远不给引导。
      var sendSucceeded = false;
      Object? sendError;

      try {
        socket.send(data, address, SsdpConstants.multicastPort);
        sendSucceeded = true;
      } catch (e) {
        sendError = e;
        CastLogger.warning(
          'DLNA: initial M-SEARCH send failed (likely Local Network not yet granted): $e',
        );
      }

      // Send again after a short delay for reliability
      _searchTimer = Timer(const Duration(milliseconds: 500), () {
        try {
          socket.send(data, address, SsdpConstants.multicastPort);
          sendSucceeded = true;
        } catch (e) {
          sendError = e;
          CastLogger.warning('DLNA: retry M-SEARCH send failed: $e');
        }
      });

      // Close after timeout
      Timer(timeout, () {
        CastLogger.info('DLNA: discovery timeout reached, closing');
        if (!sendSucceeded && sendError != null) {
          // 两次 M-SEARCH 发送全部失败 —— 多半是 iOS 缺 multicast
          // entitlement 或本地网络授权被拒。上抛给上层 cast_service 的
          // onError 钩子，触发 `_lastDiscoveryAllFailed = true`，
          // cast_panel 据此展示设置入口提示。
          _controller?.addError(
            StateError(
              'DLNA M-SEARCH send failed twice (likely iOS multicast '
              'entitlement or Local Network permission missing): '
              '$sendError',
            ),
          );
        } else if (!sendSucceeded) {
          // send() 未抛错但也未记录成功 —— 极少见，留 warning 便于排查。
          CastLogger.warning(
            'DLNA: M-SEARCH did not succeed; multicast may be silently blocked',
          );
        }
        _controller?.close();
      });
    } catch (e) {
      CastLogger.error('DLNA: discovery failed: $e');
      _controller?.addError(e);
      _controller?.close();
    }
  }

  void _handleResponse(String data) async {
    final response = SsdpMessage.parseResponse(data);
    final location = response.location;
    if (location == null) return;

    final uuid = SsdpMessage.extractUuid(response.usn);
    if (uuid == null) return;

    // Skip if we already have this device
    if (_devices.containsKey(uuid)) return;

    CastLogger.debug(
      'DLNA: SSDP response from $uuid, fetching description at $location',
    );

    try {
      final xml = await _httpFetcher(location);
      final description = DlnaDeviceDescription.parse(xml, location);
      final device = description.toCastDevice();
      CastLogger.info(
        'DLNA: found device "${device.name}" at ${device.address.address}:${device.port}',
      );
      _devices[uuid] = device;

      if (_controller?.isClosed == false) {
        _controller!.add(_devices.values.toList());
      }
    } catch (e) {
      CastLogger.warning(
        'DLNA: failed to fetch description for $uuid at $location: $e',
      );
    }
  }

  @override
  void stopDiscovery() {
    _searchTimer?.cancel();
    _searchTimer = null;
    _socket?.close();
    _socket = null;
    if (_controller?.isClosed == false) {
      _controller?.close();
    }
    _controller = null;
  }

  @override
  void dispose() {
    stopDiscovery();
  }

  static Future<String> _defaultHttpFetch(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final body =
          await response.transform(const SystemEncoding().decoder).join();
      return body;
    } finally {
      client.close();
    }
  }
}
