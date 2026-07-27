import 'dart:async';

import '../logger/app_logger.dart';
import 'stream_config.dart';
import 'stream_worker.dart';

/// 调度中心 — 对应后端 ScheduleCenter
///
/// 核心调度逻辑：
/// - 1 个调度循环，100ms 间隔
/// - 1 个 Dedicated Worker 保障紧急分片优先下载（守护模式，持续跟随播放位置）
/// - N 个 General Worker 按优先级队列执行下载任务
/// - 前瞻窗口计算：只为当前播放位置 + bufferSize 范围内的分片入队
/// - 增量入队：维护 _queuedSet 避免重复入队
/// - Seek 后立即中断 Dedicated Worker 当前无关任务，以 seek 位置为中心重排
/// - 守护 Worker 机制：每次调度周期检查 Dedicated Worker 任务是否在播放窗口内
class StreamScheduler {
  final StreamSessionRef session;
  final PriorityQueue generalQueue;
  final Map<int, StreamWorker> _workers = {};
  final StreamConfig config;

  bool _running = false;
  bool _stopped = false;
  Timer? _scheduleTimer;
  final _seekNotifyController = StreamController<void>.broadcast();

  int _currentSegmentIndex = 0; // 当前播放位置

  /// 已入队分片集合 — 增量入队时去重
  final Set<int> _queuedSet = {};

  /// Dedicated Worker 的固定 ID
  static const int _dedicatedWorkerId = -1;

  StreamScheduler({
    required this.session,
    required this.config,
  }) : generalQueue = PriorityQueue();

  /// 启动调度中心
  void start() {
    if (_running) return;
    _running = true;

    appLogger.i('[Scheduler] 启动: generalWorkers=${config.generalWorkers}, bufferSize=${config.bufferSize}');

    // 启动 Dedicated Worker（保障紧急分片优先下载）
    _spawnDedicatedWorker(_dedicatedWorkerId);

    // 启动通用 Worker
    for (var i = 0; i < config.generalWorkers; i++) {
      _spawnGeneralWorker(i);
    }

    // 启动调度循环（100ms 间隔）
    _scheduleTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_stopped) _schedule();
    });

    // 监听 seek 通知
    _seekNotifyController.stream.listen((_) {
      if (!_stopped) _schedule();
    });
  }

  /// 停止调度中心
  void stop() {
    if (!_running) return;
    _running = false;
    _stopped = true;

    appLogger.i('[Scheduler] 停止');

    _scheduleTimer?.cancel();
    _scheduleTimer = null;

    for (final worker in _workers.values) {
      worker.stop();
    }
    _workers.clear();
    _queuedSet.clear();
    generalQueue.clear();

    _seekNotifyController.close();
  }

  /// 通知 seek — 对应后端 NotifySeek
  ///
  /// Seek 后立即：
  /// 1. 更新播放位置
  /// 2. 清空通用队列和 _queuedSet
  /// 3. 中断 Dedicated Worker 当前无关任务
  /// 4. 清空 Dedicated Worker 待执行任务队列
  /// 5. 重置被取消分片的 downloading 状态为 pending
  /// 6. 以 seek 位置为中心重填队列
  /// 7. 为 Dedicated Worker 分配 seek 位置附近的任务
  void notifySeek(int targetIndex) {
    final oldIndex = _currentSegmentIndex;
    _currentSegmentIndex = targetIndex;

    appLogger.i('[Scheduler] seek 通知: oldIndex=$oldIndex, targetIndex=$targetIndex');

    // 1. 清空通用队列和 _queuedSet
    generalQueue.clear();
    _queuedSet.clear();

    // 2. 中断 Dedicated Worker 当前任务 + 清空任务队列
    final dedicatedWorker = _workers[_dedicatedWorkerId];
    if (dedicatedWorker != null) {
      // 保存当前任务索引，用于重置状态
      final currentTask = dedicatedWorker.currentTask;

      // 取消当前正在执行的任务（中断 HTTP 请求）
      dedicatedWorker.cancelCurrentTask();

      // 清空待执行的任务队列
      dedicatedWorker.clearTaskQueue();

      // 重置被取消的 Downloading 分片状态为 Pending
      // 避免 Worker 取消后分片卡在 Downloading 状态导致无人继续下载
      if (currentTask != null) {
        final idx = currentTask.segmentIndex;
        final cacheManager = session.cacheManager;
        // 如果取消的分片不在 seek 范围内，重置为 Pending
        final seekRangeEnd = (targetIndex + config.bufferSize)
            .clamp(0, cacheManager.totalSegments);
        if (idx < targetIndex || idx >= seekRangeEnd) {
          cacheManager.resetDownloadingToPending(idx);
          appLogger.d('[Scheduler] 重置被取消分片状态: segment=$idx, target=$targetIndex, rangeEnd=$seekRangeEnd');
        }
      }
    }

    // 3. 以 seek 位置为中心重填通用队列
    _fillQueueForSeek(targetIndex);

    // 4. 为 Dedicated Worker 分配 seek 位置附近的任务
    if (dedicatedWorker != null) {
      _assignDedicatedTasksForSeek(dedicatedWorker, targetIndex);
    }

    // 5. 触发调度（通过 seekNotify 通知）
    if (!_seekNotifyController.isClosed) {
      _seekNotifyController.add(null);
    }
  }

  /// 通知紧急分片 — 对应后端 NotifyUrgentSegment
  void notifyUrgentSegment(int segmentIndex) {
    // 直接将紧急任务推入队列（Dedicated Worker 会优先处理）
    if (!_queuedSet.contains(segmentIndex)) {
      _queuedSet.add(segmentIndex);
      generalQueue.push(DownloadTask(
        segmentIndex: segmentIndex,
        priority: 0, // 最高优先级
        urgent: true,
      ));
    }

    // 同时通知 Dedicated Worker 直接处理此紧急分片
    final dedicatedWorker = _workers[_dedicatedWorkerId];
    if (dedicatedWorker != null) {
      dedicatedWorker.assignTask(DownloadTask(
        segmentIndex: segmentIndex,
        priority: 0,
        urgent: true,
      ));
    }
  }

  /// 更新当前播放位置 — 由 recordSegmentRequest 调用
  ///
  /// 不触发 seek 逻辑，仅更新 [_currentSegmentIndex] 使调度窗口计算更准确。
  void updateCurrentPosition(int segmentIndex) {
    _currentSegmentIndex = segmentIndex;
  }

  // ==================== 内部方法 ====================

  /// 创建专属 Worker — 对应后端 spawnDedicatedWorker
  void _spawnDedicatedWorker(int id) {
    final worker = StreamWorker(
      id: id,
      workerType: WorkerType.dedicated,
      session: session,
      sharedHttpClient: session.httpClient,
    );
    _workers[id] = worker;
    worker.run();
  }

  /// 创建通用 Worker — 对应后端 spawnGeneralWorker
  void _spawnGeneralWorker(int id) {
    final worker = StreamWorker(
      id: id,
      workerType: WorkerType.general,
      session: session,
      generalQueue: generalQueue,
      sharedHttpClient: session.httpClient,
    );
    _workers[id] = worker;
    worker.run();
  }

  /// 核心调度逻辑 — 两阶段调度 + 守护 Worker
  ///
  /// 阶段1（紧急窗口）：入队 [currentIndex, currentIndex + bufferSize] 范围内未缓存分片，高优先级
  /// 阶段2（全量填充）：入队所有未缓存分片，低优先级，General Worker 空闲时持续填充
  /// 阶段3（守护 Worker）：确保 Dedicated Worker 始终在播放位置附近下载
  ///
  /// 增量模式：只入队不在 _queuedSet 中的新分片
  Future<void> _schedule() async {
    final cacheManager = session.cacheManager;
    final m3u8Info = session.m3u8Info;
    final totalSegments = m3u8Info.segments.length;

    // 计算紧急窗口范围
    final windowStart = _currentSegmentIndex;
    final windowEnd = (_currentSegmentIndex + config.bufferSize)
        .clamp(0, totalSegments);

    var urgentAdded = 0;
    var fillAdded = 0;

    // 阶段1：紧急窗口 — 高优先级入队
    for (var segIndex = windowStart; segIndex < windowEnd; segIndex++) {
      if (_queuedSet.contains(segIndex)) continue;

      final status = cacheManager.getStatus(segIndex);
      if (status == SegmentStatus.done) {
        _queuedSet.add(segIndex); // 标记已完成，不再入队
        continue;
      }
      if (status == SegmentStatus.downloading) continue; // 正在下载，跳过

      // 入队，优先级 = segIndex（越早的越优先，数值小）
      _queuedSet.add(segIndex);
      generalQueue.push(DownloadTask(
        segmentIndex: segIndex,
        priority: segIndex,
      ));
      urgentAdded++;
    }

    // 阶段2：全量填充 — 低优先级入队所有未缓存分片
    // 优先级 = totalSegments + segIndex（确保低于紧急窗口优先级）
    for (var segIndex = 0; segIndex < totalSegments; segIndex++) {
      if (_queuedSet.contains(segIndex)) continue;

      final status = cacheManager.getStatus(segIndex);
      if (status == SegmentStatus.done) {
        _queuedSet.add(segIndex);
        continue;
      }
      if (status == SegmentStatus.downloading) continue;

      _queuedSet.add(segIndex);
      generalQueue.push(DownloadTask(
        segmentIndex: segIndex,
        priority: totalSegments + segIndex,
      ));
      fillAdded++;
    }

    final totalAdded = urgentAdded + fillAdded;
    if (totalAdded > 0) {
      appLogger.d('[Scheduler] 增量入队: urgent=$urgentAdded, fill=$fillAdded, window=[$windowStart,$windowEnd), queueLen=${generalQueue.length}');
    }

    // 阶段3：守护 Dedicated Worker — 确保其始终在播放位置附近下载
    _rebalanceGuardianTask();

    // 淘汰超出内存限制的缓存
    await cacheManager.evictMemoryCache();

    // 滑动窗口淘汰远离播放位置的内存缓存
    await cacheManager.slideWindow(_currentSegmentIndex);
  }

  /// 守护 Dedicated Worker — 对应后端 rebalanceGuardianTasks
  ///
  /// 确保 Dedicated Worker 始终在用户播放位置附近下载未完成分片。
  /// 如果 Dedicated Worker 的当前任务不在播放窗口内，取消并重新分配。
  void _rebalanceGuardianTask() {
    final dedicatedWorker = _workers[_dedicatedWorkerId];
    if (dedicatedWorker == null) return;

    final cacheManager = session.cacheManager;
    final totalSegments = cacheManager.totalSegments;
    final cur = _currentSegmentIndex;
    final windowEnd = (cur + config.bufferSize).clamp(0, totalSegments);

    // 检查当前任务是否在播放窗口内
    final currentTask = dedicatedWorker.currentTask;
    if (currentTask != null) {
      final taskIdx = currentTask.segmentIndex;
      if (taskIdx < cur || taskIdx >= windowEnd) {
        // 当前任务不在播放窗口内，取消并重置状态
        dedicatedWorker.cancelCurrentTask();
        dedicatedWorker.clearTaskQueue();
        cacheManager.resetDownloadingToPending(taskIdx);
        appLogger.d('[Scheduler] 守护 Worker 任务超出窗口，重平衡: '
            'taskSegment=$taskIdx, window=[$cur,$windowEnd)');
      }
    }

    // 为 Dedicated Worker 分配播放窗口内的 Pending 分片（增量补充）
    // 如果 Worker 当前空闲或有 Pending 分片，立即分配
    var assigned = 0;
    for (var segIndex = cur; segIndex < windowEnd && assigned < config.bufferSize; segIndex++) {
      final status = cacheManager.getStatus(segIndex);
      if (status == SegmentStatus.pending || status == SegmentStatus.failed) {
        dedicatedWorker.assignTask(DownloadTask(
          segmentIndex: segIndex,
          priority: segIndex - cur,
          urgent: true,
        ));
        assigned++;
      }
    }

    if (assigned > 0) {
      appLogger.d('[Scheduler] 守护 Worker 分配任务: assigned=$assigned, window=[$cur,$windowEnd)');
    }
  }

  /// 以 seek 位置为中心重填通用队列 — 对应后端 handleSeek 步骤 2
  void _fillQueueForSeek(int seekTarget) {
    final cacheManager = session.cacheManager;
    final totalSegments = cacheManager.totalSegments;
    final seekEnd = (seekTarget + config.bufferSize * 2).clamp(0, totalSegments);

    var priority = 0;
    for (var segIndex = seekTarget; segIndex < seekEnd; segIndex++) {
      final status = cacheManager.getStatus(segIndex);
      if (status == SegmentStatus.pending || status == SegmentStatus.failed) {
        _queuedSet.add(segIndex);
        generalQueue.push(DownloadTask(
          segmentIndex: segIndex,
          priority: priority,
        ));
        priority++;
      } else if (status == SegmentStatus.done) {
        _queuedSet.add(segIndex);
      }
    }

    appLogger.d('[Scheduler] seek 重填队列: target=$seekTarget, rangeEnd=$seekEnd, added=$priority');
  }

  /// 为 Dedicated Worker 分配 seek 位置附近的任务 — 对应后端 handleSeek 步骤 4
  void _assignDedicatedTasksForSeek(StreamWorker dedicatedWorker, int seekTarget) {
    final cacheManager = session.cacheManager;
    final totalSegments = cacheManager.totalSegments;
    final seekRangeEnd = (seekTarget + config.bufferSize).clamp(0, totalSegments);

    var batchSize = 0;
    for (var segIndex = seekTarget; segIndex < seekRangeEnd && batchSize < config.bufferSize; segIndex++) {
      final status = cacheManager.getStatus(segIndex);
      if (status == SegmentStatus.pending || status == SegmentStatus.failed) {
        dedicatedWorker.assignTask(DownloadTask(
          segmentIndex: segIndex,
          priority: segIndex - seekTarget,
          urgent: true,
        ));
        batchSize++;
      }
    }

    appLogger.i('[Scheduler] seek 后 Dedicated Worker 重分配: '
        'target=$seekTarget, rangeEnd=$seekRangeEnd, assigned=$batchSize');
  }

  /// 是否正在运行
  bool get isRunning => _running;
}
