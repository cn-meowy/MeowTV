import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:dart_cast/dart_cast.dart';
import '../../core/logger/app_logger.dart';
import '../../core/theme/app_theme.dart' show BuildContextThemeX;
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../shared/models/resource_detail.dart';
import '../../shared/models/enums.dart';
import '../download/download_provider.dart';
import '../history/history_provider.dart';
import '../settings/douban_image_proxy_provider.dart';
import '../settings/buffer_mode_provider.dart';
import '../settings/play_mode_provider.dart';
import '../settings/aspect_ratio_provider.dart';
import '../detail/m3u8_check_provider.dart';
import '../../core/cache/play_cache_service.dart';
import '../../core/cache/video_cache_proxy.dart';
import '../../core/cache/cache_meta.dart';
import 'widgets/player_controls/sleep_timer_provider.dart';
import '../../core/cache/play_cache_download_service.dart';
import 'widgets/info_panel.dart';
import 'widgets/resource_tabs.dart';
import 'widgets/episode_list.dart';
import '../../shared/widgets/download_episode_dialog.dart';
import '../../shared/widgets/cache_episode_dialog.dart';
import 'widgets/player_controls/controls_overlay.dart';
import 'widgets/player_controls/cast_connecting_overlay.dart';
import 'widgets/player_controls/aspect_ratio_panel.dart';
import 'cast/cast_provider.dart';
import 'cast/cast_service.dart';
import 'playback/playback_provider.dart';
import '../settings/cast_proxy_provider.dart';
import 'subtitle/subtitle_provider.dart';
import 'subtitle/subtitle_render_bridge.dart';
import 'subtitle/subtitle_model.dart';
import 'quality/quality_manager.dart';
import 'quality/quality_provider.dart';
import 'audio_track/audio_track_provider.dart';
import 'audio_track/audio_track_manager.dart';
import 'capture/capture_provider.dart';
import 'capture/media_capture_manager.dart';
import 'danmaku/danmaku_provider.dart';
import 'danmaku/danmaku_controller.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String resourceDomain;
  final int vodId;
  final int sourceIndex;
  final int epIndex;
  const PlayerScreen({super.key, required this.resourceDomain, required this.vodId, this.sourceIndex = 0, this.epIndex = 0});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  String _playerTitle = '';
  bool _isPlayerInitialized = false;
  bool _isLoadingDetail = true;
  bool _isBuffering = false;
  String? _errorMessage;
  ResourceDetailResponse? _detail;
  List<PlaySource> _sources = [];
  int _currentSourceIndex = 0;
  int _currentEpIndex = 0;
  Timer? _progressTimer;
  Timer? _bufferingTimeout;
  Timer? _errorDelayTimer;  // 错误确认延迟计时器，用于可重试错误的去重
  Timer? _autoRetryTimer;   // 自动重试定时器
  VoidCallback? _videoListener;

  // ── 自动重试与线路切换状态 ──
  int _retryCount = 0;                    // 当前线路的重试计数
  static const int _maxRetryCount = 3;     // 同一线路最大重试次数
  int _autoSwitchAttempt = 0;              // 已尝试的线路数
  bool _isAutoRetrying = false;            // 是否正在自动重试中
  String? _currentCacheKey;                // 当前播放的代理缓存 key（重试/切换线路时用于 unregister）

  // ── m3u8 位置守护（修复 Android 上无限重复第一个分片）──
  Duration? _lastStablePosition;
  bool _isM3u8Url = false; // 当前播放是否为 m3u8
  int _positionResetCount = 0; // 位置跳回起始的累计次数
  DateTime? _lastResetTime; // 上次跳回的时间
  Duration? _userSeekTarget; // 用户主动 seek 的目标位置（区分用户操作和异常跳回）

  // ── 续播状态 ──
  /// 待 seek 的续播位置（秒）。API 返回后若 VPC 未就绪则缓存，待 isInitialized 时 seek。
  int? _resumePositionSeconds;
  /// 续播 seek 是否已执行（保证 seek 只执行一次，避免与用户手动 seek 冲突）
  bool _resumeSeeked = false;

  // ── 全屏恢复幂等标志 ──
  bool _isRestoringFromFullscreen = false;  // 防止 _onExitFullscreen 被多次调用

  // ── 画面比例 ──
  final ValueNotifier<ChewieController?> _chewieControllerNotifier = ValueNotifier(null);

  // ── 本地下载检查状态 ──
  String? _localFileUrl;          // 已下载文件的服务器流 URL
  // ignore: unused_field
  String _localFileFormat = 'mp4'; // 本地文件格式（预留，未来用于 UI 展示本地播放标识）
  bool _checkingLocal = false;    // 是否正在检查本地下载
  int _checkDownloadSeq = 0;      // 序列号，防止过期的异步回调

  // ── 投屏 ──
  QualityManager? _qualityManager;

  /// 音轨是否已获取（防止重复获取）
  bool _audioTrackFetched = false;

  /// 当前播放的远程 URL（投屏时设备可访问的地址，非本机代理地址）
  String _currentCastUrl = '';

  /// 用户主动断开投屏标志（区分用户操作与设备意外断线）
  bool _userInitiatedDisconnect = false;

  /// 投屏状态变化订阅
  StreamSubscription<CastState>? _castStateSub;

  // ── 缓存 Provider 引用（dispose 时 ref.read 不可用，需提前缓存） ──
  late final DanmakuController _danmakuController;
  late final AudioTrackManager _audioTrackManager;
  late final MediaCaptureManager _captureManager;
  late final HistoryNotifier _historyNotifier;

  @override
  void initState() {
    super.initState();
    // 缓存 Provider 引用：dispose 时 element 已 defunct，ref.read 会抛 StateError
    _danmakuController = ref.read(danmakuControllerProvider);
    _audioTrackManager = ref.read(audioTrackManagerProvider);
    _captureManager = ref.read(captureManagerProvider);
    _historyNotifier = ref.read(historyProvider.notifier);
    appLogger.i('[Player] 初始化索引：sourceIndex=${widget.sourceIndex}, epIndex=${widget.epIndex}');
    _currentSourceIndex = widget.sourceIndex;
    _currentEpIndex = widget.epIndex;
    // 确保图片代理就绪，避免信息面板封面图 buildImageUrl 因 token 为空回退到原始 URL
    Future.microtask(() => ref.read(doubanImageProxyProvider.notifier).init());
    _initPlayer();
    _listenCastState();
  }

  /// 监听投屏状态变化，设备意外断线时自动回退本地播放
  void _listenCastState() {
    final castService = ref.read(castServiceProvider);
    _castStateSub = castService.stateStream.listen((castState) {
      if (!mounted) return;

      // 设备意外断线（非用户主动断开）：自动回退本地播放
      if (castState == CastState.disconnected && !_userInitiatedDisconnect) {
        final castPosition = castService.castPosition;
        appLogger.i('[Player] 投屏设备意外断线，自动回退本地播放，断点位置: $castPosition');

        // 从远端最后位置恢复本地播放
        if (castPosition.inMilliseconds > 0 && _chewieController != null) {
          _chewieController!.seekTo(castPosition);
          _chewieController!.play();
          ref.read(danmakuControllerProvider).play();
        } else {
          _chewieController?.play();
          ref.read(danmakuControllerProvider).play();
        }

        // 提示用户
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('投屏设备已断开，已恢复本地播放'),
            duration: Duration(seconds: 3),
          ),
        );
      }

      // 重置用户主动断开标志
      if (castState == CastState.disconnected) {
        _userInitiatedDisconnect = false;
      }
    });
  }

  /// 初始化播放器
  Future<void> _initPlayer() async {
    if (mounted) setState(() { _isPlayerInitialized = true; });

    // 设置定时关闭回调：到达指定时间后暂停播放并提示
    ref.read(sleepTimerProvider.notifier).setOnExpired(() {
      if (!mounted) return;
      _chewieController?.pause();
      ref.read(danmakuControllerProvider).pause();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('定时关闭：播放已暂停'),
          duration: Duration(seconds: 3),
        ),
      );
    });

    _loadDetailAndPlay();
    _startProgressReporting();
  }

  Future<void> _loadDetailAndPlay() async {
    setState(() { _isLoadingDetail = true; _errorMessage = null; });
    appLogger.i('[Player] 加载资源详情: site=${widget.resourceDomain}, vod_id=${widget.vodId}');
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.post<Map<String, dynamic>>(ApiConstants.resourceDetail, data: {'site': widget.resourceDomain, 'vod_id': widget.vodId});
      final body = resp.data!;
      _detail = ResourceDetailResponse.fromJson((body['data'] ?? body) as Map<String, dynamic>);
      _sources = _detail!.parsedSources;
      final playUrlPreview = _detail!.vodPlayUrl != null && _detail!.vodPlayUrl!.isNotEmpty
          ? _detail!.vodPlayUrl!.substring(0, _detail!.vodPlayUrl!.length > 200 ? 200 : _detail!.vodPlayUrl!.length)
          : '<null>';
      appLogger.i('[Player] 资源详情加载成功: ${_detail!.vodName}, 播放源数量=${_sources.length}, vod_play_url=$playUrlPreview...');
      // 触发 m3u8 链接检测（如果 DetailScreen 尚未触发）
      _triggerM3u8Check();
      if (_sources.isEmpty) {
        appLogger.w('[Player] 解析后无可用播放源, vod_play_from=${_detail!.vodPlayFrom}');
        if (mounted) setState(() { _isLoadingDetail = false; _errorMessage = '暂无可播放的资源'; });
        return;
      }
      if (mounted) setState(() => _isLoadingDetail = false);
      // 方案A：默认缓冲模式
      final bufferState = ref.read(bufferModeProvider);
      if (bufferState.mode == BufferMode.strategyA) {
        appLogger.i('[Player] 方案A 缓冲模式，当前使用默认缓冲');
      }
      // 先检查本地下载，完成后再播放
      await _checkLocalDownload();
      _playCurrentEpisode();
    } catch (e, stackTrace) {
      appLogger.e('[Player] 加载资源详情失败', error: e, stackTrace: stackTrace);
      if (mounted) setState(() { _isLoadingDetail = false; _errorMessage = '加载资源详情失败: $e'; });
    }
  }

  Future<void> _playCurrentEpisode() async {
    if (_sources.isEmpty) return;
    // 重置续播状态（每次切集/切源都重新获取进度）
    _resumePositionSeconds = null;
    _resumeSeeked = false;

    final si = _currentSourceIndex.clamp(0, _sources.length - 1);
    final source = _sources[si];
    if (source.episodes.isEmpty) { setState(() => _errorMessage = '当前资源没有可播放的剧集'); return; }
    final ei = _currentEpIndex.clamp(0, source.episodes.length - 1);
    final episode = source.episodes[ei];

    // 获取历史播放进度，用于自动续播
    // 关键修复：必须 await 等待 API 返回后再创建播放器，
    // 否则 _resumePositionSeconds 在 ChewieController 创建时仍为 null，
    // 导致 autoPlay 始终为 true 且 videoListener 续播分支无法触发。
    //
    // 重要：必须在 _upsertPlayHistory 之前调用！
    // 因为 upsert 请求不含 progress/current_time/duration 字段，
    // Go 零值会覆写后端已有的进度数据，导致 fetch 获取到 current_time=0。
    // 后端已修复 Upsert DoUpdates 不再更新进度字段，此处调换顺序作为双重保障。
    await _fetchAndApplyResumePosition();

    // 写入播放历史（含完整信息，确保 vod_name/vod_pic/resource_name 不为空）
    // 放在 fetch 之后，避免 upsert 覆写 current_time 为 0
    _upsertPlayHistory();

    // 本地文件优先；检查中暂不播放，避免先播放远程再切换本地的闪烁
    final String url;
    if (_localFileUrl != null) {
      url = _localFileUrl!;
      // 本地文件无远程 URL，投屏不可用
      _currentCastUrl = '';
    } else if (_checkingLocal) {
      appLogger.i('[Player] 正在检查本地下载，暂缓播放');
      return;
    } else {
      // 方案B：使用代理边下边播
      final bufferState = ref.read(bufferModeProvider);
      if (bufferState.mode == BufferMode.strategyB && _detail != null) {
        final cacheKey = PlayCacheService.instance.cacheKey(
          _detail!.resourceDomain,
          widget.vodId,
          _currentSourceIndex,
          _currentEpIndex,
        );

        // 存储 cacheKey 供重试/切换线路时 unregister 旧 session
        _currentCacheKey = cacheKey;

        // 注册远程 URL 到代理
        await VideoCacheProxyServer.instance.register(cacheKey, episode.url);

        // 确保 proxy 服务器运行
        await VideoCacheProxyServer.instance.start();

        // 检查是否有 paused 状态的 auto 缓存
        final meta = await PlayCacheService.instance.getCacheMeta(cacheKey);
        if (meta != null &&
            meta.cacheSource == CacheSource.auto &&
            meta.taskStatus == CacheTaskStatus.paused) {
          // 有 paused 的缓存，恢复并继续
          appLogger.i('[Player] 检测到 paused 自动缓存，恢复缓存: $cacheKey');
          await VideoCacheProxyServer.instance.resumeProxyCache(cacheKey);
        } else {
          // 新缓存或无缓存，正常注册
          appLogger.i('[Player] 新建自动缓存: $cacheKey');
          await VideoCacheProxyServer.instance.resumeProxyCache(cacheKey);
        }

        // 使用代理 URL — 方案B 始终走 /hls/ 路由：
        // 1. 边下边播需要解析 m3u8 才能调度分片下载
        // 2. 即使原始 URL 实际是 MP4，/hls/ 路由也能通过内容嗅探降级处理
        // 3. 避免 _isHlsUrl() 误判导致 ExoPlayer UnrecognizedInputFormatException
        //    （/proxy/ 路由返回 m3u8 文本时，ExoPlayer 的 ProgressiveMediaSource
        //     无法识别，而 /hls/ 路由返回的 m3u8 会被 HLS 解析器正确处理）
        url = VideoCacheProxyServer.instance.hlsProxyUrl(cacheKey);

        // 初始化清晰度管理器
        // 注意：StreamSession 在视频播放器首次请求 /hls/{cacheKey} 时才异步创建，
        // 此时 getSession 返回 null。通过 onSessionCreated 回调在 Session 创建后
        // 初始化清晰度管理器，解决时序竞争问题。
        _qualityManager ??= ref.read(qualityManagerProvider);
        _initQualityManagerOnSessionReady(cacheKey, episode.url);

        appLogger.i('[Player] 方案B 使用代理缓存: $cacheKey, proxyUrl=$url');
      } else {
        url = episode.url;
        // 记录远程原始 URL 供投屏使用（非代理地址，投屏设备可直接访问）
        _currentCastUrl = episode.url;
      }
    }

    // 判断是否使用方案B代理缓存（代理 URL 走 /hls/ 路由）
    final isUsingProxyCache = _localFileUrl == null &&
        !_checkingLocal &&
        ref.read(bufferModeProvider).mode == BufferMode.strategyB &&
        _detail != null;

    // 标记当前播放类型（是否为 m3u8）和重置位置守护
    // 使用代理缓存时，/hls/ 路由返回的是重写后的 m3u8，始终视为 HLS
    _isM3u8Url = isUsingProxyCache || url.contains('.m3u8');

    // 非代理缓存时重置清晰度管理器并设置默认标识
    if (!isUsingProxyCache) {
      _qualityManager?.reset();
      _qualityManager ??= ref.read(qualityManagerProvider);
      _qualityManager!.setDefault();
    }

    _lastStablePosition = null;
    _positionResetCount = 0;
    _lastResetTime = null;
    _userSeekTarget = null;

    // 开始新播放时，取消之前的错误延迟计时器
    _errorDelayTimer?.cancel();
    setState(() { _errorMessage = null; _isBuffering = true; });
    _cancelBufferingTimeout();
    final urlPreview = url.length > 200 ? url.substring(0, 200) : url;
    appLogger.i('[Player] 开始播放: source=${source.name}, episode=${episode.name}, isLocal=${_localFileUrl != null}, isProxyCache=$isUsingProxyCache, url=$urlPreview');

    // 设置当前视频源路径到截图/录制/GIF 管理器
    _captureManager.setVideoSource(url);

    // 销毁旧控制器
    await _disposeControllers();

    // 创建新的 VideoPlayerController + ChewieController
    // 关键修复：当使用方案B代理缓存时，必须传入 formatHint: VideoFormat.hls，
    // 否则 ExoPlayer 的 DefaultMediaSourceFactory 无法从代理 URL（如
    // http://localhost:PORT/hls/cacheKey）判断内容格式，默认使用
    // ProgressiveMediaSource（MP4 模式），导致收到 m3u8 文本后报
    // UnrecognizedInputFormatException（sniff failures: NoDeclaredBrand）。
    // 传入 formatHint 后，ExoPlayer 会使用 HlsMediaSource 正确解析 m3u8。
    //
    // 关键修复：iOS 上 video_player 可能通过平台通道异步抛出 PlatformException
    // （如 CoreMediaErrorDomain fmt?），该异常不会被 videoListener 的 hasError
    // 捕获，而是直接逃逸为 Unhandled Exception。此处用 try-catch 包裹，
    // 将其转入 _handleVideoError 三级容错流程。
    try {
      final vpc = VideoPlayerController.networkUrl(
        Uri.parse(url),
        formatHint: isUsingProxyCache ? VideoFormat.hls : null,
      );
      _videoPlayerController = vpc;

      _videoListener = () {
        if (!mounted) return;
        final value = vpc.value;

        // 缓冲状态
        final isBuffering = value.isBuffering;
        appLogger.i('[Player] videoListener 事件: buffering=$isBuffering (之前: $_isBuffering)');
        if (isBuffering != _isBuffering) {
          setState(() => _isBuffering = isBuffering);
          if (isBuffering) {
            appLogger.i('[Player] 开始缓冲，启动缓冲超时');
            _startBufferingTimeout();
          } else {
            appLogger.i('[Player] 停止缓冲，取消缓冲超时');
            _cancelBufferingTimeout();
          }
        }

        // 弹幕同步
        if (value.isInitialized) {
          ref.read(danmakuControllerProvider).updatePosition(
            value.position,
            Size(value.size.width, value.size.height),
          );

          // 续播：VPC 就绪后检查是否有待 seek 的续播位置（API 先返回、VPC 后就绪的情况）
          if (!_resumeSeeked && _resumePositionSeconds != null) {
            _applyResumeSeek(vpc, _resumePositionSeconds!);
          }

          // 音轨初始化：首次初始化完成后获取音轨列表
          if (!_audioTrackFetched) {
            _audioTrackFetched = true;
            Future.microtask(() async {
              if (mounted) {
                await ref.read(audioTrackManagerProvider).fetchTracks(vpc);
              }
            });
          }
        }

        // 错误处理
        if (value.hasError) {
          final errorStr = value.errorDescription ?? 'Unknown video error';
          _handleVideoError(errorStr);
        }

        // 播放完成
        if (value.position >= value.duration && value.duration.inMilliseconds > 0 && value.position.inMilliseconds > 0) {
          _onPlaybackCompleted();
        }

        // 播放开始时清除错误消息
        if (value.isPlaying && _errorMessage != null) {
          _errorDelayTimer?.cancel();
          appLogger.i('[Player] 播放已开始，清除错误提示');
          setState(() { _errorMessage = null; });
        }

        // 位置守护
        _checkPositionGuard(value.position);
      };
      vpc.addListener(_videoListener!);

      _chewieController = ChewieController(
        videoPlayerController: vpc,
        autoInitialize: true,
        // 续播时禁用 autoPlay：避免从位置 0 开始播放后再 seek 导致的竞争问题
        // seek 完成后由 _applyResumeSeek 手动调用 play()
        autoPlay: _resumePositionSeconds == null,
        aspectRatio: 16 / 9,
        showControls: false,
        allowedScreenSleep: false,
        allowFullScreen: false,
        errorBuilder: (context, errorMessage) {
          appLogger.e('[Player] Chewie errorBuilder: $errorMessage');
          _handleVideoError(errorMessage);
          return const SizedBox.shrink();
        },
      );

      // 更新标题
      _playerTitle = _playerTitleComputed;

      // 播放器初始化成功，重置重试计数
      _retryCount = 0;
      _isAutoRetrying = false;

      _chewieControllerNotifier.value = _chewieController;
      // 同步到全局 PlaybackController 使用的 ValueNotifier
      globalChewieNotifier.value = _chewieController;
      setState(() {});

      // 字幕初始化：视频加载后获取内嵌字幕轨道
      Future.microtask(() async {
        final bridge = SubtitleRenderBridge();
        final embeddedTracks = await bridge.getEmbeddedTracks();
        if (embeddedTracks.isNotEmpty && mounted) {
          ref.read(subtitleManagerProvider).setEmbeddedTracks(embeddedTracks);
        }
      });

      // 音轨初始化：视频加载后获取内嵌音轨列表
      // 在 videoListener 中 isInitialized 首次变为 true 时触发
      _audioTrackFetched = false;
    } catch (e) {
      // 捕获 iOS PlatformException 等初始化期间逃逸的异常
      appLogger.e('[Player] 播放器初始化异常（PlatformException 逃逸捕获）', error: e);
      await _disposeControllers();
      if (mounted) {
        _handleVideoError(e.toString());
      }
    }
  }

  /// 销毁视频控制器。
  ///
  /// 在播放器仍 active 时调用（切集/切清晰度）。会同步移除监听并重置弹幕/音轨
  /// 管理器，再异步释放视频控制器原生资源。
  Future<void> _disposeControllers() async {
    _detachVideoListener();
    // 同步重置受 watch 的 ChangeNotifier（widget active 时 notify 安全）
    _resetPlayerManagers();
    await _chewieController?.pause();
    _chewieController?.dispose();
    _chewieController = null;
    await _videoPlayerController?.dispose();
    _videoPlayerController = null;
    // 清除全局 notifier 引用
    globalChewieNotifier.value = null;
  }

  /// 同步移除视频监听并重置弹幕/音轨管理器。
  ///
  /// 这部分必须在 element 仍 active 时执行（[dispose] 中需在 [super.dispose] 之前）：
  /// [DanmakuController.reset]/[AudioTrackManager.reset] 会 [notifyListeners]，
  /// 若推迟到 defunct 之后会触发 '_lifecycleState != defunct' 断言。
  void _detachVideoListener() {
    if (_videoListener != null) {
      _videoPlayerController?.removeListener(_videoListener!);
      _videoListener = null;
    }
  }

  /// 重置弹幕与音轨管理器（触发 [notifyListeners]，需在 element active 时调用）。
  ///
  /// 仅用于切换视频等非 dispose 场景；dispose 时直接调用各 manager 的
  /// `reset(notify: false)` 以避免 Riverpod 断言错误。
  void _resetPlayerManagers() {
    // 清除全局 notifier 引用（投屏/控件依赖，提前清空避免旧引用残留）
    globalChewieNotifier.value = null;
    _danmakuController.reset();
    _audioTrackManager.reset();
  }

  /// 异步释放视频控制器原生资源（不触发 watch 重建，可 fire-and-forget）。
  ///
  /// 在 [dispose] 中于 [super.dispose] 之后调用：[ChewieController]/
  /// [VideoPlayerController] 的释放是平台层异步操作，不依赖 widget element 状态，
  /// 即使 element 已 defunct 也安全。
  Future<void> _releaseVideoControllers() async {
    await _chewieController?.pause();
    _chewieController?.dispose();
    _chewieController = null;
    await _videoPlayerController?.dispose();
    _videoPlayerController = null;
  }

  /// 清晰度切换：替换播放器 URL 并 seek 到原位置
  Future<void> _switchToNewQuality(String proxyUrl, Duration position) async {
    if (!mounted) return;
    appLogger.i('[Player] 清晰度切换到: $proxyUrl, seekTo: ${position.inSeconds}s');

    // 更新截图/录制/GIF 管理器的视频源路径
    _captureManager.setVideoSource(proxyUrl);

    try {
      // 保存当前位置
      final currentPosition = _videoPlayerController?.value.position ?? position;

      // 销毁旧控制器
      await _disposeControllers();

      // 创建新的 VideoPlayerController
      final vpc = VideoPlayerController.networkUrl(
        Uri.parse(proxyUrl),
        formatHint: VideoFormat.hls,
      );
      _videoPlayerController = vpc;

      _videoListener = () {
        if (!mounted) return;
        final value = vpc.value;

        // 缓冲状态
        final isBuffering = value.isBuffering;
        if (isBuffering != _isBuffering) {
          setState(() => _isBuffering = isBuffering);
          if (isBuffering) {
            _startBufferingTimeout();
          } else {
            _cancelBufferingTimeout();
          }
        }

        // 弹幕同步
        if (value.isInitialized) {
          ref.read(danmakuControllerProvider).updatePosition(
            value.position,
            Size(value.size.width, value.size.height),
          );
        }

        // 错误处理
        if (value.hasError) {
          _handleVideoError(value.errorDescription ?? '清晰度切换失败');
        }

        // 播放开始后 seek 到原位置并播放
        if (value.isInitialized && !value.isBuffering && value.position.inMilliseconds < 1000) {
          vpc.seekTo(currentPosition);
          vpc.play();
          ref.read(danmakuControllerProvider).play();
        }

        // 播放完成
        if (value.position >= value.duration && value.duration.inMilliseconds > 0 && value.position.inMilliseconds > 0) {
          _onPlaybackCompleted();
        }

        // 播放开始时清除错误消息
        if (value.isPlaying && _errorMessage != null) {
          _errorDelayTimer?.cancel();
          setState(() { _errorMessage = null; });
        }
      };

      await vpc.initialize();
      vpc.addListener(_videoListener!);

      // 创建新的 ChewieController
      _chewieController = ChewieController(
        videoPlayerController: vpc,
        showControls: false,
        allowedScreenSleep: false,
      );

      // 清晰度切换后重新应用音轨选择
      Future.microtask(() async {
        if (mounted) {
          await ref.read(audioTrackManagerProvider).reapplyAfterQualitySwitch(vpc);
        }
      });

      setState(() {});
    } catch (e) {
      appLogger.e('[Player] 清晰度切换失败', error: e);
      _handleVideoError('清晰度切换失败: $e');
    }
  }

  /// 在 StreamSession 创建后初始化清晰度管理器。
  ///
  /// StreamSession 在视频播放器首次请求 `/hls/{cacheKey}` 时才异步创建，
  /// 因此通过 [VideoCacheProxyServer.onSessionCreated] 回调延迟初始化。
  /// 如果 session 已存在（如重试/切集），回调会立即触发。
  void _initQualityManagerOnSessionReady(String cacheKey, String originalUrl) {
    VideoCacheProxyServer.instance.onSessionCreated(cacheKey, (session) {
      if (!mounted) return;
      if (_currentCacheKey != cacheKey) return; // 已切换到其他剧集，忽略

      if (session.m3u8Info.isMaster && session.m3u8Info.variants.isNotEmpty) {
        _qualityManager ??= ref.read(qualityManagerProvider);
        _qualityManager!.reset();
        _qualityManager!.initialize(
          masterInfo: session.m3u8Info,
          cacheKey: cacheKey,
          originalUrl: originalUrl,
        );
        // 设置切换回调
        _qualityManager!.onSwitchReady = (proxyUrl, position) {
          if (!mounted) return;
          final currentPosition = _videoPlayerController?.value.position ?? Duration.zero;
          _switchToNewQuality(proxyUrl, currentPosition);
        };
        _qualityManager!.onSwitchFailed = (message) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
          );
        };
        // 应用初始清晰度
        Connectivity().checkConnectivity().then((results) {
          if (!mounted) return;
          _qualityManager?.applyInitialQuality(results.first);
        });
        appLogger.i('[Player] 清晰度管理器已初始化: variants=${session.m3u8Info.variants.length}');
      } else {
        // 非 master playlist：设置默认清晰度标识
        _qualityManager ??= ref.read(qualityManagerProvider);
        _qualityManager!.setDefault();
        appLogger.i('[Player] 非 master playlist，设置默认清晰度标识');
      }
    });
  }

  /// 处理视频错误 — 三级容错：自动重试 → 自动切换线路 → 显示错误 UI
  void _handleVideoError(String error) {
    appLogger.e('[Player] 播放异常', error: error);
    appLogger.i('[Player] 当前状态 - playing: ${_videoPlayerController?.value.isPlaying}, buffering: ${_videoPlayerController?.value.isBuffering}, position: ${_videoPlayerController?.value.position}, duration: ${_videoPlayerController?.value.duration}');
    if (!mounted) return;

    // 如果播放器正在播放且实际有进度，说明这是非致命性错误
    if (_videoPlayerController?.value.isPlaying == true) {
      final pos = _videoPlayerController!.value.position;
      final dur = _videoPlayerController!.value.duration;
      final isActuallyPlaying = pos.inMilliseconds > 0 || dur.inMilliseconds > 0 || !_videoPlayerController!.value.isBuffering;
      if (isActuallyPlaying) {
        appLogger.w('[Player] 播放中的非致命错误，忽略: $error');
        return;
      }
      appLogger.w('[Player] 播放中但位置/时长为0且仍在缓冲，视为致命错误: $error');
    }

    appLogger.i('[Player] 错误事件触发，当前索引：sourceIndex=$_currentSourceIndex, epIndex=$_currentEpIndex');

    // 取消之前的延迟确认和自动重试
    _errorDelayTimer?.cancel();
    _autoRetryTimer?.cancel();

    final isRetryable = _isRetryableError(error);
    final isSourceError = _isSourceUnavailableError(error);

    if (isRetryable && _retryCount < _maxRetryCount) {
      // 第一级：可重试错误 + 未超重试上限 → 自动重试（退避策略）
      _retryCount++;
      _isAutoRetrying = true;
      final backoffMs = _retryCount * 2000; // 2s, 4s, 6s 退避
      appLogger.i('[Player] 自动重试 $_retryCount/$_maxRetryCount，${backoffMs}ms 后重试');
      // 关键修复：重试前失效旧 session，强制重新创建。
      // 否则 _getOrCreateSession 会复用旧 session（含可能错误的 _keyCache），
      // 重试拿到的还是同样的错误密钥 -> 同样的 fmt? 错误 -> 重试无效。
      _invalidateCurrentSession();
      setState(() { _errorMessage = null; _isBuffering = true; });
      _autoRetryTimer = Timer(Duration(milliseconds: backoffMs), () {
        if (!mounted) return;
        _playCurrentEpisode();
      });
    } else if (isSourceError || (isRetryable && _retryCount >= _maxRetryCount)) {
      // 第二级：源不可用 或 重试耗尽 → 自动切换线路
      _tryAutoSwitchSource();
    } else {
      // 第三级：不可重试错误 → 快速显示错误 UI
      _errorDelayTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _cancelBufferingTimeout();
        setState(() {
          _isBuffering = false;
          _isAutoRetrying = false;
          _errorMessage = _classifyError(error);
        });
      });
    }
  }

  /// 触发 m3u8 链接检测
  /// 从详情页进入时会由 DetailScreen 触发，从 PlayerScreen 直接进入时在这里触发
  void _triggerM3u8Check() {
    if (_sources.isEmpty) return;
    final allUrls = <String>[];
    for (final source in _sources) {
      for (final ep in source.episodes) {
        if (ep.url.isNotEmpty) allUrls.add(ep.url);
      }
    }
    if (allUrls.isNotEmpty) {
      appLogger.i('[Player] 触发 m3u8 检测: ${allUrls.length} 个 URL');
      ref.read(m3u8CheckProvider.notifier).checkUrls(allUrls);
    }
  }

  /// 写入播放历史（含完整信息）
  void _upsertPlayHistory() {
    if (_detail == null) return;
    ref.read(historyProvider.notifier).upsertHistory(
      vodId: widget.vodId,
      vodName: _detail!.vodName,
      vodPic: _detail!.vodPic ?? '',
      resourceDomain: _detail!.resourceDomain,
      resourceName: _detail!.resourceName,
      groupKey: '',
      sourceIndex: _currentSourceIndex,
      epIndex: _currentEpIndex,
      epName: _currentEpName,
    );
  }

  /// 获取历史播放进度并设置续播位置。
  ///
  /// 由 [_playCurrentEpisode] await 调用，确保在创建 ChewieController 之前
  /// _resumePositionSeconds 已设置，这样：
  /// - ChewieController 的 autoPlay 可根据是否有续播位置正确判断
  /// - videoListener 的续播分支在 VPC isInitialized 时能正确触发 seek
  ///
  /// 失败时静默返回，保证续播失败不影响正常播放（从头播放）。
  Future<void> _fetchAndApplyResumePosition() async {
    try {
      final item = await _historyNotifier.getPlayHistory(
        vodId: widget.vodId,
        resourceDomain: widget.resourceDomain,
        epIndex: _currentEpIndex,
      );
      if (!mounted) return;
      if (item == null) {
        appLogger.i('[Player] 无历史记录，从头播放');
        return;
      }

      // 进度 >95% 视为已看完，不恢复位置（与 Web 端 SKIP_RESTORE_THRESHOLD 对齐）
      const skipRestoreThreshold = 95;
      if (item.progress > skipRestoreThreshold) {
        appLogger.i('[Player] 进度 ${item.progress.toStringAsFixed(1)}% > $skipRestoreThreshold%，视为已看完，跳过续播');
        return;
      }

      final currentTime = item.currentTime.toInt();
      if (currentTime <= 0) {
        appLogger.i('[Player] 历史进度 currentTime=$currentTime，无需续播');
        return;
      }

      // 设置续播位置，后续由 videoListener 在 VPC isInitialized 时执行 seek
      _resumePositionSeconds = currentTime;
      appLogger.i('[Player] 续播位置已设置: ${currentTime}s, progress=${item.progress.toStringAsFixed(1)}%, duration=${item.duration}s');
    } catch (e) {
      appLogger.w('[Player] 获取续播位置失败，将从开头播放', error: e);
    }
  }

  /// 执行续播 seek 并标记已完成。
  void _applyResumeSeek(VideoPlayerController vpc, int seconds) {
    _resumeSeeked = true;
    final target = Duration(seconds: seconds);

    // 通知位置守护系统：这是合法的 seek 操作，不是异常跳回
    // 与 _onUserSeek() 保持一致，防止 _checkPositionGuard 将续播纠正回起始位置
    _userSeekTarget = target;
    _lastResetTime = DateTime.now();
    _positionResetCount = 0;
    // 预设稳定位置到 seek 目标，防止守护把续播纠正回去
    _lastStablePosition = target;

    vpc.seekTo(target).then((_) {
      // seek 完成后开始播放（续播时 autoPlay=false，需手动播放）
      if (mounted) {
        vpc.play();
        appLogger.i('[Player] 续播 seek 完成，开始播放');
      }
    });
    appLogger.i('[Player] 续播 seek 到: ${seconds}s');
  }

  /// 检查当前剧集是否有已下载的本地文件。
  ///
  /// 参考 Web 端 PlayPage.tsx 的 checkDownload 逻辑：
  /// - MP4 格式：使用服务器流 `/api/download/file/:id?token=xxx` 播放
  /// - TS 格式：回退到远程流（不支持 TS 容器直接播放）
  /// - 未找到：使用远程原始 URL
  Future<void> _checkLocalDownload() async {
    if (_detail == null) {
      _resetLocalState();
      return;
    }
    final resourceDomain = _detail!.resourceDomain;
    if (resourceDomain.isEmpty) {
      _resetLocalState();
      return;
    }

    final seq = ++_checkDownloadSeq;
    // 立即标记为检查中，并清空本地文件 URL
    setState(() {
      _checkingLocal = true;
      _localFileUrl = null;
    });

    try {
      final downloadNotifier = ref.read(downloadProvider.notifier);
      final resp = await downloadNotifier.checkDownload(
        resourceDomain: resourceDomain,
        vodId: widget.vodId,
        sourceIndex: _currentSourceIndex,
        epIndex: _currentEpIndex,
      );

      if (seq != _checkDownloadSeq || !mounted) return;

      if (resp != null && resp.found && resp.taskId > 0 && resp.fileFormat == 'mp4') {
        appLogger.i('[Player] 本地 MP4 文件已找到, task_id: ${resp.taskId}');
        final fileUrl = await downloadNotifier.getDownloadFileUrl(resp.taskId);
        if (seq != _checkDownloadSeq || !mounted) return;
        setState(() {
          _localFileUrl = fileUrl;
          _localFileFormat = 'mp4';
          _checkingLocal = false;
        });
      } else if (resp != null && resp.found && resp.fileFormat == 'ts') {
        appLogger.i('[Player] 本地文件为 TS 格式，回退远程流, task_id: ${resp.taskId}');
        setState(() {
          _localFileUrl = null;
          _localFileFormat = 'ts';
          _checkingLocal = false;
        });
      } else {
        appLogger.i('[Player] 未找到本地下载文件');
        setState(() {
          _localFileUrl = null;
          _localFileFormat = 'mp4';
          _checkingLocal = false;
        });
      }
    } catch (e) {
      if (seq != _checkDownloadSeq || !mounted) return;
      appLogger.e('[Player] checkDownload 失败', error: e);
      setState(() {
        _localFileUrl = null;
        _localFileFormat = 'mp4';
        _checkingLocal = false;
      });
    }
  }

  void _resetLocalState() {
    _localFileUrl = null;
    _localFileFormat = 'mp4';
    _checkingLocal = false;
  }

  /// 上报当前播放进度（复用定时上报逻辑）
  void _reportCurrentProgress() {
    if (_detail == null) return;
    final vpc = _videoPlayerController;
    if (vpc == null) return;
    final dur = vpc.value.duration;
    final pos = vpc.value.position;
    if (dur.inSeconds == 0) return;
    _historyNotifier.reportProgress(
      vodId: widget.vodId,
      vodName: _detail?.vodName ?? '',
      vodPic: _detail?.vodPic ?? '',
      resourceDomain: widget.resourceDomain,
      resourceName: _detail?.resourceName ?? '',
      groupKey: '',
      sourceIndex: _currentSourceIndex,
      epIndex: _currentEpIndex,
      epName: _currentEpName,
      progress: (pos.inSeconds / dur.inSeconds * 100).clamp(0.0, 100.0),
      currentTime: pos.inSeconds,
      duration: dur.inSeconds,
    );
  }

  void _startProgressReporting() {
    _progressTimer?.cancel();
    // 立即上报一次进度，避免用户在 30 秒内退出时进度完全丢失
    _reportCurrentProgress();
    _progressTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) {
        _progressTimer?.cancel();
        return;
      }
      _reportCurrentProgress();
    });
  }

  String get _currentEpName {
    if (_sources.isEmpty) return '';
    final si = _currentSourceIndex.clamp(0, _sources.length - 1);
    final source = _sources[si];
    if (source.episodes.isEmpty) return '';
    return source.episodes[_currentEpIndex.clamp(0, source.episodes.length - 1)].name;
  }

  int get _currentEpCount {
    if (_sources.isEmpty) return 0;
    final si = _currentSourceIndex.clamp(0, _sources.length - 1);
    return _sources[si].episodes.length;
  }

  String get _playerTitleComputed {
    final vodName = _detail?.vodName ?? '';
    final epName = _currentEpName;
    if (vodName.isNotEmpty && epName.isNotEmpty) return '$vodName - $epName';
    return vodName.isNotEmpty ? vodName : epName;
  }

  void _selectEpisode(int sourceIndex, int epIndex) {
    appLogger.i('[Player] _selectEpisode 调用: sourceIndex=$sourceIndex, epIndex=$epIndex');
    appLogger.i('[Player] _selectEpisode 当前状态: sourceIndex=$_currentSourceIndex, epIndex=$_currentEpIndex');
    if (sourceIndex == _currentSourceIndex && epIndex == _currentEpIndex) {
      appLogger.i('[Player] _selectEpisode: 相同索引，early return');
      return;
    }
    setState(() {
      _currentSourceIndex = sourceIndex;
      _currentEpIndex = epIndex;
      // 用户主动切换剧集时重置重试和线路切换状态
      _retryCount = 0;
      _autoSwitchAttempt = 0;
      _isAutoRetrying = false;
      appLogger.i('[Player] _selectEpisode setState 完成: 新索引 sourceIndex=$_currentSourceIndex, epIndex=$_currentEpIndex');
    });

    // 投屏中切集：在远端加载新媒体，不重建本地播放器
    final castService = ref.read(castServiceProvider);
    if (castService.isCasting) {
      _switchCastEpisode();
      return;
    }

    // 切换剧集时先检查本地下载，完成后再播放
    _checkLocalDownload().then((_) => _playCurrentEpisode());
  }

  /// 投屏中切集：在远端会话中加载新集媒体
  Future<void> _switchCastEpisode() async {
    if (_sources.isEmpty) return;
    final si = _currentSourceIndex.clamp(0, _sources.length - 1);
    final source = _sources[si];
    if (source.episodes.isEmpty) return;
    final ei = _currentEpIndex.clamp(0, source.episodes.length - 1);
    final episode = source.episodes[ei];

    // 更新标题
    _playerTitle = _playerTitleComputed;

    // 使用远程原始 URL（非本机代理地址）
    final castUrl = episode.url;
    _currentCastUrl = castUrl;

    if (castUrl.isEmpty) {
      appLogger.w('[Player] 投屏切集：无可用的远程 URL');
      return;
    }

    final media = CastMedia(
      url: castUrl,
      type: _detectCastMediaType(castUrl),
      title: _playerTitle,
    );

    appLogger.i('[Player] 投屏切集: url=$castUrl, title=$_playerTitle');
    final castService = ref.read(castServiceProvider);
    await castService.loadMedia(media);

    // 更新本地播放历史
    _upsertPlayHistory();
    setState(() {}); // 刷新 UI 标题
  }

  /// 播放完成时的处理，根据连播模式决定下一步行为
  void _onPlaybackCompleted() {
    appLogger.i('[Player] _onPlaybackCompleted 开始 - 当前索引：sourceIndex=$_currentSourceIndex, epIndex=$_currentEpIndex');

    final vpc = _videoPlayerController;
    if (vpc == null) return;
    final pos = vpc.value.position;
    final dur = vpc.value.duration;

    appLogger.i('[Player] 当前状态 - position: $pos, duration: $dur');

    // 防护：播放位置为0且时长为0时，说明播放并未真正完成
    if (pos.inMilliseconds == 0 && dur.inMilliseconds == 0) {
      appLogger.w('[Player] 播放位置和时长均为0，忽略completed事件（可能是播放失败）');
      return;
    }

    final playMode = ref.read(playModeProvider);
    appLogger.i('[Player] 播放模式: $playMode');

    switch (playMode) {
      case PlayMode.autoNext:
        appLogger.i('[Player] 自动连播模式，调用 _playNextEpisode');
        _playNextEpisode();
        break;
      case PlayMode.pauseOnEnd:
        // 播完暂停 — 默认行为
        break;
      case PlayMode.loopSingle:
        vpc.seekTo(Duration.zero);
        vpc.play();
        ref.read(danmakuControllerProvider).play();
        break;
    }
  }

  /// 自动播放下一集
  void _playNextEpisode() {
    appLogger.i('[Player] _playNextEpisode 开始 - 当前索引：sourceIndex=$_currentSourceIndex, epIndex=$_currentEpIndex');
    if (_sources.isEmpty) {
      appLogger.w('[Player] _playNextEpisode: 无播放源，返回');
      return;
    }
    final si = _currentSourceIndex.clamp(0, _sources.length - 1);
    final source = _sources[si];
    if (source.episodes.isEmpty) {
      appLogger.w('[Player] _playNextEpisode: 播放源无剧集，返回');
      return;
    }
    appLogger.i('[Player] _playNextEpisode: 当前剧集总数=${source.episodes.length}');
    if (_currentEpIndex < source.episodes.length - 1) {
      appLogger.i('[Player] _playNextEpisode: 切换到下一集，从 $_currentEpIndex 到 ${_currentEpIndex + 1}');
      _selectEpisode(_currentSourceIndex, _currentEpIndex + 1);
    } else {
      appLogger.i('[Player] _playNextEpisode: 已是最后一集，不做操作');
    }
  }

  void _startBufferingTimeout() {
    _cancelBufferingTimeout();
    appLogger.i('[Player] _startBufferingTimeout 启动 - 当前 _isBuffering: $_isBuffering');
    _bufferingTimeout = Timer(const Duration(seconds: 15), () {
      if (!mounted || !_isBuffering) {
        appLogger.i('[Player] 缓冲超时回调跳过 - mounted: $mounted, _isBuffering: $_isBuffering');
        return;
      }
      appLogger.i('[Player] 缓冲超时，设置错误消息');
      setState(() {
        _isBuffering = false;
        _errorMessage = '视频加载超时，链接可能不可用';
      });
    });
  }

  void _cancelBufferingTimeout() {
    appLogger.i('[Player] _cancelBufferingTimeout 调用 - 当前 _bufferingTimeout: ${_bufferingTimeout != null ? "存在" : "null"}, _isBuffering: $_isBuffering');
    _bufferingTimeout?.cancel();
    _bufferingTimeout = null;
  }

  String _classifyError(String error) {
    final e = error.toLowerCase();
    if (e.contains('connection timed out') || e.contains('timed out')) {
      return '连接超时，请检查网络后重试';
    }
    if (e.contains('connection refused') || e.contains('could not connect')) {
      return '无法连接服务器，链接可能已失效';
    }
    if (e.contains('403') || e.contains('forbidden')) {
      return '访问被拒绝，链接已过期或无权限';
    }
    if (e.contains('404') || e.contains('not found')) {
      return '视频资源不存在，链接已失效';
    }
    if (e.contains('dns') || e.contains('name resolution') || e.contains('could not resolve')) {
      return '域名解析失败，请检查网络连接';
    }
    if (e.contains('tcp') || e.contains('network') || e.contains('socket')) {
      return '网络连接失败，请检查网络后重试';
    }
    if (e.contains('no such file') || e.contains('file not found')) {
      return '视频文件不存在，链接已失效';
    }
    if (e.contains('decoder') || e.contains('codec') || e.contains('format')) {
      return '视频格式不支持或解码失败';
    }
    // iOS CoreMedia 格式错误（fmt? / kCMFormatDescriptionError_InvalidFormat）
    // 常见于加密 HLS 密钥获取异常，AVPlayer 用错误密钥解密后无法识别 TS 格式
    if (e.contains('coremedia') || e.contains('fmt?') || e.contains('1718449215')) {
      return '视频格式解析失败，可能加密密钥获取异常，请重试或切换线路';
    }
    // ExoPlayer Source error - 源加载失败
    if (e.contains('source error')) {
      return '视频源加载失败，请尝试其他线路';
    }
    if (e.contains('unrecognized') || e.contains('data source')) {
      return '视频源无法识别，请尝试其他线路';
    }
    // Android 明文 HTTP 被禁止（本地代理需要 network_security_config）
    if (e.contains('cleartext') && e.contains('not permitted')) {
      return '本地代理连接被拒绝，请更新应用配置';
    }
    return '播放失败，请尝试其他线路';
  }

  /// 判断是否为可自动重试的错误（临时性网络错误）。
  bool _isRetryableError(String error) {
    final e = error.toLowerCase();
    // iOS CoreMedia 格式错误 - 可能是密钥获取临时异常，重试可重新获取密钥
    if (e.contains('coremedia') || e.contains('fmt?') || e.contains('1718449215')) return true;
    // TCP 连接/读取错误
    if (e.contains('tcp:') || e.contains('ffurl_read')) return true;
    // TLS/SSL 握手错误
    if (e.contains('tls:') || e.contains('ssl_handshake') || e.contains('mbedtls')) return true;
    // 文件缓存创建失败（通常是临时状态）
    if (e.contains('file cache')) return true;
    // 通用 I/O 错误
    if (e.contains('i/o error')) return true;
    // 网络不可达/重置（会自动重连）
    if (e.contains('connection reset') || e.contains('network is unreachable')) return true;
    // video_player 特有的源初始化错误（排除 ExoPlayer 的 Source error）
    if (e.contains('unrecognized') || e.contains('data source')) return true;
    // ExoPlayer 连接超时（与 Source error 不同，这是可重试的）
    if (e.contains('connecttimeout') || e.contains('connectiontimeout')) return true;
    return false;
  }

  /// 判断是否为源不可用错误（线路级别，需要切换线路）。
  bool _isSourceUnavailableError(String error) {
    final e = error.toLowerCase();
    // ExoPlayer Source error - 源加载失败
    if (e.contains('source error')) return true;
    // HTTP 403/404 - 链接失效
    if (e.contains('403') || e.contains('forbidden')) return true;
    if (e.contains('404') || e.contains('not found')) return true;
    // Android 明文 HTTP 被禁止（配置问题，非重试可解决）
    if (e.contains('cleartext') && e.contains('not permitted')) return true;
    return false;
  }

  /// 失效当前代理缓存 session，强制下次播放时重新创建。
  ///
  /// 关键修复：重试/切换线路前必须调用，否则 _getOrCreateSession 会复用
  /// 旧 session（含可能错误的 _keyCache），重试拿到同样的错误密钥 -> 同样的
  /// fmt? 错误 -> 重试无效。unregister 会移除 _sessions 中的旧 session 并 stop。
  void _invalidateCurrentSession() {
    if (_currentCacheKey != null) {
      appLogger.i('[Player] 失效旧 session: cacheKey=$_currentCacheKey');
      VideoCacheProxyServer.instance.unregister(_currentCacheKey!);
      _currentCacheKey = null;
    }
  }

  /// 自动切换到下一个播放源
  void _tryAutoSwitchSource() {
    _invalidateCurrentSession(); // 切换线路前失效旧 session
    _retryCount = 0; // 重置重试计数
    _autoSwitchAttempt++;

    if (_sources.length > 1 && _autoSwitchAttempt < _sources.length) {
      // 切换到下一个线路
      final nextSourceIndex = (_currentSourceIndex + 1) % _sources.length;
      appLogger.i('[Player] 自动切换线路: $_currentSourceIndex -> $nextSourceIndex (第 $_autoSwitchAttempt 次切换)');
      _isAutoRetrying = true;
      setState(() { _errorMessage = null; _isBuffering = true; });
      _selectEpisode(nextSourceIndex, _currentEpIndex);
    } else {
      // 所有线路都尝试过 → 显示错误 UI
      appLogger.w('[Player] 所有线路均已尝试失败');
      _cancelBufferingTimeout();
      setState(() {
        _isBuffering = false;
        _isAutoRetrying = false;
        _autoSwitchAttempt = 0;
        _errorMessage = '所有线路均不可用，请稍后重试';
      });
    }
  }

  /// 位置守护：检测异常跳回并自动纠正
  void _checkPositionGuard(Duration pos) {
    if (!Platform.isAndroid || !_isM3u8Url) return;
    final vpc = _videoPlayerController;
    if (vpc == null) return;
    // 忽略暂停/缓冲期间的位置变化
    if (!vpc.value.isPlaying || vpc.value.isBuffering) return;

    final now = DateTime.now();

    // 如果用户刚主动 seek 过，跳过守护检测（给 seek 操作 2 秒窗口）
    if (_userSeekTarget != null) {
      // 续播 seek 给更长窗口（5秒），因为 HLS 流缓冲/分片加载可能导致位置短暂跳回；
      // 用户手动 seek 保持 2 秒窗口即可
      final elapsed = now.difference(_lastResetTime ?? now);
      final seekWindowSeconds = _resumeSeeked ? 5 : 2;
      if (elapsed.inSeconds < seekWindowSeconds) {
        // 在 seek 窗口期内，只更新稳定位置到 seek 目标附近
        if (pos.inSeconds >= _userSeekTarget!.inSeconds - 2) {
          _lastStablePosition = pos;
          _positionResetCount = 0;
        }
        return;
      }
      // 窗口期结束，清除 seek 目标
      _userSeekTarget = null;
    }

    // 检测1：大幅跳回 — 当前位置比上次稳定位置少了5秒以上
    if (_lastStablePosition != null &&
        pos.inSeconds > 0 &&
        _lastStablePosition!.inSeconds > 5 &&
        pos.inSeconds < _lastStablePosition!.inSeconds - 5) {
      appLogger.w('[Player] 检测到异常进度大幅跳回: $_lastStablePosition -> $pos, 自动纠正');
      vpc.seekTo(_lastStablePosition!);
      return;
    }

    // 检测2：循环跳回起始 — 位置回到 0-5 秒范围，但之前已播放超过 10 秒
    if (_lastStablePosition != null &&
        _lastStablePosition!.inSeconds > 10 &&
        pos.inSeconds >= 0 &&
        pos.inSeconds < 5) {
      if (_lastResetTime != null &&
          now.difference(_lastResetTime!).inSeconds < 30) {
        _positionResetCount++;
      } else {
        _positionResetCount = 1;
      }
      _lastResetTime = now;

      if (_positionResetCount >= 2) {
        appLogger.w('[Player] 检测到 m3u8 循环跳回起始: '
            'resetCount=$_positionResetCount, '
            'lastStable=$_lastStablePosition -> $pos, '
            '自动纠正到 ${_lastStablePosition! + const Duration(seconds: 1)}');
        vpc.seekTo(_lastStablePosition! + const Duration(seconds: 1));
        _positionResetCount = 0;
        return;
      }

      appLogger.i('[Player] m3u8 位置跳回起始（第 $_positionResetCount 次）: '
          '$_lastStablePosition -> $pos');
    }

    // 更新稳定位置（只向前更新）
    if (pos.inSeconds > (_lastStablePosition?.inSeconds ?? 0)) {
      _lastStablePosition = pos;
      if (pos.inSeconds > 10) {
        _positionResetCount = 0;
      }
    }
  }

  /// 打开下载剧集选择弹窗
  void _onDownload() {
    if (_detail == null || _sources.isEmpty) return;
    final si = _currentSourceIndex.clamp(0, _sources.length - 1);
    final source = _sources[si];
    if (source.episodes.isEmpty) return;
    final ei = _currentEpIndex.clamp(0, source.episodes.length - 1);

    DownloadEpisodeDialog.show(
      context,
      sources: _sources,
      defaultSourceIndex: si,
      defaultEpIndex: ei,
      vodId: widget.vodId,
      vodName: _detail!.vodName,
      vodPic: _detail!.vodPic,
      resourceDomain: _detail!.resourceDomain,
      resourceName: source.name,
      groupKey: '',
    );
  }

  Future<void> _onEnterFullscreen(FullscreenMode mode) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []);
      if (mode == FullscreenMode.portrait) {
        await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        _pushPortraitFullscreenRoute();
      } else {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        _pushLandscapeFullscreenRoute();
      }
    } catch (e) {
      appLogger.e('[Player] 设置全屏方向失败', error: e);
    }
  }

  /// 全屏模式直接切换（不经过非全屏中间状态）
  Future<void> _switchFullscreenMode(FullscreenMode targetMode) async {
    try {
      final currentMode = BilibiliControls.currentFullscreenMode;
      if (currentMode == targetMode) return;

      // 防止 pop 触发 onExitFullscreen
      _isRestoringFromFullscreen = true;

      if (currentMode == FullscreenMode.portrait && targetMode == FullscreenMode.landscape) {
        // 竖屏→横屏：先 pop 竖屏路由，再直接进入横屏全屏
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        BilibiliControls.currentFullscreenMode = FullscreenMode.landscape;
        _pushLandscapeFullscreenRoute();
      } else if (currentMode == FullscreenMode.landscape && targetMode == FullscreenMode.portrait) {
        // 横屏→竖屏：先 pop 横屏路由，再直接进入竖屏全屏
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        BilibiliControls.currentFullscreenMode = FullscreenMode.portrait;
        _pushPortraitFullscreenRoute();
      }

      // 短暂延迟后重置标志
      Future.delayed(const Duration(milliseconds: 500), () {
        _isRestoringFromFullscreen = false;
      });
    } catch (e) {
      _isRestoringFromFullscreen = false;
      appLogger.e('[Player] 全屏模式切换失败', error: e);
    }
  }

  /// 推入竖屏全屏自定义路由
  void _pushPortraitFullscreenRoute() {
    final cc = _chewieController;
    if (cc == null) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => _PortraitFullscreenPage(
          chewieControllerNotifier: _chewieControllerNotifier,
          title: _playerTitle,
          onExitFullscreen: _onExitFullscreen,
          onEnterFullscreen: _onEnterFullscreen,
          onSwitchFullscreenMode: _switchFullscreenMode,
          onUserSeek: _onUserSeek,
          onAspectRatioChange: _onAspectRatioChange,
          onCastDevice: _startCasting,
          onCastDisconnect: _stopCasting,
          onPreviousEpisode: () => _selectEpisode(_currentSourceIndex, _currentEpIndex - 1),
          onNextEpisode: () => _selectEpisode(_currentSourceIndex, _currentEpIndex + 1),
          canPrevious: _currentEpIndex > 0,
          canNext: _currentEpIndex < _currentEpCount - 1,
        ),
        opaque: true,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  /// 推入横屏全屏自定义路由
  void _pushLandscapeFullscreenRoute() {
    final cc = _chewieController;
    if (cc == null) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => _LandscapeFullscreenPage(
          chewieControllerNotifier: _chewieControllerNotifier,
          title: _playerTitle,
          onExitFullscreen: _onExitFullscreen,
          onEnterFullscreen: _onEnterFullscreen,
          onSwitchFullscreenMode: _switchFullscreenMode,
          onUserSeek: _onUserSeek,
          onAspectRatioChange: _onAspectRatioChange,
          onCastDevice: _startCasting,
          onCastDisconnect: _stopCasting,
          onPreviousEpisode: () => _selectEpisode(_currentSourceIndex, _currentEpIndex - 1),
          onNextEpisode: () => _selectEpisode(_currentSourceIndex, _currentEpIndex + 1),
          canPrevious: _currentEpIndex > 0,
          canNext: _currentEpIndex < _currentEpCount - 1,
        ),
        opaque: true,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  /// 退出全屏恢复系统方向和 UI
  /// 幂等保护：防止全屏页面退出时 onExitFullscreen 被多次调用
  Future<void> _onExitFullscreen() async {
    if (_isRestoringFromFullscreen) return;
    _isRestoringFromFullscreen = true;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      await SystemChrome.setPreferredOrientations([]);
      BilibiliControls.currentFullscreenMode = null;
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      appLogger.e('[Player] 退出全屏恢复方向失败', error: e);
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        _isRestoringFromFullscreen = false;
      });
    }
  }

  /// 画面比例变更处理
  void _onAspectRatioChange(DisplayAspectRatio ratio) {
    final cc = _chewieController;
    if (cc == null) return;

    final newAspectRatio = _computeAspectRatio(ratio, cc);
    final newController = cc.copyWith(aspectRatio: newAspectRatio);
    _chewieController = newController;
    _chewieControllerNotifier.value = newController;
    setState(() {});
  }

  @override
  void dispose() {
    _castStateSub?.cancel();
    _cancelBufferingTimeout();
    _errorDelayTimer?.cancel();
    _autoRetryTimer?.cancel();
    // 退出前最后一次上报进度（fire-and-forget，Dio 请求不依赖 widget 生命周期）
    final vpc = _videoPlayerController;
    if (vpc != null && vpc.value.duration.inSeconds > 0) {
      appLogger.i('[Player] dispose 上报进度: position=${vpc.value.position.inSeconds}s, duration=${vpc.value.duration.inSeconds}s');
    }
    _reportCurrentProgress();
    _progressTimer?.cancel();
    _chewieControllerNotifier.dispose();
    // 暂停所有活跃的自动缓存（标记为 paused，不影响手动缓存）
    VideoCacheProxyServer.instance.pauseActiveProxying();
    // 停止所有方案B后台缓存下载
    PlayCacheDownloadService.instance.stopAutoDownloads();
    // 恢复系统自动亮度（用户可能在播放器中手动调节了亮度）
    if (Platform.isIOS || Platform.isAndroid) {
      try {
        ScreenBrightness().resetApplicationScreenBrightness();
      } catch (_) {
        // 恢复失败时忽略
      }
    }
    // dispose 中重置 ChangeNotifier 状态时使用 notify: false，
    // 因为 widget 正在销毁，无需通知 UI 重建；
    // 若触发 notifyListeners 会导致 Riverpod 抛出
    // "Tried to modify a provider while the widget tree was building" 断言错误。
    //
    // 注意：dispose 中不能使用 ref.read（element 已 defunct），
    // 改用 initState 中缓存的 provider 引用。
    try {
      _detachVideoListener();
      // 主动断开 PlaybackController 与当前 VPC 的监听链。
      // 必须在 super.dispose 之前执行：此时 PlaybackController 仍 active，
      // _onLocalControllerChanged 会被触发，正确地从旧 VPC removeListener，
      // 避免下方 _releaseVideoControllers 中的 pause 触发 _syncFromLocal ->
      // notifyListeners 导致 Riverpod 在 widget 树 unmount 期间抛出
      // "Tried to modify a provider while the widget tree was building"。
      globalChewieNotifier.value = null;
      _danmakuController.reset(notify: false);
      _audioTrackManager.reset(notify: false);
      _qualityManager?.reset(notify: false);
      _captureManager.reset(notify: false);
    } catch (e) {
      appLogger.e('[Player] dispose 同步清理异常（将继续释放视频控制器）', error: e);
    }
    super.dispose();
    // 异步释放视频控制器原生资源：平台层释放不通过 ref.watch 通知 element，
    // 即使 element 已 defunct 也安全。
    // 此步骤必须执行，否则后台继续播放声音。
    _releaseVideoControllers();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // 监听字幕状态变化，同步到原生渲染桥
    // 注意：ref.listen 只能在 build 方法内使用，不能放在 initState/_initPlayer 中，
    // 否则会触发 'debugDoingBuild' 断言失败（ref.listen can only be used within the build method）。
    // 放在 build 中时：首次 build 不会立即触发回调，仅监听后续变化（与原意图一致）；
    // widget 销毁时 Riverpod 会自动取消订阅，无需手动管理。
    ref.listen(subtitleManagerProvider, (previous, next) {
      if (previous?.activeTrack != next.activeTrack) {
        final bridge = SubtitleRenderBridge();
        if (next.activeTrack == null) {
          bridge.clearSubtitle();
        } else if (next.activeTrack!.source == SubtitleSource.embedded) {
          final trackIndex = next.embeddedTracks.where(
            (t) => 'embedded_${t.index}' == next.activeTrack!.id,
          ).firstOrNull?.index ?? 0;
          bridge.selectEmbeddedTrack(trackIndex);
        } else if (next.activeTrack!.source == SubtitleSource.external ||
                   next.activeTrack!.source == SubtitleSource.online) {
          bridge.loadExternalSubtitle(next.activeTrack!.cues, offsetMs: next.offsetMs);
        }
      }
      if (previous?.offsetMs != next.offsetMs && next.activeTrack != null) {
        SubtitleRenderBridge().updateOffset(next.offsetMs);
      }
    });

    return Scaffold(backgroundColor: colors.background, body: Column(children: [
      _buildPlayerArea(),
      Expanded(child: _isLoadingDetail ? Center(child: CircularProgressIndicator(color: colors.primary)) : _detail == null ? _buildErrorView() : _buildContentBelow()),
    ]));
  }

  Widget _buildPlayerArea() {
    final colors = context.colors;
    return Container(color: colors.background, child: SafeArea(bottom: false, child: AspectRatio(aspectRatio: 16 / 9, child: Stack(alignment: Alignment.center, children: [
      if (_chewieController != null && _isPlayerInitialized)
        Chewie(controller: _chewieController!)
      else
        Center(child: CircularProgressIndicator(color: colors.primary)),
      if (_chewieController != null && _isPlayerInitialized) ...[
        // 投屏时显示 CastConnectingOverlay 替代 BilibiliControls
        if (ref.watch(playbackControllerProvider).state.isCasting)
          CastConnectingOverlay(
            title: _playerTitle,
            onDisconnect: _stopCasting,
            onPreviousEpisode: () => _selectEpisode(_currentSourceIndex, _currentEpIndex - 1),
            onNextEpisode: () => _selectEpisode(_currentSourceIndex, _currentEpIndex + 1),
            canPrevious: _currentEpIndex > 0,
            canNext: _currentEpIndex < _currentEpCount - 1,
          )
        else
          BilibiliControls(
            chewieController: _chewieController!,
            onEnterFullscreen: _onEnterFullscreen,
            onExitFullscreen: _onExitFullscreen,
            onSwitchFullscreenMode: _switchFullscreenMode,
            onUserSeek: _onUserSeek,
            onAspectRatioChange: _onAspectRatioChange,
            onCastDevice: _startCasting,
            onCastDisconnect: _stopCasting,
            title: _playerTitle,
          ),
      ],
      if (_errorMessage != null && !_isLoadingDetail)
        Container(
          color: colors.background.withValues(alpha: 1.0),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, color: colors.error, size: 40),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: TextStyle(color: colors.textInverse, fontSize: 14), textAlign: TextAlign.center),
            if (_isAutoRetrying) ...[
              const SizedBox(height: 8),
              Text(
                '正在重试 $_retryCount/$_maxRetryCount...',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ] else if (_autoSwitchAttempt > 0) ...[
              const SizedBox(height: 8),
              Text(
                '已尝试 $_autoSwitchAttempt 个线路',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _buildOverlayButton('重试', colors.primary, colors.textInverse, _retryPlay),
              const SizedBox(width: 12),
              _buildOverlayButton('返回', colors.elevated, colors.textSecondary, () => context.pop()),
            ]),
          ]),
        ),
    ]))));
  }

  Widget _buildOverlayButton(String text, Color bg, Color fg, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _retryPlay() {
    appLogger.i('[Player] _retryPlay 调用 - 当前状态: _isBuffering=$_isBuffering, _errorMessage=$_errorMessage');
    _cancelBufferingTimeout();
    _autoRetryTimer?.cancel();
    // 手动重试也失效旧 session，强制重新创建（避免复用错误密钥缓存）
    _invalidateCurrentSession();
    setState(() { _errorMessage = null; _isBuffering = false; _retryCount = 0; _autoSwitchAttempt = 0; _isAutoRetrying = false; });
    _playCurrentEpisode();
  }

  // ── 投屏控制 ──────────────────────────────────────────────────────────────

  /// 投屏启动：暂停本地播放，记录断点位置，连接远端设备并从断点续投
  Future<void> _startCasting(CastDevice device) async {
    appLogger.i('[Player] 投屏启动: device=${device.name}');

    // 1. 记录当前本地播放位置（断点续投）
    final currentPosition = _videoPlayerController?.value.position ?? Duration.zero;

    // 2. 暂停本地播放
    _chewieController?.pause();
    ref.read(danmakuControllerProvider).pause();
    appLogger.i('[Player] 本地播放已暂停，断点位置: $currentPosition');

    // 3. 构建投屏媒体 URL
    //    - 代理模式启用 + 当前使用方案B代理缓存：启动 LAN 代理，使用 LAN IP URL
    //    - 否则：使用远程原始 URL
    String castUrl = _currentCastUrl;
    final castProxyState = ref.read(castProxyProvider);
    if (castProxyState.enabled && castProxyState.selectedIp.isNotEmpty && _currentCacheKey != null) {
      try {
        // 启动 LAN 代理服务器（绑定 0.0.0.0）
        await VideoCacheProxyServer.instance.startLan();
        final lanIp = castProxyState.selectedIp;
        castUrl = VideoCacheProxyServer.instance.lanHlsProxyUrl(_currentCacheKey!, lanIp);
        appLogger.i('[Player] 投屏使用代理模式: lanIp=$lanIp, castUrl=$castUrl');
      } catch (e) {
        appLogger.e('[Player] LAN 代理启动失败，回退使用远程 URL', error: e);
        castUrl = _currentCastUrl;
      }
    }

    if (castUrl.isEmpty) {
      appLogger.w('[Player] 无可投屏的 URL');
      return;
    }

    final media = CastMedia(
      url: castUrl,
      type: _detectCastMediaType(castUrl),
      title: _playerTitle,
      startPosition: currentPosition.inMilliseconds > 0 ? currentPosition : null,
    );

    // 4. 连接设备并开始投屏
    final castService = ref.read(castServiceProvider);
    await castService.connectAndPlay(device, media);
    appLogger.i('[Player] 投屏已启动: url=$castUrl, startPosition=$currentPosition');
  }

  /// 投屏断开：断开远端连接，从远端最后位置恢复本地播放
  Future<void> _stopCasting() async {
    appLogger.i('[Player] 投屏断开（用户主动）');

    // 标记为用户主动断开，防止 _listenCastState 触发意外断线回退
    _userInitiatedDisconnect = true;

    // 1. 记录远端最后播放位置
    final castService = ref.read(castServiceProvider);
    final castPosition = castService.castPosition;

    // 2. 断开远端连接
    await castService.disconnect();

    // 3. 从远端最后位置恢复本地播放
    if (castPosition.inMilliseconds > 0 && _chewieController != null) {
      appLogger.i('[Player] 从投屏断点恢复本地播放: position=$castPosition');
      _chewieController!.seekTo(castPosition);
      _chewieController!.play();
      ref.read(danmakuControllerProvider).play();
    } else {
      // 无有效位置，直接恢复播放
      _chewieController?.play();
      ref.read(danmakuControllerProvider).play();
    }
  }

  /// 根据 URL 判断投屏媒体类型
  CastMediaType _detectCastMediaType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') || lower.contains('/hls/')) {
      return CastMediaType.hls;
    }
    if (lower.contains('.mkv')) {
      return CastMediaType.mkv;
    }
    if (lower.contains('.ts') && !lower.contains('.m3u8')) {
      return CastMediaType.mpegTs;
    }
    // 默认 MP4（最广泛的投屏兼容性）
    return CastMediaType.mp4;
  }

  /// 用户主动 seek 回调 — 通知位置守护系统这是用户操作而非异常跳回
  void _onUserSeek(Duration target) {
    _userSeekTarget = target;
    _lastResetTime = DateTime.now();
    _positionResetCount = 0;
    // 更新稳定位置到 seek 目标，防止守护把用户 seek 纠正回去
    if (target.inSeconds > (_lastStablePosition?.inSeconds ?? 0)) {
      _lastStablePosition = target;
    }
    // 弹幕同步 seek
    ref.read(danmakuControllerProvider).seekTo(target);
    appLogger.d('[Player] 用户主动 seek: target=$target');
  }

  Widget _buildErrorView() {
    final colors = context.colors;
    return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.error_outline, color: colors.error, size: 48),
      const SizedBox(height: 16),
      Text(_errorMessage ?? '加载失败', style: TextStyle(color: colors.textSecondary, fontSize: 14), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        GestureDetector(onTap: _loadDetailAndPlay, child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(8)), child: Text('重试', style: TextStyle(color: colors.textInverse, fontSize: 14, fontWeight: FontWeight.w600)))),
        const SizedBox(width: 12),
        GestureDetector(onTap: () => context.pop(), child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: BoxDecoration(color: colors.elevated, borderRadius: BorderRadius.circular(8)), child: Text('返回', style: TextStyle(color: colors.textSecondary, fontSize: 14)))),
      ]),
    ])));
  }

  Widget _buildContentBelow() {
    final proxyState = ref.watch(doubanImageProxyProvider);
    ref.read(doubanImageProxyProvider.notifier).checkAndRefresh();
    final baseUrl = ref.read(apiClientProvider).baseUrl;
    final detail = _detail!;
    return SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InfoPanel(detail: detail, proxyState: proxyState, baseUrl: baseUrl, onDownload: _onDownload, onCache: () {
        if (_detail == null || _sources.isEmpty) return;
        final si = _currentSourceIndex.clamp(0, _sources.length - 1);
        CacheEpisodeDialog.show(
          context,
          sources: _sources,
          defaultSourceIndex: si,
          defaultEpIndex: _currentEpIndex,
          resourceDomain: _detail!.resourceDomain,
          vodId: widget.vodId,
        );
      }),
      const SizedBox(height: 12),
      if (_sources.length > 1) ResourceTabs(sources: _sources, activeSourceIndex: _currentSourceIndex, onSelect: (idx) => _selectEpisode(idx, 0)),
      if (_sources.length > 1) const SizedBox(height: 12),
      EpisodeList(episodes: _sources.isNotEmpty ? _sources[_currentSourceIndex.clamp(0, _sources.length - 1)].episodes : [], activeIndex: _currentEpIndex, vodId: widget.vodId, sourceIndex: _currentSourceIndex, onSelect: (idx) => _selectEpisode(_currentSourceIndex, idx)),
      const SizedBox(height: 32),
    ]));
  }
}

/// 竖屏全屏页面 — 使用自定义竖屏布局
class _PortraitFullscreenPage extends ConsumerWidget {
  final ValueNotifier<ChewieController?> chewieControllerNotifier;
  final String title;
  final VoidCallback onExitFullscreen;
  final Future<void> Function(FullscreenMode)? onEnterFullscreen;
  final Future<void> Function(FullscreenMode)? onSwitchFullscreenMode;
  final void Function(Duration)? onUserSeek;
  final void Function(DisplayAspectRatio)? onAspectRatioChange;
  final void Function(CastDevice device)? onCastDevice;
  final VoidCallback? onCastDisconnect;
  final VoidCallback? onPreviousEpisode;
  final VoidCallback? onNextEpisode;
  final bool canPrevious;
  final bool canNext;

  const _PortraitFullscreenPage({
    required this.chewieControllerNotifier,
    required this.title,
    required this.onExitFullscreen,
    this.onEnterFullscreen,
    this.onSwitchFullscreenMode,
    this.onUserSeek,
    this.onAspectRatioChange,
    this.onCastDevice,
    this.onCastDisconnect,
    this.onPreviousEpisode,
    this.onNextEpisode,
    this.canPrevious = true,
    this.canNext = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratio = ref.watch(displayAspectRatioProvider);
    final isCasting = ref.watch(playbackControllerProvider).state.isCasting;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        onExitFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ValueListenableBuilder<ChewieController?>(
          valueListenable: chewieControllerNotifier,
          builder: (_, cc, _) {
            if (cc == null) return const SizedBox.shrink();
            return Stack(fit: StackFit.expand, children: [
              _buildVideoWithAspectRatio(cc, ratio),
              if (isCasting)
                CastConnectingOverlay(
                  title: title,
                  onDisconnect: onCastDisconnect,
                  onPreviousEpisode: onPreviousEpisode,
                  onNextEpisode: onNextEpisode,
                  canPrevious: canPrevious,
                  canNext: canNext,
                )
              else
                BilibiliControls(
                  chewieController: cc,
                  title: title,
                  onEnterFullscreen: onEnterFullscreen,
                  onExitFullscreen: onExitFullscreen,
                  onSwitchFullscreenMode: onSwitchFullscreenMode,
                  onUserSeek: onUserSeek,
                  onAspectRatioChange: onAspectRatioChange,
                  onCastDevice: onCastDevice,
                  onCastDisconnect: onCastDisconnect,
                ),
            ]);
          },
        ),
      ),
    );
  }
}

/// 根据画面比例模式计算 aspectRatio 值
/// 返回 null 表示不限制（自适应）
double? _computeAspectRatio(DisplayAspectRatio ratio, ChewieController controller) {
  switch (ratio) {
    case DisplayAspectRatio.ratio16_9:
      return 16 / 9;
    case DisplayAspectRatio.ratio4_3:
      return 4 / 3;
    case DisplayAspectRatio.ratio9_16:
      return 9 / 16;
    case DisplayAspectRatio.reset:
      // 防御性处理：reset 在 onSelected 中已映射为具体值，正常不会到达此处
      return 16 / 9;
    case DisplayAspectRatio.fill:
      // 填充模式：使用屏幕比例让视频铺满
      return null;
    case DisplayAspectRatio.autoAdapt:
      final videoSize = controller.videoPlayerController.value.size;
      if (videoSize.width > 0 && videoSize.height > 0) {
        return videoSize.width / videoSize.height;
      }
      return null;
  }
}

/// 根据画面比例模式构建视频组件
/// 填充模式需要特殊处理：让 Chewie 铺满整个 Stack 区域并裁剪
Widget _buildVideoWithAspectRatio(ChewieController controller, DisplayAspectRatio ratio) {
  if (ratio == DisplayAspectRatio.fill) {
    return ClipRect(child: Chewie(controller: controller));
  }
  return Chewie(controller: controller);
}

/// 横屏全屏页面 — 使用自定义横屏布局
class _LandscapeFullscreenPage extends ConsumerWidget {
  final ValueNotifier<ChewieController?> chewieControllerNotifier;
  final String title;
  final VoidCallback onExitFullscreen;
  final Future<void> Function(FullscreenMode)? onEnterFullscreen;
  final Future<void> Function(FullscreenMode)? onSwitchFullscreenMode;
  final void Function(Duration)? onUserSeek;
  final void Function(DisplayAspectRatio)? onAspectRatioChange;
  final void Function(CastDevice device)? onCastDevice;
  final VoidCallback? onCastDisconnect;
  final VoidCallback? onPreviousEpisode;
  final VoidCallback? onNextEpisode;
  final bool canPrevious;
  final bool canNext;

  const _LandscapeFullscreenPage({
    required this.chewieControllerNotifier,
    required this.title,
    required this.onExitFullscreen,
    this.onEnterFullscreen,
    this.onSwitchFullscreenMode,
    this.onUserSeek,
    this.onAspectRatioChange,
    this.onCastDevice,
    this.onCastDisconnect,
    this.onPreviousEpisode,
    this.onNextEpisode,
    this.canPrevious = true,
    this.canNext = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratio = ref.watch(displayAspectRatioProvider);
    final isCasting = ref.watch(playbackControllerProvider).state.isCasting;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        onExitFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ValueListenableBuilder<ChewieController?>(
          valueListenable: chewieControllerNotifier,
          builder: (_, cc, _) {
            if (cc == null) return const SizedBox.shrink();
            return Stack(fit: StackFit.expand, children: [
              _buildVideoWithAspectRatio(cc, ratio),
              if (isCasting)
                CastConnectingOverlay(
                  title: title,
                  onDisconnect: onCastDisconnect,
                  onPreviousEpisode: onPreviousEpisode,
                  onNextEpisode: onNextEpisode,
                  canPrevious: canPrevious,
                  canNext: canNext,
                )
              else
                BilibiliControls(
                  chewieController: cc,
                  title: title,
                  onEnterFullscreen: onEnterFullscreen,
                  onExitFullscreen: onExitFullscreen,
                  onSwitchFullscreenMode: onSwitchFullscreenMode,
                  onUserSeek: onUserSeek,
                  onAspectRatioChange: onAspectRatioChange,
                  onCastDevice: onCastDevice,
                  onCastDisconnect: onCastDisconnect,
                ),
            ]);
          },
        ),
      ),
    );
  }
}
