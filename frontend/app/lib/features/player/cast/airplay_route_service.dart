import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import '../../../core/logger/app_logger.dart';

/// 原生 AirPlay 路由服务。
///
/// 通过 [showPicker] 调用原生 `AVRoutePickerView` 触发系统 AirPlay 选路面板
/// （不在 Dart 端嵌入 PlatformView）。
///
/// iOS / macOS 均通过 [EventChannel] 监听路由状态变化（iOS 走
/// [AVAudioSession.routeChangeNotification]，macOS 走 CoreAudio 默认输出设备
/// 变化）感知 AirPlay 路由状态。
///
/// 仅在 iOS / macOS 平台可用。其他平台调用为 no-op。
class AirPlayRouteService {
  static const _channel = MethodChannel('com.meowtv.airplay');
  static const _eventChannel = EventChannel('com.meowtv.airplay/events');

  StreamSubscription? _eventSub;
  final _activeController = StreamController<bool>.broadcast();
  final _routeNameController = StreamController<String?>.broadcast();

  bool _isActive = false;
  bool get isActive => _isActive;

  /// AirPlay 路由是否激活（true = 正在 AirPlay 输出）
  Stream<bool> get activeStream => _activeController.stream;

  /// 当前 AirPlay 路由名称（如 "Apple TV"）
  Stream<String?> get routeNameStream => _routeNameController.stream;

  /// 当前 AirPlay 路由名称
  String? _routeName;
  String? get routeName => _routeName;

  /// 开始监听 AirPlay 路由状态。
  ///
  /// 在 app 启动或进入播放器时调用。
  void start() {
    if (_eventSub != null) return;
    if (!Platform.isIOS && !Platform.isMacOS) return;
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (data) {
        _isActive = data as bool;
        _activeController.add(_isActive);
        if (_isActive) {
          _fetchRouteName();
        } else {
          _routeName = null;
          _routeNameController.add(null);
        }
      },
      onError: (e) {
        appLogger.w('[AirPlayRoute] EventChannel 错误: $e');
      },
    );
  }

  /// 停止监听
  void stop() {
    _eventSub?.cancel();
    _eventSub = null;
  }

  /// 弹出系统 AirPlay 路由选择器。
  ///
  /// iOS / macOS：调用原生 `AVRoutePickerView` 触发系统选路面板。
  /// 返回 [bool] 表示是否成功触发；失败时已记录错误日志。
  ///
  /// [anchor]：macOS 26 (Tahoe) 上系统要求 picker 按钮位于窗口可见区域内才
  /// 弹出 popover，故传入 Flutter 逻辑坐标（原点在窗口内容左上）让原生把
  /// 常驻 picker 临时移到该位置；缺省时原生取窗口右上角。iOS 原生不读参数，
  /// 无影响。
  Future<bool> showPicker({Offset? anchor}) async {
    if (!Platform.isIOS && !Platform.isMacOS) return false;
    try {
      final Map<String, double>? args = anchor == null
          ? null
          : {'x': anchor.dx, 'y': anchor.dy};
      final ok = await _channel.invokeMethod<bool>(
            'showAirPlayPicker',
            args,
          ) ??
          false;
      appLogger.i('[AirPlayRoute] showAirPlayPicker 结果=$ok anchor=$anchor');
      return ok;
    } catch (e) {
      appLogger.e('[AirPlayRoute] showAirPlayPicker 调用失败', error: e);
      return false;
    }
  }

  /// 查询当前 AirPlay 是否激活
  Future<bool> checkActive() async {
    if (!Platform.isIOS && !Platform.isMacOS) return false;
    try {
      return await _channel.invokeMethod('isExternalPlaybackActive') ?? false;
    } catch (e) {
      appLogger.w('[AirPlayRoute] isExternalPlaybackActive 失败: $e');
      return false;
    }
  }

  /// 一键断开 AirPlay。
  ///
  /// iOS：原生把所有 AVPlayer 的 `allowsExternalPlayback` 置 false，立即把视频
  /// 从 AirPlay 接收端踢回本机；返回 true 表示成功踢掉至少一个 player。
  /// macOS：原生把系统默认输出设备切回非 AirPlay（优先内置）；返回 true 表示
  /// 实际执行了 CoreAudio 默认输出切换。
  ///
  /// 调用方应根据返回值决定是否走 picker 兜底（返回 false 时）。
  /// 其他平台为 no-op 返回 false。
  Future<bool> disconnect() async {
    if (!Platform.isIOS && !Platform.isMacOS) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('disconnectAirPlay') ?? false;
      appLogger.i('[AirPlayRoute] disconnectAirPlay 结果=$ok');
      return ok;
    } catch (e) {
      appLogger.e('[AirPlayRoute] disconnectAirPlay 调用失败', error: e);
      return false;
    }
  }

  Future<void> _fetchRouteName() async {
    try {
      _routeName = await _channel.invokeMethod('getActiveRouteName');
      _routeNameController.add(_routeName);
    } catch (e) {
      appLogger.w('[AirPlayRoute] getActiveRouteName 失败: $e');
    }
  }

  void dispose() {
    stop();
    _activeController.close();
    _routeNameController.close();
  }
}