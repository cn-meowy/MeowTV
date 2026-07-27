import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 定时关闭状态
class SleepTimerState {
  final bool isActive;
  final int remainingSeconds;
  final int totalSeconds;

  const SleepTimerState({
    this.isActive = false,
    this.remainingSeconds = 0,
    this.totalSeconds = 0,
  });

  SleepTimerState copyWith({
    bool? isActive,
    int? remainingSeconds,
    int? totalSeconds,
  }) =>
      SleepTimerState(
        isActive: isActive ?? this.isActive,
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
        totalSeconds: totalSeconds ?? this.totalSeconds,
      );

  /// 格式化剩余时间为 mm:ss
  String get remainingFormatted {
    final m = remainingSeconds ~/ 60;
    final s = remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// 定时关闭 Notifier
class SleepTimerNotifier extends StateNotifier<SleepTimerState> {
  Timer? _timer;
  VoidCallback? _onExpired;

  SleepTimerNotifier() : super(const SleepTimerState());

  void setOnExpired(VoidCallback? callback) {
    _onExpired = callback;
  }

  /// 启动定时器（秒为单位）
  void startTimer(int seconds) {
    _timer?.cancel();
    if (seconds <= 0) return;
    state = SleepTimerState(
      isActive: true,
      remainingSeconds: seconds,
      totalSeconds: seconds,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = state.remainingSeconds - 1;
      if (remaining <= 0) {
        _timer?.cancel();
        state = const SleepTimerState();
        _onExpired?.call();
      } else {
        state = state.copyWith(remainingSeconds: remaining);
      }
    });
  }

  /// 启动定时器（分钟为单位）
  void startTimerMinutes(int minutes) => startTimer(minutes * 60);

  /// 取消定时器
  void cancelTimer() {
    _timer?.cancel();
    state = const SleepTimerState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// 定时关闭 Provider
final sleepTimerProvider =
    StateNotifierProvider<SleepTimerNotifier, SleepTimerState>((ref) {
  return SleepTimerNotifier();
});
