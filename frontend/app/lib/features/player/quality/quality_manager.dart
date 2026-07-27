import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../../../core/cache/video_cache_proxy.dart';
import '../../../core/logger/app_logger.dart';
import '../../../core/stream/m3u8_parser.dart';
import '../../../core/stream/stream_config.dart';
import 'abr_controller.dart';
import 'network_preference.dart';
import 'quality_level.dart';

/// 清晰度切换进度
enum QualitySwitchState {
  idle,       // 空闲
  precaching, // 预缓存中
  switching,  // 正在切换
}

/// 清晰度管理器
class QualityManager extends ChangeNotifier {
  final M3u8Parser _parser = M3u8Parser();
  final ABRController _abrController = ABRController();

  /// 可用清晰度列表
  List<QualityLevel> levels = [];

  /// 当前播放清晰度
  QualityLevel? currentLevel;

  /// 清晰度模式
  QualityMode mode = QualityMode.auto;

  /// 手动选择的清晰度
  QualityLevel? manualLevel;

  /// 切换状态
  QualitySwitchState switchState = QualitySwitchState.idle;

  /// 预缓存进度 (0.0 - 1.0)
  double precacheProgress = 0.0;

  /// 正在切换到的目标清晰度
  QualityLevel? switchTarget;

  /// 原始 M3u8Info（master playlist）
  M3u8Info? _masterInfo;

  /// 当前 cacheKey
  String? _currentCacheKey;

  /// 切换完成回调 — 由 PlayerScreen 设置，切换完成后调用以更新播放器
  void Function(String proxyUrl, Duration position)? onSwitchReady;

  /// 切换失败回调
  void Function(String message)? onSwitchFailed;

  /// 连接状态订阅
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// 从 master playlist 解析清晰度列表
  void parseLevels(List<VariantInfo> variants) {
    levels = variants.map((v) => v.toQualityLevel()).toList();
    // 按带宽从高到低排序
    levels.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    appLogger.i('[Quality] 解析到 ${levels.length} 个清晰度等级');
    notifyListeners();
  }

  /// 初始化：设置原始信息
  void initialize({
    required M3u8Info masterInfo,
    required String cacheKey,
    required String originalUrl,
  }) {
    _masterInfo = masterInfo;
    _currentCacheKey = cacheKey;

    if (masterInfo.isMaster && masterInfo.variants.isNotEmpty) {
      parseLevels(masterInfo.variants);
      // 初始清晰度为当前使用的（最高带宽）
      currentLevel = levels.isNotEmpty ? levels.first : null;
    }

    // 监听网络变化
    _startConnectivityListener();
  }

  /// 根据网络偏好确定初始清晰度
  Future<void> applyInitialQuality(ConnectivityResult connectivity) async {
    if (levels.isEmpty) return;

    final preference = connectivity == ConnectivityResult.wifi
        ? await NetworkPreference.getWifiPreference()
        : await NetworkPreference.getCellularPreference();

    if (mode == QualityMode.auto) {
      // ABR 评估
      final recommended = _abrController.evaluate(levels, connectivity);
      if (recommended != null) {
        currentLevel = recommended;
      }
    } else {
      final specificId = connectivity == ConnectivityResult.wifi
          ? await NetworkPreference.getWifiSpecificLevel()
          : await NetworkPreference.getCellularSpecificLevel();
      final recommended = NetworkPreference.getRecommendedLevel(
        preference,
        levels,
        specificLevelId: specificId,
      );
      if (recommended != null) {
        currentLevel = recommended;
      }
    }

    appLogger.i('[Quality] 初始清晰度: ${currentLevel?.label ?? "无"}');
    notifyListeners();
  }

  /// 手动切换清晰度（预缓存无缝切换）
  Future<void> selectQuality(QualityLevel level) async {
    if (level == currentLevel) return;
    if (switchState != QualitySwitchState.idle) {
      appLogger.w('[Quality] 正在切换中，忽略请求');
      return;
    }
    if (_currentCacheKey == null || _masterInfo == null) return;

    mode = QualityMode.manual;
    manualLevel = level;
    switchTarget = level;
    switchState = QualitySwitchState.precaching;
    precacheProgress = 0.0;
    notifyListeners();

    appLogger.i('[Quality] 开始切换清晰度: ${currentLevel?.label} → ${level.label}');

    try {
      // 1. 找到对应的 VariantInfo
      final variant = _masterInfo!.variants.firstWhere(
        (v) => '${v.bandwidth}_${v.resolution}' == level.id,
        orElse: () => _masterInfo!.variants.first,
      );

      // 2. 注册新码率的代理 URL
      final newCacheKey = '${_currentCacheKey}_${level.id}';
      await VideoCacheProxyServer.instance.register(newCacheKey, variant.uri);

      // 3. 确保代理服务器运行
      await VideoCacheProxyServer.instance.start();

      // 4. 恢复/启动缓存
      await VideoCacheProxyServer.instance.resumeProxyCache(newCacheKey);

      // 5. 获取代理 URL
      final proxyUrl = VideoCacheProxyServer.instance.hlsProxyUrl(newCacheKey);

      // 6. 模拟预缓存进度（实际 StreamSession 会后台下载分片）
      for (var i = 1; i <= 5; i++) {
        await Future.delayed(const Duration(milliseconds: 300));
        precacheProgress = i / 5;
        notifyListeners();
      }

      // 7. 通知切换完成
      switchState = QualitySwitchState.switching;
      notifyListeners();

      // 8. 获取当前播放位置
      final currentPosition = Duration.zero;

      // 9. 回调通知 PlayerScreen 切换
      onSwitchReady?.call(proxyUrl, currentPosition);

      // 10. 停止旧码率调度（保留缓存）
      VideoCacheProxyServer.instance.unregister(_currentCacheKey!);

      // 11. 更新状态
      _currentCacheKey = newCacheKey;
      currentLevel = level;
      switchState = QualitySwitchState.idle;
      switchTarget = null;
      precacheProgress = 0.0;
      _abrController.markSwitched();

      appLogger.i('[Quality] 清晰度切换完成: ${level.label}');
      notifyListeners();
    } catch (e) {
      appLogger.e('[Quality] 清晰度切换失败', error: e);
      switchState = QualitySwitchState.idle;
      switchTarget = null;
      precacheProgress = 0.0;
      onSwitchFailed?.call('清晰度切换失败，请重试');
      notifyListeners();
    }
  }

  /// 切换到自动模式
  void setAutoMode() {
    mode = QualityMode.auto;
    manualLevel = null;
    appLogger.i('[Quality] 切换到自动模式');
    notifyListeners();
  }

  /// ABR 评估（根据当前网络状况推荐清晰度）
  Future<void> evaluateABR(ConnectivityResult connectivity) async {
    if (mode != QualityMode.auto) return;
    if (levels.isEmpty) return;
    if (switchState != QualitySwitchState.idle) return;

    final recommended = _abrController.evaluate(levels, connectivity);
    if (recommended != null && recommended != currentLevel) {
      appLogger.i('[Quality] ABR 推荐: ${recommended.label} (当前: ${currentLevel?.label})');
      await selectQuality(recommended);
    }
  }

  /// 监听网络变化
  void _startConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      // connectivity_plus v6+ 返回 List<ConnectivityResult>，取第一个
      final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
      if (mode == QualityMode.auto) {
        evaluateABR(result);
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _parser.close();
    super.dispose();
  }

  /// 清除状态（新视频时调用）
  void reset({bool notify = true}) {
    levels = [];
    currentLevel = null;
    mode = QualityMode.auto;
    manualLevel = null;
    switchState = QualitySwitchState.idle;
    precacheProgress = 0.0;
    switchTarget = null;
    _masterInfo = null;
    _currentCacheKey = null;
    _isDefault = false;
    _abrController.reset();
    if (notify) notifyListeners();
  }

  /// 是否有多码率可选
  bool get hasMultipleLevels => levels.length > 1;

  /// 是否为默认清晰度（非 master playlist，无法识别清晰度等级）
  bool _isDefault = false;

  /// 是否为默认清晰度（无法识别清晰度等级时显示"默认"标签）
  bool get isDefault => _isDefault;

  /// 设置为默认清晰度（非 master playlist 或无法识别清晰度时调用）
  void setDefault() {
    _isDefault = true;
    notifyListeners();
  }

  /// 获取当前清晰度显示标签
  String get currentLabel {
    if (_isDefault) return '默认';
    if (levels.isEmpty) return '';
    return currentLevel?.label ?? '自动';
  }
}
