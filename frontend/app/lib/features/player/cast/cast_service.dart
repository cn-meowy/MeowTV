import 'dart:async';
import 'dart:io' show Platform;
import 'package:dart_cast/dart_cast.dart';
import '../../../core/logger/app_logger.dart';

/// 用户主动断开 / 切换设备时取消 in-flight loadMedia 的内部信号。
///
/// [MeowCastService.connectAndPlay] 在 `await _activeSession!.loadMedia(media)`
/// 期间会被 dart_cast 的 SETUP / play 阻塞（30s+）。如果用户在阻塞期间点击
/// "断开投屏"，必须立刻取消等待，否则：
///   - playV2 SETUP 超时后回退链（playHapV1 / playV1 / playV1Text）在已断开
///     的 socket 上仍可能跑完并返回 false-200
///   - loadMedia "成功"返回 → cast_service 打印"媒体加载成功" → 上层误判为
///     "投屏已启动"，UI 卡在 cast overlay 中无法退出
///
/// 修复：disconnect() 调用时 complete 这个 completer，loadMedia 路径立刻抛
/// [CastCancelledException]，catch 块走"曾连接 → 广播 disconnected"分支。
/// 实现细节见 plan 1786547299978 P1。
class CastCancelledException implements Exception {
  const CastCancelledException(this.message);
  final String message;
  @override
  String toString() => 'CastCancelledException: $message';
}

/// 投屏服务封装：设备发现、连接、播放控制、断开
class MeowCastService {
  final CastService _service = CastService(
    discoveryProviders: [
      ChromecastDiscoveryProvider(),
      DlnaDiscoveryProvider(),
      if (Platform.isIOS || Platform.isMacOS) AirPlayDiscoveryProvider(),
    ],
    sessionFactory: (device) {
      switch (device.protocol) {
        case CastProtocol.chromecast:
          return ChromecastSession(device: device);
        case CastProtocol.airplay:
          return AirPlaySession(device);
        case CastProtocol.dlna:
          return _buildDlnaSession(device);
      }
    },
  );
  CastSession? _activeSession;
  CastDevice? _connectedDevice;

  final _stateController = StreamController<CastState>.broadcast();
  final _devicesController = StreamController<List<CastDevice>>.broadcast();

  // ─── 中转流：在 MeowCastService 层稳定暴露远端进度/时长/音量 ──────────────
  // CastSession 仅在 connect 后存在，重建 session 会让上层订阅失效。
  // 这里用中转 StreamController：connectAndPlay 成功后订阅 session 流并转发，
  // disconnect 时 emit Duration.zero 并取消订阅，保证上层订阅稳定不断流。
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _volumeController = StreamController<double>.broadcast();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<double>? _volSub;
  StreamSubscription<SessionState>? _sessionStateSub;

  Duration _castPosition = Duration.zero;
  Duration _castDuration = Duration.zero;

  /// 本次 connectAndPlay 是否曾成功建立过会话。
  /// 用于区分「连接/加载失败」（false）与「设备意外断线」（true）：
  /// 失败时不应广播 disconnected，以免触发"意外断线回退到 0:00:00"。
  bool _hasEverConnected = false;

  /// 取消 in-flight `loadMedia` 的信号。
  ///
  /// 在 [connectAndPlay] 入口创建，仅供本次调用使用；disconnect()
  /// 触发时 complete 它，让 `await _activeSession!.loadMedia(media)`
  /// 立刻抛 [CastCancelledException] 而不再被 dart_cast 阻塞 30s。
  /// plan 1786547299978 P1。
  Completer<void>? _loadMediaCanceller;

  /// 最近一次发现是否所有 provider 都报错过（无任何设备被发现）。
  ///
  /// iOS 14+ 上最常见原因是用户尚未授予"本地网络"权限，三路探针（DLNA /
  /// Chromecast / AirPlay）都会因 `SocketException(EHOSTUNREACH)` 走
  /// onError 路径，最终设备列表为空。
  ///
  /// [cast_panel] 读取本字段，决定"未发现设备"分支是否展示 iOS 设置 hint。
  /// 必须在 [stopDiscovery] 中复位，否则用户授权后再点投屏仍显示旧提示。
  bool _lastDiscoveryAllFailed = false;

  /// 最近一次发现是否所有 provider 都报错过。供 UI 层判断是否提示
  /// iOS"本地网络"权限问题。
  bool get lastDiscoveryAllFailed => _lastDiscoveryAllFailed;

  /// 当前投屏状态
  Stream<CastState> get stateStream => _stateController.stream;
  CastState _state = CastState.disconnected;
  CastState get state => _state;

  /// 发现的设备列表
  Stream<List<CastDevice>> get devicesStream => _devicesController.stream;
  List<CastDevice> _devices = [];
  List<CastDevice> get devices => List.unmodifiable(_devices);

  /// 已连接的设备
  CastDevice? get connectedDevice => _connectedDevice;

  /// 远端播放进度流（中转，稳定不断流）
  Stream<Duration> get positionStream => _positionController.stream;

  /// 远端媒体时长流（中转，稳定不断流）
  Stream<Duration> get durationStream => _durationController.stream;

  /// 远端音量流（中转，稳定不断流）
  Stream<double> get volumeStream => _volumeController.stream;

  /// 当前远端播放进度（最新值）
  Duration get castPosition => _castPosition;

  /// 当前远端媒体时长（最新值）
  Duration get castDuration => _castDuration;

  /// 把外部进度注入到中转 position 流，同时更新 [_castPosition]。
  ///
  /// 仅供 [MeowCastService] 之外的代码使用：例如投屏加载超时兜底时，
  /// PlayerScreen 在断开远端前把本地断点注入到这里，让 `_listenCastState`
  /// 的 disconnected 恢复分支拿到正确的断点（远端从未真正播放时
  /// `castPosition` 仍为 0）。
  void injectCastPosition(Duration position) {
    _castPosition = position;
    if (!_positionController.isClosed) {
      _positionController.add(position);
    }
  }

  /// 是否正在投屏（playing/paused/buffering/loading/connected 均视为投屏中）
  bool get isCasting {
    final s = _state;
    return s == CastState.playing ||
        s == CastState.paused ||
        s == CastState.buffering ||
        s == CastState.loading ||
        s == CastState.connected;
  }

  void _updateState(CastState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }

  /// 统一设备标签：[id=..., name=..., addr=ip:port, proto=...]。
  ///
  /// 每个 CastDevice 在日志中需要可唯一识别的标签。`id` 可能为空字符串
  /// （mDNS TXT 缺失场景），必须显式标注；地址+端口+协议组合能区分
  /// 「同一 TV 的多次发现」。所有 [Cast] 域日志统一使用此格式输出设备上下文。
  String _deviceTag(CastDevice d) =>
      '[id=${d.id.isEmpty ? "<empty>" : d.id}, '
      'name=${d.name}, '
      'addr=${d.address.address}:${d.port}, '
      'proto=${d.protocol.name}]';

  /// 取消 session 流订阅（disconnect / 重连前调用）
  void _cancelSessionSubscriptions() {
    _posSub?.cancel();
    _durSub?.cancel();
    _volSub?.cancel();
    _sessionStateSub?.cancel();
    _posSub = null;
    _durSub = null;
    _volSub = null;
    _sessionStateSub = null;
  }

  /// 订阅当前 session 的进度/时长/音量流并转发到中转流
  void _subscribeSessionStreams() {
    final session = _activeSession;
    if (session == null) return;
    _posSub = session.positionStream.listen((pos) {
      _castPosition = pos;
      _positionController.add(pos);
    });
    _durSub = session.durationStream.listen((dur) {
      _castDuration = dur;
      _durationController.add(dur);
    });
    _volSub = session.volumeStream.listen((vol) {
      _volumeController.add(vol);
    });
  }

  /// 开始设备发现
  Future<void> startDiscovery({Duration timeout = const Duration(seconds: 10)}) async {
    appLogger.i('[Cast] startDiscovery 开始 (timeout=${timeout.inSeconds}s)');
    _devices = [];
    _lastDiscoveryAllFailed = false;
    _devicesController.add(_devices);
    appLogger.d('[Cast] discovery reset: emit 空列表');
    _updateState(CastState.discovering);

    var anyError = false;

    try {
      _service.startDiscovery(timeout: timeout).listen(
        (deviceList) {
          appLogger.d(
              '[Cast] raw emit: count=${deviceList.length}, '
              'devices=${deviceList.map(_deviceTag).join(' | ')}');
          _devices = deviceList;
          _devicesController.add(_devices);
          appLogger.i('[Cast] 发现 ${deviceList.length} 个设备（去重前）');
        },
        onDone: () {
          if (_state == CastState.discovering) {
            _updateState(CastState.disconnected);
          }
          // 发现流正常结束：若全程无设备且出现过错误，最可能就是 iOS 未授权
          // 本地网络。cast_panel 据此展示 hint 文案。
          if (_devices.isEmpty && anyError) {
            _lastDiscoveryAllFailed = true;
            appLogger.w(
              '[Cast] 发现完全失败（无设备 + 全程出错），'
              '最可能原因：iOS 未授权本地网络',
            );
          }
          appLogger.i(
            '[Cast] 设备发现结束，最终列表: count=${_devices.length}, '
            'anyError=$anyError, allFailed=$_lastDiscoveryAllFailed',
          );
        },
        onError: (e, st) {
          anyError = true;
          appLogger.e('[Cast] 设备发现流错误', error: e, stackTrace: st);
          _updateState(CastState.disconnected);
        },
      );
    } catch (e, st) {
      anyError = true;
      appLogger.e('[Cast] 启动设备发现失败', error: e, stackTrace: st);
      _updateState(CastState.disconnected);
    }
  }

  /// 停止设备发现
  void stopDiscovery() {
    _service.stopDiscovery();
    // 复位"上次完全失败"标记：用户授权后再次投屏应回到正常提示路径，
    // 否则 hint 文案会一直挂着误导用户。
    _lastDiscoveryAllFailed = false;
  }

  /// 内部清理：断开旧 session 并释放资源，不广播 disconnected 状态。
  /// 用于 connectAndPlay 切换设备前的静默清理。
  Future<void> _cleanupActiveSession() async {
    // P1：切换设备时旧会话可能还在 in-flight loadMedia，需要取消。
    final canceller = _loadMediaCanceller;
    if (canceller != null && !canceller.isCompleted) {
      appLogger.d('[Cast] cleanup: 取消旧会话的 in-flight loadMedia');
      canceller.complete();
    }
    _loadMediaCanceller = null;

    final session = _activeSession;
    if (session == null) return;
    appLogger.d('[Cast] cleanup old session: prev=${session.runtimeType}');
    // 先取消所有订阅（含 stateStream），防止 disconnect 触发的
    // SessionState.disconnected 回调到监听器引发状态广播
    _cancelSessionSubscriptions();
    try {
      await session.disconnect();
    } catch (e, st) {
      appLogger.e('[Cast] 清理旧会话失败', error: e, stackTrace: st);
    }
    _castPosition = Duration.zero;
    _castDuration = Duration.zero;
    _hasEverConnected = false;
    _positionController.add(Duration.zero);
    _durationController.add(Duration.zero);
    _activeSession = null;
    _connectedDevice = null;
  }

  /// 连接到设备并开始投屏
  Future<void> connectAndPlay(CastDevice device, CastMedia media) async {
    appLogger.i('[Cast] connectAndPlay 入口 ${_deviceTag(device)}');
    _updateState(CastState.connecting);

    try {
      // 静默清理旧连接（不广播 disconnected）
      await _cleanupActiveSession();

      // DLNA 设备 metadata 完整性校验：dart_cast 的 DlnaSession.fromDevice 在
      // metadata 缺少 avTransportControlUrl 时会抛裸 ArgumentError。此处提前校验，
      // 给出带设备名的友好错误信息，让 catch 块走"投屏失败"提示路径。
      if (device.protocol == CastProtocol.dlna) {
        final avTransportUrl = device.metadata['avTransportControlUrl'];
        if (avTransportUrl == null || avTransportUrl.isEmpty) {
          appLogger.w(
              '[Cast] DLNA metadata 校验失败: avTransportControlUrl=$avTransportUrl ${_deviceTag(device)}');
          throw CastException(
            '设备 "${device.name}" 的 DLNA 描述信息不完整（缺少 AVTransport 控制地址）。'
            '该设备可能不兼容 DLNA 投屏，请尝试 AirPlay 协议。',
          );
        }
      }

      // AirPlayDiscoveryProvider 已注册到 discoveryProviders，用于检测网络中
      // 是否存在 AirPlay 设备（驱动投屏面板中 AirPlay 按钮的显隐与计数）。
      // 实际 AirPlay 投屏仍走原生 iOS/macOS AVRoutePickerView，不通过此分支连接。
      _activeSession = await _service.connect(device);
      _connectedDevice = device;
      // 标记已成功建立会话：此后任何异常都视为「意外断线」而非「连接失败」。
      // 必须在订阅 stateStream 之前置位，否则 disconnected 回调可能与 catch 块竞态。
      _hasEverConnected = true;
      _updateState(CastState.connected);

      // 订阅远端进度/时长/音量流（转发到中转流）
      _subscribeSessionStreams();

      // 监听会话状态
      _sessionStateSub = _activeSession!.stateStream.listen((sessionState) {
        switch (sessionState) {
          case SessionState.playing:
            _updateState(CastState.playing);
            break;
          case SessionState.paused:
            _updateState(CastState.paused);
            break;
          case SessionState.buffering:
            _updateState(CastState.buffering);
            break;
          case SessionState.idle:
            _updateState(CastState.connected);
            break;
          case SessionState.disconnected:
            _cancelSessionSubscriptions();
            _castPosition = Duration.zero;
            _castDuration = Duration.zero;
            _positionController.add(Duration.zero);
            _durationController.add(Duration.zero);
            _hasEverConnected = false;
            _updateState(CastState.disconnected);
            _activeSession = null;
            _connectedDevice = null;
            // 100ms 后二次 emit Duration.zero，保证下游 UI（进度条/overlay）
            // 一定收到归零信号。仅在期间未发起新会话时触发，避免干扰新投屏。
            Future.delayed(const Duration(milliseconds: 100), () {
              if (_activeSession == null && !_positionController.isClosed) {
                _positionController.add(Duration.zero);
              }
            });
            break;
          default:
            break;
        }
      });

      // 加载媒体
      _updateState(CastState.loading);
      // P1：创建本次 loadMedia 的 canceller；disconnect() 会通过它取消等待。
      // 使用 Future.any 而非 cancel——dart_cast 的内部 socket 等待不可中断，
      // 但可以让 cast_service 不再被它阻塞。
      final canceller = _loadMediaCanceller = Completer<void>();
      try {
        await Future.wait([
          _activeSession!.loadMedia(media),
          canceller.future.then((_) {
            throw const CastCancelledException('loadMedia 被断开取消');
          }),
        ]);
        appLogger.i('[Cast] 媒体加载成功: ${media.url}, type=${media.type.name}');
      } finally {
        // 清理本次调用的 canceller 引用，避免影响下一次 connectAndPlay。
        if (identical(_loadMediaCanceller, canceller)) {
          _loadMediaCanceller = null;
        }
      }
    } catch (e, st) {
      // P1：loadMedia 被断开取消是预期路径。
      if (e is CastCancelledException) {
        appLogger.i('[Cast] loadMedia 被断开取消（用户主动断开或切换设备） ${_deviceTag(device)}');
      } else {
        appLogger.e('[Cast] 连接/播放失败 ${_deviceTag(device)} '
            '(metadataKeys=${device.metadata.keys.toList()})',
            error: e, stackTrace: st);
      }
      _cancelSessionSubscriptions();
      final hadConnected = _hasEverConnected;
      _activeSession = null;
      _connectedDevice = null;
      _hasEverConnected = false;
      if (hadConnected) {
        // 曾成功连接后失败 → 视为意外断线，广播 disconnected 让上层走断点回退
        appLogger.w(
            '[Cast] 已连接后失败,广播 disconnected: errorType=${e.runtimeType} ${_deviceTag(device)}');
        _updateState(CastState.disconnected);
      } else {
        // 从未连接成功 → 静默清理，不广播 disconnected。
        // 避免上层 _listenCastState 误判为"意外断线"而用 castPosition=0 覆盖本地断点。
        // 同步内部状态字段（不通过 _updateState 广播）。
        _state = CastState.disconnected;
        appLogger.i(
            '[Cast] 连接失败，未广播 disconnected: errorType=${e.runtimeType}, msg=${e.toString()} ${_deviceTag(device)}');
      }
    }
  }

  /// 切集续投：复用已连接 session 加载新媒体，避免重连
  ///
  /// 仅在已连接设备时有效；未连接时为 no-op。
  Future<void> loadMedia(CastMedia media) async {
    final session = _activeSession;
    if (session == null) {
      appLogger.w('[Cast] loadMedia 失败：无活跃会话');
      return;
    }
    _updateState(CastState.loading);
    try {
      await session.loadMedia(media);
      appLogger.i('[Cast] 切集续投加载成功: ${media.url}, type=${media.type.name}');
    } catch (e, st) {
      appLogger.e('[Cast] 切集续投加载失败', error: e, stackTrace: st);
    }
  }

  /// 暂停
  Future<void> pause() async {
    try {
      await _activeSession?.pause();
    } catch (e, st) {
      appLogger.e('[Cast] 暂停失败', error: e, stackTrace: st);
    }
  }

  /// 恢复播放
  Future<void> play() async {
    try {
      await _activeSession?.play();
    } catch (e, st) {
      appLogger.e('[Cast] 播放失败', error: e, stackTrace: st);
    }
  }

  /// 跳转
  Future<void> seek(Duration position) async {
    try {
      await _activeSession?.seek(position);
    } catch (e, st) {
      appLogger.e('[Cast] 跳转失败', error: e, stackTrace: st);
    }
  }

  /// 设置音量（0.0-1.0）
  Future<void> setVolume(double volume) async {
    try {
      await _activeSession?.setVolume(volume);
    } catch (e, st) {
      appLogger.e('[Cast] 设置音量失败', error: e, stackTrace: st);
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    // P1：取消可能仍在阻塞的 loadMedia 等待，避免回退链在已断开 socket 上
    // 跑完后误报"投屏已启动"。plan 1786547299978。
    final canceller = _loadMediaCanceller;
    if (canceller != null && !canceller.isCompleted) {
      appLogger.d('[Cast] disconnect: 触发 loadMedia 取消信号');
      canceller.complete();
    }
    _loadMediaCanceller = null;

    if (_activeSession != null) {
      try {
        await _activeSession!.disconnect();
      } catch (e, st) {
        appLogger.e('[Cast] 断开连接失败', error: e, stackTrace: st);
      }
      _cancelSessionSubscriptions();
      _castPosition = Duration.zero;
      _castDuration = Duration.zero;
      _positionController.add(Duration.zero);
      _durationController.add(Duration.zero);
      _activeSession = null;
      _connectedDevice = null;
    }
    _updateState(CastState.disconnected);
  }

  /// 释放资源
  void dispose() {
    stopDiscovery();
    disconnect();
    _stateController.close();
    _devicesController.close();
    _positionController.close();
    _durationController.close();
    _volumeController.close();
  }
}

/// 投屏状态
enum CastState {
  disconnected,
  discovering,
  connecting,
  connected,
  loading,
  playing,
  paused,
  buffering,
}

/// DLNA 直传 [MediaTransformer]：让 [DlnaSession] 直接把原始 URL 给电视，
/// 绕开 dart_cast 的 [MediaProxy]（[MediaProxy] 不解密 AES-128 HLS，
/// 也不正确处理 app 自己的代理 URL）。
///
/// - 策略 A（远程原始 m3u8）：dart_cast MediaProxy 会用 [HlsParser.rewritePlaylist]
///   把 `#EXT-X-KEY` URI 改指向自身代理，但**不会**解密 TS 分片。
///   libmpv 严格按 HLS 规范解密，电视收到密文后黑屏。
/// - 策略 B（app 自己的 `VideoCacheProxyServer`）：app 代理**只透传**不解密
///   （`StreamWorker._doDownloadSegment` 仅下载原始密文），但 dart_cast MediaProxy
///   会改写 m3u8 把 `#EXT-X-KEY` URI 指向**自身的内嵌代理**，导致 TV 拿到
///   错误的 key → 解密失败 → 黑屏。
///
/// 两种策略都必须在 dart_cast 的 transformer 层短路，让 app 代理 URL 透传到 TV。
/// TV 端通过 app 代理的 `/hls-key/{cacheKey}?keyuri=...` 接口自行拉取 AES-128 key
/// 并解密分片（与本地播放器走完全相同的路径）。plan 1786714898308。
class _DlnaDirectMediaTransformer implements MediaTransformer {
  const _DlnaDirectMediaTransformer();

  @override
  Future<TransformedMedia> transform(CastMedia media, MediaProxy proxy) async {
    return TransformedMedia(proxyUrl: media.url, effectiveType: media.type);
  }
}

/// 手工构造 [DlnaSession]，避免 dart_cast 默认 transformer 带来的黑屏问题。
///
/// [DlnaSession.fromDevice] 不接受 [MediaTransformer] 参数，只能用默认 transformer。
/// 此处复用 `fromDevice` 的 metadata 提取逻辑（5 个键），传入 [_DlnaDirectMediaTransformer]
/// 让原始 URL 透传给 TV。
///
/// vendored dart_cast 的 `_loadMediaInternal` 仍会调用 `_proxy.start()`：
/// 启动一个未被使用的 MediaProxy 是无害的（dart_cast 内部不会主动绑定端口，
/// 直到 `registerMedia` 被调用）。如果未来发现端口冲突，可在 vendored 库加
/// `skipProxyStart` flag（不在本修复范围）。
DlnaSession _buildDlnaSession(CastDevice device) {
  final avTransportUrl = device.metadata['avTransportControlUrl'];
  final renderingControlUrl = device.metadata['renderingControlUrl'];
  final connectionManagerControlUrl =
      device.metadata['connectionManagerControlUrl'];

  final description = DlnaDeviceDescription(
    friendlyName: device.name,
    udn: device.id,
    manufacturer: device.metadata['manufacturer'],
    modelName: device.metadata['modelName'],
    avTransportControlUrl: avTransportUrl,
    renderingControlUrl: renderingControlUrl,
    connectionManagerControlUrl: connectionManagerControlUrl,
    locationUrl: 'http://${device.address.address}:${device.port}',
  );

  return DlnaSession(
    device: device,
    description: description,
    mediaTransformer: const _DlnaDirectMediaTransformer(),
  );
}
