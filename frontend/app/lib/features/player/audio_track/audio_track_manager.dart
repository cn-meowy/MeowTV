import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../../../core/logger/app_logger.dart';
import 'audio_track_model.dart';

/// 音轨管理器 — 管理音轨状态与切换
///
/// 直接使用 video_player 内置的 getAudioTracks / selectAudioTrack API，
/// 无需自定义平台通道。
class AudioTrackManager extends ChangeNotifier {
  List<AudioTrack> _tracks = [];
  AudioTrack? _activeTrack;
  bool _isLoading = false;

  List<AudioTrack> get tracks => List.unmodifiable(_tracks);
  AudioTrack? get activeTrack => _activeTrack;
  bool get isLoading => _isLoading;

  /// 是否有多条音轨（仅 >1 时显示音轨入口）
  bool get hasMultipleTracks => _tracks.length > 1;

  /// 从 video_player 获取音轨列表
  Future<void> fetchTracks(VideoPlayerController controller) async {
    if (_isLoading) return;

    // 检查平台是否支持音轨 API
    if (!controller.isAudioTrackSupportAvailable()) {
      appLogger.d('[AudioTrack] 当前平台不支持音轨切换');
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final videoTracks = await controller.getAudioTracks();
      _tracks = videoTracks.map((t) => AudioTrack(
        id: t.id,
        label: t.label ?? t.language ?? '音轨 ${t.id}',
        language: t.language,
        channelCount: t.channelCount,
        codec: t.codec,
        isActive: t.isSelected,
      )).toList();

      // 找到当前激活的音轨
      _activeTrack = _tracks.where((t) => t.isActive).firstOrNull ?? _tracks.firstOrNull;

      appLogger.i('[AudioTrack] 获取到 ${_tracks.length} 条音轨'
          '${_activeTrack != null ? "，当前: ${_activeTrack!.label}" : ""}');
    } catch (e) {
      appLogger.e('[AudioTrack] 获取音轨列表异常', error: e);
      _tracks = [];
      _activeTrack = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 切换到指定音轨
  Future<bool> selectTrack(AudioTrack track, VideoPlayerController controller) async {
    if (track.id == _activeTrack?.id) return true;

    appLogger.i('[AudioTrack] 切换音轨: ${track.label} (id=${track.id})');

    try {
      await controller.selectAudioTrack(track.id);
      _activeTrack = track;
      // 更新 tracks 列表中的 isActive 状态
      _tracks = _tracks.map((t) => t.copyWith(isActive: t.id == track.id)).toList();
      notifyListeners();
      return true;
    } catch (e) {
      appLogger.e('[AudioTrack] 切换音轨失败', error: e);
      return false;
    }
  }

  /// 清晰度切换后重新应用当前音轨选择
  ///
  /// 清晰度切换会销毁并重建 VideoPlayerController，音轨选择会丢失。
  /// 此方法在新控制器初始化后调用，重新获取音轨并尝试恢复之前的选择。
  Future<void> reapplyAfterQualitySwitch(VideoPlayerController controller) async {
    final previousLanguage = _activeTrack?.language;
    final previousLabel = _activeTrack?.label;

    if (previousLanguage == null && previousLabel == null) return;

    appLogger.i('[AudioTrack] 清晰度切换后重新应用音轨: $previousLabel');
    // 重新获取音轨列表
    await fetchTracks(controller);

    // 尝试找到匹配的音轨并重新选择
    if (_tracks.length <= 1) return; // 单音轨无需切换

    final matched = _tracks.where((t) =>
      (t.language != null && t.language == previousLanguage) ||
      (t.label == previousLabel)
    ).firstOrNull;

    if (matched != null && matched.id != _activeTrack?.id) {
      await selectTrack(matched, controller);
    }
  }

  /// 重置状态（切换视频时调用）
  void reset({bool notify = true}) {
    _tracks = [];
    _activeTrack = null;
    _isLoading = false;
    if (notify) notifyListeners();
  }
}
