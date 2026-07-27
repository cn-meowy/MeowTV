import 'dart:async';
import 'package:dart_cast/dart_cast.dart';
import '../../../core/logger/app_logger.dart';

/// 投屏服务封装：设备发现、连接、播放控制、断开
class MeowCastService {
  final CastService _service = CastService(
    discoveryProviders: [
      ChromecastDiscoveryProvider(),
      AirPlayDiscoveryProvider(),
      DlnaDiscoveryProvider(),
    ],
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

  Duration _castPosition = Duration.zero;
  Duration _castDuration = Duration.zero;

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

  /// 取消 session 流订阅（disconnect / 重连前调用）
  void _cancelSessionSubscriptions() {
    _posSub?.cancel();
    _durSub?.cancel();
    _volSub?.cancel();
    _posSub = null;
    _durSub = null;
    _volSub = null;
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
    _devices = [];
    _devicesController.add(_devices);
    _updateState(CastState.discovering);

    try {
      _service.startDiscovery(timeout: timeout).listen(
        (deviceList) {
          _devices = deviceList;
          _devicesController.add(_devices);
          appLogger.i('[Cast] 发现 ${deviceList.length} 个设备');
        },
        onDone: () {
          if (_state == CastState.discovering) {
            _updateState(CastState.disconnected);
          }
          appLogger.i('[Cast] 设备发现结束');
        },
        onError: (e) {
          appLogger.e('[Cast] 设备发现失败', error: e);
          _updateState(CastState.disconnected);
        },
      );
    } catch (e) {
      appLogger.e('[Cast] 启动设备发现失败', error: e);
      _updateState(CastState.disconnected);
    }
  }

  /// 停止设备发现
  void stopDiscovery() {
    _service.stopDiscovery();
  }

  /// 连接到设备并开始投屏
  Future<void> connectAndPlay(CastDevice device, CastMedia media) async {
    appLogger.i('[Cast] 连接设备: ${device.name} (${device.protocol})');
    _updateState(CastState.connecting);

    try {
      // 断开之前的连接
      await disconnect();

      _activeSession = await _service.connect(device);
      _connectedDevice = device;
      _updateState(CastState.connected);

      // 订阅远端进度/时长/音量流（转发到中转流）
      _subscribeSessionStreams();

      // 监听会话状态
      _activeSession!.stateStream.listen((sessionState) {
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
            _updateState(CastState.disconnected);
            _activeSession = null;
            _connectedDevice = null;
            break;
          default:
            break;
        }
      });

      // 加载媒体
      _updateState(CastState.loading);
      await _activeSession!.loadMedia(media);
      appLogger.i('[Cast] 媒体加载成功: ${media.url}');
    } catch (e) {
      appLogger.e('[Cast] 连接/播放失败', error: e);
      _cancelSessionSubscriptions();
      _updateState(CastState.disconnected);
      _activeSession = null;
      _connectedDevice = null;
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
      appLogger.i('[Cast] 切集续投加载成功: ${media.url}');
    } catch (e) {
      appLogger.e('[Cast] 切集续投加载失败', error: e);
    }
  }

  /// 暂停
  Future<void> pause() async {
    try {
      await _activeSession?.pause();
    } catch (e) {
      appLogger.e('[Cast] 暂停失败', error: e);
    }
  }

  /// 恢复播放
  Future<void> play() async {
    try {
      await _activeSession?.play();
    } catch (e) {
      appLogger.e('[Cast] 播放失败', error: e);
    }
  }

  /// 跳转
  Future<void> seek(Duration position) async {
    try {
      await _activeSession?.seek(position);
    } catch (e) {
      appLogger.e('[Cast] 跳转失败', error: e);
    }
  }

  /// 设置音量（0.0-1.0）
  Future<void> setVolume(double volume) async {
    try {
      await _activeSession?.setVolume(volume);
    } catch (e) {
      appLogger.e('[Cast] 设置音量失败', error: e);
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    if (_activeSession != null) {
      try {
        await _activeSession!.disconnect();
      } catch (e) {
        appLogger.e('[Cast] 断开连接失败', error: e);
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
