import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../cast/cast_provider.dart';
import 'playback_controller.dart';

/// 全局 ChewieController ValueNotifier
///
/// PlayerScreen 持有此 notifier 并在创建/销毁 controller 时更新它，
/// PlaybackController 监听它以同步本地播放源。
final globalChewieNotifier = ValueNotifier<ChewieController?>(null);

/// 全局 PlaybackController Provider
///
/// ChewieController 由 PlayerScreen 动态创建/销毁，
/// 通过 [globalChewieNotifier] 同步到 PlaybackController。
final playbackControllerProvider = ChangeNotifierProvider<PlaybackController>((ref) {
  final castService = ref.watch(castServiceProvider);
  final controller = PlaybackController(
    chewieNotifier: globalChewieNotifier,
    castService: castService,
  );
  ref.onDispose(() => controller.dispose());
  return controller;
});
