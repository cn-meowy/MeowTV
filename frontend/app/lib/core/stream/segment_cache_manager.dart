import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../logger/app_logger.dart';
import 'stream_config.dart';

/// 分片缓存条目 — 对应后端 SegmentCache
class SegmentCache {
  final int index;
  SegmentStatus status;
  Uint8List? data; // 完成后的完整数据（内存热缓存）
  String? filePath; // 磁盘文件路径
  final List<SegmentConsumer> consumers; // 流式推送消费者列表
  final Completer<void> _doneCompleter = Completer<void>();
  int lastAccess; // 上次访问时间（ms since epoch）

  SegmentCache({
    required this.index,
    this.status = SegmentStatus.pending,
  })  : consumers = [],
        lastAccess = DateTime.now().millisecondsSinceEpoch;

  bool get isDone => _doneCompleter.isCompleted;
  Future<void> get onDone => _doneCompleter.future;

  void markDone() {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  void addConsumer(SegmentConsumer consumer) {
    consumers.add(consumer);
  }

  void removeConsumer(SegmentConsumer consumer) {
    consumers.remove(consumer);
    consumer.close();
  }

  void closeAllConsumers() {
    for (final c in consumers) {
      c.close();
    }
    consumers.clear();
  }
}

/// 分片流式推送消费者 — 对应后端 chan []byte
class SegmentConsumer {
  final void Function(Uint8List chunk) onData;
  final void Function() onDone;
  final void Function(Object error)? onError;
  bool _closed = false;

  SegmentConsumer({
    required this.onData,
    required this.onDone,
    this.onError,
  });

  bool get isClosed => _closed;

  void sendData(Uint8List chunk) {
    if (_closed) return;
    onData(chunk);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    onDone();
  }

  void sendError(Object error) {
    if (_closed) return;
    onError?.call(error);
    close();
  }
}

/// 分片缓存管理器 — 对应后端 SegmentCacheManager
///
/// 双层缓存（内存 + 磁盘）+ 流式推送消费者管理
/// 使用 _guarded 保护关键状态变更，防止 async 交叉点竞态
class SegmentCacheManager {
  final int totalSegments;
  final String segmentDir;

  final Map<int, SegmentCache> _segments = {};
  int _doneCount = 0;
  final int _memLimit;
  int _memUsed = 0;
  void Function()? _onAllDone;
  bool _allDoneFired = false;

  /// 简易互斥锁 — 防止 async 交叉点竞态
  Completer<void>? _lock;

  /// 在锁保护下执行异步操作
  Future<T> _guarded<T>(Future<T> Function() fn) async {
    final prev = _lock;
    final next = Completer<void>();
    _lock = next;
    if (prev != null) await prev.future;
    try {
      return await fn();
    } finally {
      next.complete();
    }
  }

  SegmentCacheManager({
    required this.totalSegments,
    required this.segmentDir,
    int? memLimit,
  }) : _memLimit = memLimit ?? 200 {
    for (var i = 0; i < totalSegments; i++) {
      _segments[i] = SegmentCache(index: i);
    }
    _restoreFromDisk();
  }

  // ==================== 查询方法 ====================

  SegmentCache? getSegment(int index) => _segments[index];

  SegmentStatus getStatus(int index) {
    return _segments[index]?.status ?? SegmentStatus.pending;
  }

  /// 设置分片状态 — 使用 _guarded 保护共享状态
  Future<void> setStatus(int index, SegmentStatus status) async {
    return _guarded(() async {
      _segments[index]?.status = status;
    });
  }

  bool get isAllDone => _doneCount == totalSegments;
  int get doneCount => _doneCount;

  List<int> getPendingSegments() {
    final pending = <int>[];
    for (var i = 0; i < totalSegments; i++) {
      final status = getStatus(i);
      if (status == SegmentStatus.pending || status == SegmentStatus.failed) {
        pending.add(i);
      }
    }
    return pending;
  }

  List<int> getDownloadingSegments() {
    final downloading = <int>[];
    for (var i = 0; i < totalSegments; i++) {
      if (getStatus(i) == SegmentStatus.downloading) {
        downloading.add(i);
      }
    }
    return downloading;
  }

  // ==================== 数据获取 ====================

  Future<Uint8List?> getSegmentData(int index) async {
    final seg = _segments[index];
    if (seg == null) return null;

    if (seg.status == SegmentStatus.done && seg.data != null) {
      seg.lastAccess = DateTime.now().millisecondsSinceEpoch;
      return seg.data;
    }

    if (seg.filePath != null) {
      final file = File(seg.filePath!);
      if (!await file.exists()) {
        appLogger.w('[SegmentCacheManager] 文件已过期: ${seg.filePath}');
        return null;
      }
      try {
        final data = await file.readAsBytes();
        final uint8Data = Uint8List.fromList(data);
        if (seg.data == null && _memUsed < _memLimit) {
          seg.data = uint8Data;
          _memUsed++;
        }
        seg.lastAccess = DateTime.now().millisecondsSinceEpoch;
        return uint8Data;
      } catch (e) {
        appLogger.e('[SegmentCacheManager] 读取分片文件失败: ${seg.filePath}', error: e);
        return null;
      }
    }

    return null;
  }

  // ==================== 状态变更（加锁保护） ====================

  /// 标记分片下载完成 — 使用 _guarded 防止多 Worker 竞态
  Future<void> markSegmentDone(int index, Uint8List data) async {
    return _guarded(() async {
      final seg = _segments[index];
      if (seg == null) return;
      if (seg.status == SegmentStatus.done) return; // 幂等保护

      final segPath = '$segmentDir/seg_${index.toString().padLeft(4, '0')}.ts';
      try {
        final dir = Directory(segmentDir);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        await File(segPath).writeAsBytes(data);
      } catch (e) {
        appLogger.e('[SegmentCacheManager] 写入分片文件失败: $segPath', error: e);
        seg.status = SegmentStatus.failed;
        seg.closeAllConsumers();
        return;
      }

      seg.filePath = segPath;
      seg.data = data;
      seg.status = SegmentStatus.done;
      seg.markDone();
      _doneCount++;
      seg.closeAllConsumers();

      if (_memUsed < _memLimit) {
        _memUsed++;
      } else {
        seg.data = null;
      }

      appLogger.d('[SegmentCacheManager] 分片完成: index=$index, bytes=${data.length}, done=$_doneCount/$totalSegments, memUsed=$_memUsed');

      if (isAllDone && !_allDoneFired && _onAllDone != null) {
        _allDoneFired = true;
        _onAllDone!();
      }
    });
  }

  /// 标记分片下载失败 — 使用 _guarded 防止与 markSegmentDone 竞态
  Future<void> markSegmentFailed(int index) async {
    return _guarded(() async {
      final seg = _segments[index];
      if (seg == null) return;
      if (seg.status == SegmentStatus.done) return; // 已完成的不覆盖
      seg.status = SegmentStatus.failed;
      seg.closeAllConsumers();
    });
  }

  /// 重置 Downloading 状态为 Pending — 对应后端 ResetDownloadingToPending
  ///
  /// 当 Worker 任务被取消时（如 seek 后中断专属 Worker），将分片状态从
  /// downloading 重置为 pending，避免状态泄漏导致无人继续下载该分片。
  /// 仅当状态为 downloading 时重置，其他状态不受影响。
  ///
  /// 同步方法：仅修改内存中的状态标志，不涉及 I/O 操作。
  /// 不使用 _guarded 保护，因为调用方（cancelCurrentTask 后）已确保
  /// 没有其他 Worker 在下载同一分片（每个分片同时只有一个 Worker 下载）。
  void resetDownloadingToPending(int index) {
    final seg = _segments[index];
    if (seg == null) return;
    if (seg.status == SegmentStatus.downloading) {
      seg.status = SegmentStatus.pending;
      appLogger.d('[SegmentCacheManager] 重置分片状态: index=$index, downloading -> pending');
    }
  }

  void setOnAllDone(void Function()? fn) {
    _onAllDone = fn;
    if (isAllDone && fn != null && !_allDoneFired) {
      _allDoneFired = true;
      fn();
    }
  }

  // ==================== 流式推送 ====================

  void broadcastChunk(int index, Uint8List chunk) {
    final seg = _segments[index];
    if (seg == null) return;
    final consumers = List<SegmentConsumer>.from(seg.consumers);
    for (final consumer in consumers) {
      consumer.sendData(chunk);
    }
  }

  // ==================== 内存管理 ====================

  /// LRU 淘汰内存缓存 — 使用 _guarded 保护 _memUsed
  Future<void> evictMemoryCache() async {
    return _guarded(() async {
      if (_memUsed <= _memLimit) return;

      final entries = <_CacheEntry>[];
      for (final seg in _segments.values) {
        if (seg.data != null && seg.status == SegmentStatus.done) {
          entries.add(_CacheEntry(index: seg.index, lastAccess: seg.lastAccess));
        }
      }

      entries.sort((a, b) => a.lastAccess.compareTo(b.lastAccess));

      final targetCount = _memLimit ~/ 2;
      var evicted = 0;

      for (final entry in entries) {
        if (_memUsed <= targetCount) break;
        final seg = _segments[entry.index];
        if (seg != null && seg.data != null) {
          seg.data = null;
          _memUsed--;
          evicted++;
        }
      }

      if (evicted > 0) {
        appLogger.i('[SegmentCacheManager] LRU 淘汰内存缓存: count=$evicted, memUsed=$_memUsed');
      }
    });
  }

  /// 滑动窗口淘汰 — 使用 _guarded 保护 _memUsed
  Future<void> slideWindow(int centerIndex) async {
    return _guarded(() async {
      const windowBefore = 3;
      const windowAfter = 5;

      int windowStart, windowEnd;
      if (centerIndex < 0) {
        windowStart = totalSegments;
        windowEnd = -1;
      } else {
        windowStart = centerIndex - windowBefore;
        if (windowStart < 0) windowStart = 0;
        windowEnd = centerIndex + windowAfter;
        if (windowEnd >= totalSegments) windowEnd = totalSegments - 1;
      }

      var evicted = 0;
      for (final seg in _segments.values) {
        if (seg.index < windowStart || seg.index > windowEnd) {
          if (seg.data != null) {
            seg.data = null;
            _memUsed--;
            evicted++;
          }
        }
      }

      if (evicted > 0) {
        appLogger.d('[SegmentCacheManager] 滑动窗口淘汰: center=$centerIndex, window=[$windowStart,$windowEnd], evicted=$evicted');
      }
    });
  }

  // ==================== 磁盘缓存恢复 ====================

  void _restoreFromDisk() {
    final dir = Directory(segmentDir);
    if (!dir.existsSync()) return;

    final segFileRegex = RegExp(r'^seg_(\d+)\.ts$');
    var restored = 0;

    for (final entity in dir.listSync()) {
      if (entity is! File) continue;

      final name = entity.path.split('/').last;
      final matches = segFileRegex.firstMatch(name);
      if (matches == null || matches.groupCount != 1) continue;

      final index = int.tryParse(matches.group(1)!);
      if (index == null || index < 0 || index >= totalSegments) continue;

      try {
        final size = entity.lengthSync();
        if (size == 0) continue;
      } catch (_) {
        continue;
      }

      final seg = _segments[index];
      if (seg != null && seg.status == SegmentStatus.pending) {
        seg.status = SegmentStatus.done;
        seg.filePath = entity.path;
        seg.lastAccess = DateTime.now().millisecondsSinceEpoch;
        seg.markDone();
        _doneCount++;
        restored++;
      }
    }

    if (restored > 0) {
      appLogger.i('[SegmentCacheManager] 磁盘缓存恢复: restored=$restored, total=$totalSegments');
    }
  }

  Future<void> cleanup(bool keepDisk) async {
    if (!keepDisk) {
      final dir = Directory(segmentDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }

    for (final seg in _segments.values) {
      seg.closeAllConsumers();
    }
    _segments.clear();
  }
}

/// 内存缓存条目（LRU 排序用）
class _CacheEntry {
  final int index;
  final int lastAccess;

  const _CacheEntry({required this.index, required this.lastAccess});
}
