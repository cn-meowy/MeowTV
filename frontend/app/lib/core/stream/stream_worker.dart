import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../logger/app_logger.dart';
import 'segment_cache_manager.dart';
import 'stream_config.dart';

/// 最大分片下载重试次数 — 对应后端 MaxSegmentRetries
const int maxSegmentRetries = 3;

/// 分片下载超时 — 对应后端 StreamTimeout
const Duration streamTimeout = Duration(seconds: 60);

/// 任务取消异常 — 用于中断正在进行的下载
class TaskCancelledException implements Exception {
  final int segmentIndex;
  TaskCancelledException(this.segmentIndex);

  @override
  String toString() => 'TaskCancelledException: segment=$segmentIndex';
}

/// Worker — 工作协程，对应后端 Worker
///
/// 负责下载 TS 分片，写入缓存管理器。
/// 两种类型：
/// - Dedicated Worker：专属协程，保障对应用户当前观看位置不断流
/// - General Worker：通用协程，按优先级队列顺序下载未缓存分片
///
/// 支持任务取消：seek 时可通过 [cancelCurrentTask] 中断正在下载的任务，
/// 通过 [clearTaskQueue] 清空待执行的任务队列。
class StreamWorker {
  final int id;
  final WorkerType workerType;
  final int? assignedUserId; // 专属 Worker 关联的用户 ID
  final StreamSessionRef session;
  final PriorityQueue? generalQueue; // 通用 Worker 使用的优先级队列
  final HttpClient? _sharedHttpClient; // 共享 HttpClient，复用 TCP 连接
  final void Function()? onTaskNotify; // 通知调度器有新任务

  bool _stopped = false;
  DownloadTask? _currentTask;
  Completer<void>? _stopCompleter;

  /// 取消当前任务的信号 — 对应后端 cancelCh + taskCtx
  /// seek 时通过 [cancelCurrentTask] complete 此 Completer，
  /// 正在执行的下载任务在下一个 await 点感知取消并退出
  Completer<void>? _cancelCompleter;

  /// 专属 Worker 任务队列 — 替代 StreamController，支持清空操作
  /// 对应后端 Worker.dedicatedTask (chan *Task)
  final List<DownloadTask> _dedicatedTaskQueue = [];

  /// 专属 Worker 任务通知 — 有新任务入队时触发
  Completer<void>? _taskNotifyCompleter;

  StreamWorker({
    required this.id,
    required this.workerType,
    this.assignedUserId,
    required this.session,
    this.generalQueue,
    HttpClient? sharedHttpClient,
    this.onTaskNotify,
  }) : _sharedHttpClient = sharedHttpClient;

  /// 启动 Worker 主循环
  Future<void> run() async {
    appLogger.d('[Worker] 启动: id=$id, type=$workerType, userId=$assignedUserId');

    if (workerType == WorkerType.dedicated) {
      await _runDedicated();
    } else {
      await _runGeneral();
    }

    appLogger.d('[Worker] 停止: id=$id');
  }

  /// 停止 Worker
  void stop() {
    if (_stopped) return;
    _stopped = true;
    _stopCompleter?.complete();
    // 唤醒可能在等待任务的 Dedicated Worker
    _notifyTaskAvailable();
  }

  /// 获取当前任务
  DownloadTask? get currentTask => _currentTask;

  /// 分配任务给专属 Worker — 对应后端 AssignTask
  ///
  /// 非阻塞，入队后通知 Dedicated Worker 主循环。
  /// 队列无上限（由调度器控制入队数量），旧任务不会被丢弃。
  void assignTask(DownloadTask task) {
    _dedicatedTaskQueue.add(task);
    _notifyTaskAvailable();
  }

  /// 取消当前正在执行的任务 — 对应后端 CancelCurrentTask
  ///
  /// 通过 complete [_cancelCompleter] 发出取消信号，
  /// 正在执行的 [_doDownloadSegment] 会在下一个 await 点感知取消并退出。
  /// 用于 seek 后中断专属 Worker 正在下载的无关分片。
  void cancelCurrentTask() {
    final c = _cancelCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  /// 清空专属任务队列中所有待执行任务 — 对应后端 ClearTaskQueue
  ///
  /// 用于 seek 后清除专属 Worker 中尚未开始执行的旧任务，
  /// 避免继续下载用户不再需要的位置。
  int clearTaskQueue() {
    final count = _dedicatedTaskQueue.length;
    _dedicatedTaskQueue.clear();
    if (count > 0) {
      appLogger.d('[Worker] 清空专属任务队列: workerId=$id, cleared=$count');
    }
    return count;
  }

  /// 通知 Dedicated Worker 有新任务可用
  void _notifyTaskAvailable() {
    final c = _taskNotifyCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  // ==================== 专属 Worker ====================

  /// 专属 Worker 主循环 — 对应后端 runDedicated
  ///
  /// 监听取消信号以支持 seek 后任务取消：收到取消信号后跳过当前任务，继续等待新任务。
  /// 使用 List + Completer 通知机制替代 StreamController，支持 [clearTaskQueue] 清空。
  Future<void> _runDedicated() async {
    while (!_stopped) {
      // 等待任务或取消信号
      if (_dedicatedTaskQueue.isEmpty) {
        // 无任务，等待通知
        final notifyCompleter = Completer<void>();
        _taskNotifyCompleter = notifyCompleter;
        try {
          await notifyCompleter.future;
        } catch (_) {
          // Completer 被取消，退出
          return;
        }
        _taskNotifyCompleter = null;
      }

      if (_stopped) return;

      // 从队列取任务
      if (_dedicatedTaskQueue.isNotEmpty) {
        final task = _dedicatedTaskQueue.removeAt(0);
        await _executeTask(task);
      }
    }
  }

  // ==================== 通用 Worker ====================

  Future<void> _runGeneral() async {
    // 兜底轮询间隔，防止极端情况下通知丢失导致任务积压
    final fallbackTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _tryPopAndExecute(),
    );

    try {
      while (!_stopped) {
        // 等待任务通知或兜底轮询
        await Future.delayed(const Duration(milliseconds: 200));
        if (_stopped) break;
        await _tryPopAndExecute();
      }
    } finally {
      fallbackTimer.cancel();
    }
  }

  Future<void> _tryPopAndExecute() async {
    final task = generalQueue?.pop();
    if (task != null) {
      await _executeTask(task);
    }
  }

  // ==================== 任务执行 ====================

  /// 执行下载任务 — 对应后端 executeTask
  ///
  /// 创建可取消的 [_cancelCompleter]，使下载可被 [cancelCurrentTask] 中断。
  /// 使用 [_guarded] 保护状态变更，防止 async 交叉点竞态。
  Future<void> _executeTask(DownloadTask task) async {
    _currentTask = task;
    // 每个任务创建新的取消信号
    _cancelCompleter = Completer<void>();

    final segmentIndex = task.segmentIndex;
    final cacheManager = session.cacheManager;

    try {
      // 检查分片状态
      final status = cacheManager.getStatus(segmentIndex);
      if (status == SegmentStatus.done) {
        appLogger.d('[Worker] 分片已完成，跳过: index=$segmentIndex');
        return;
      }

      // 检查任务是否已被取消（seek 后可能立即取消）
      if (_cancelCompleter?.isCompleted == true) {
        appLogger.d('[Worker] 任务在执行前已取消: segment=$segmentIndex');
        return;
      }

      // 标记为下载中
      await cacheManager.setStatus(segmentIndex, SegmentStatus.downloading);

      // 再次检查取消状态（setStatus 是异步操作，期间可能被取消）
      if (_cancelCompleter?.isCompleted == true) {
        appLogger.d('[Worker] 任务在标记下载中后被取消: segment=$segmentIndex');
        cacheManager.resetDownloadingToPending(segmentIndex);
        return;
      }

      appLogger.i('[Worker] 开始下载: workerId=$id, type=$workerType, segment=$segmentIndex, urgent=${task.urgent}');

      // 获取分片 URL
      final m3u8Info = session.m3u8Info;
      if (segmentIndex >= m3u8Info.segments.length) {
        appLogger.e('[Worker] 分片索引越界: segment=$segmentIndex, total=${m3u8Info.segments.length}');
        await cacheManager.markSegmentFailed(segmentIndex);
        return;
      }

      final segURL = m3u8Info.segments[segmentIndex].url;

      // 执行下载（含重试）
      await _downloadSegmentWithRetry(segmentIndex, segURL);
    } on TaskCancelledException {
      appLogger.i('[Worker] 任务被取消: workerId=$id, segment=$segmentIndex');
    } finally {
      _currentTask = null;
      _cancelCompleter = null;
    }
  }

  /// 统一下载分片原始数据（含重试机制） — 对应后端 downloadSegment
  ///
  /// 使用 [_cancelCompleter] 监听取消信号，seek 后可中断下载。
  Future<void> _downloadSegmentWithRetry(int segmentIndex, String segURL) async {
    final cacheManager = session.cacheManager;

    Object? lastError;

    for (var attempt = 1; attempt <= maxSegmentRetries; attempt++) {
      if (_stopped) return;

      // 检查取消信号
      if (_cancelCompleter?.isCompleted == true) {
        throw TaskCancelledException(segmentIndex);
      }

      // 每次重试前检查状态，可能已被其他 Worker 完成
      if (cacheManager.getStatus(segmentIndex) == SegmentStatus.done) return;

      // 重试时重新标记为 Downloading
      if (attempt > 1) {
        await cacheManager.setStatus(segmentIndex, SegmentStatus.downloading);
      }

      try {
        final data = await _doDownloadSegment(segmentIndex, segURL);
        if (data != null) {
          // 下载完成，标记完成
          await cacheManager.markSegmentDone(segmentIndex, data);
          appLogger.i('[Worker] 分片下载完成: workerId=$id, segment=$segmentIndex, bytes=${data.length}');
          return;
        }
      } on TaskCancelledException {
        rethrow;
      } catch (e) {
        lastError = e;

        if (!_isRetryableError(e)) {
          appLogger.e('[Worker] 分片下载失败（不可重试）: workerId=$id, segment=$segmentIndex, attempt=$attempt, error=$e');
          break;
        }

        appLogger.w('[Worker] 分片下载失败，重试中: workerId=$id, segment=$segmentIndex, attempt=$attempt/$maxSegmentRetries, error=$e');
      }
    }

    // 所有重试都失败
    appLogger.e('[Worker] 分片下载耗尽重试: workerId=$id, segment=$segmentIndex, maxRetries=$maxSegmentRetries, lastError=$lastError');
    await cacheManager.markSegmentFailed(segmentIndex);
  }

  /// 执行单次分片下载 — 对应后端 doDownloadSegment
  ///
  /// 优先使用共享 HttpClient 复用 TCP 连接，fallback 创建临时 client。
  /// 支持取消：通过 Future.any 监听 [_cancelCompleter] 信号，
  /// 取消时抛出 [TaskCancelledException] 中断下载。
  Future<Uint8List?> _doDownloadSegment(int segmentIndex, String segURL) async {
    final cancelCompleter = _cancelCompleter;
    if (cancelCompleter != null && cancelCompleter.isCompleted) {
      throw TaskCancelledException(segmentIndex);
    }

    final useShared = _sharedHttpClient != null;
    final client = _sharedHttpClient ?? HttpClient();
    if (!useShared) client.connectionTimeout = streamTimeout;

    try {
      final request = await client.getUrl(Uri.parse(segURL));

      // 设置防盗链关键头部：User-Agent 和 Referer
      // 与 VideoCacheProxy._proxySegmentFromOrigin 保持一致，
      // 避免源站防盗链检查返回 403 或非 TS 错误内容
      request.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      request.headers.set('Referer', session.m3u8URL);

      // 检查取消信号（在发起请求前）
      if (cancelCompleter != null && cancelCompleter.isCompleted) {
        if (!useShared) client.close(force: true);
        throw TaskCancelledException(segmentIndex);
      }

      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        if (!useShared) client.close(force: true);
        throw Exception('HTTP ${response.statusCode}');
      }

      // 读取完整响应数据，同时监听取消信号
      final builder = BytesBuilder();

      // 使用 Future.any 实现取消监听：
      // 如果取消信号先完成，抛出 TaskCancelledException 中断读取
      await Future.any<void>([
        // 下载数据流
        () async {
          await for (final chunk in response) {
            // 每读取一个 chunk 检查取消信号
            if (cancelCompleter != null && cancelCompleter.isCompleted) {
              throw TaskCancelledException(segmentIndex);
            }
            builder.add(chunk);
          }
        }(),
        // 取消信号监听
        if (cancelCompleter != null)
          cancelCompleter.future.then((_) {
            throw TaskCancelledException(segmentIndex);
          }),
      ]);

      if (!useShared) client.close();

      final data = builder.toBytes();
      appLogger.d('[Worker] 分片下载完成: segment=$segmentIndex, bytes=${data.length}');

      return Uint8List.fromList(data);
    } catch (e) {
      if (!useShared) {
        try { client.close(force: true); } catch (_) {}
      }
      if (e is TaskCancelledException) rethrow;
      if (e is TimeoutException || e is SocketException || e is HttpException) {
        rethrow;
      }
      throw Exception('download segment failed: $e');
    }
  }

  /// 判断是否可重试的错误 — 对应后端 IsRetryableError
  static bool _isRetryableError(Object error) {
    if (error is TimeoutException) return true;
    if (error is SocketException) return true;
    if (error is HttpException) return true;
    final msg = error.toString();
    if (msg.contains('Connection refused')) return true;
    if (msg.contains('Connection reset')) return true;
    if (msg.contains('broken pipe')) return true;
    if (msg.contains('HTTP 5')) return true;
    if (msg.contains('HTTP 429')) return true;
    return false;
  }
}

/// 优先级队列 — 对应后端 PriorityQueue（堆实现）
///
/// 优先级数值越小，越优先下载。
/// 支持 contains 去重检查，防止同一分片重复入队。
class PriorityQueue {
  final List<DownloadTask> _items = [];
  final Set<int> _segmentIndexSet = {}; // 快速去重检查

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;

  /// 检查指定分片是否已在队列中
  bool contains(int segmentIndex) => _segmentIndexSet.contains(segmentIndex);

  /// 入队（如果分片已在队列中，忽略）
  void push(DownloadTask task) {
    if (_segmentIndexSet.contains(task.segmentIndex)) return;
    _segmentIndexSet.add(task.segmentIndex);
    _items.add(task);
    _siftUp(_items.length - 1);
  }

  /// 弹出优先级最高的任务（priority 最小）
  DownloadTask? pop() {
    if (_items.isEmpty) return null;
    if (_items.length == 1) {
      final item = _items.removeLast();
      _segmentIndexSet.remove(item.segmentIndex);
      return item;
    }

    final result = _items[0];
    _segmentIndexSet.remove(result.segmentIndex);
    _items[0] = _items.removeLast();
    _siftDown(0);
    return result;
  }

  /// 查看队首
  DownloadTask? peek() {
    return _items.isEmpty ? null : _items[0];
  }

  /// 清空
  void clear() {
    _items.clear();
    _segmentIndexSet.clear();
  }

  void _siftUp(int index) {
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (_items[index].priority < _items[parent].priority) {
        _swap(index, parent);
        index = parent;
      } else {
        break;
      }
    }
  }

  void _siftDown(int index) {
    while (true) {
      var smallest = index;
      final left = 2 * index + 1;
      final right = 2 * index + 2;

      if (left < _items.length && _items[left].priority < _items[smallest].priority) {
        smallest = left;
      }
      if (right < _items.length && _items[right].priority < _items[smallest].priority) {
        smallest = right;
      }

      if (smallest != index) {
        _swap(index, smallest);
        index = smallest;
      } else {
        break;
      }
    }
  }

  void _swap(int i, int j) {
    final tmp = _items[i];
    _items[i] = _items[j];
    _items[j] = tmp;
  }
}

/// StreamSession 引用（避免循环依赖）
/// Worker 持有此引用来访问 Session 的数据
class StreamSessionRef {
  final M3u8Info m3u8Info;
  final String m3u8URL; // 原始 m3u8 URL，用作分片下载的 Referer
  final SegmentCacheManager cacheManager;
  final HttpClient httpClient; // 共享 HttpClient，复用 TCP 连接

  StreamSessionRef({
    required this.m3u8Info,
    required this.m3u8URL,
    required this.cacheManager,
    required this.httpClient,
  });
}
