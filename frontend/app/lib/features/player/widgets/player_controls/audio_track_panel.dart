import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../audio_track/audio_track_provider.dart';
import '../../audio_track/audio_track_model.dart';
import '../../playback/playback_provider.dart';
import 'styles.dart';

/// 音轨选择面板
class AudioTrackPanel extends ConsumerWidget {
  final VoidCallback onDismiss;
  final double scale;
  final double maxHeight;
  final double playerWidth;

  const AudioTrackPanel({
    super.key,
    required this.onDismiss,
    required this.scale,
    required this.maxHeight,
    required this.playerWidth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(audioTrackManagerProvider);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: PlayerControlsStyles.scaledWidth(220, playerWidth),
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: PlayerControlsStyles.panelBg,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(PlayerControlsStyles.scaledPadding(9, scale)),
            bottomLeft: Radius.circular(PlayerControlsStyles.scaledPadding(9, scale)),
          ),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 标题栏
          Padding(
            padding: EdgeInsets.fromLTRB(
              PlayerControlsStyles.scaledPadding(9, scale),
              PlayerControlsStyles.scaledPadding(9, scale),
              PlayerControlsStyles.scaledPadding(7, scale),
              PlayerControlsStyles.scaledPadding(7, scale),
            ),
            child: Row(children: [
              Text('音轨选择', style: TextStyle(
                color: PlayerControlsStyles.textColor,
                fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                fontWeight: FontWeight.w600,
              )),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close, color: PlayerControlsStyles.iconColor, size: PlayerControlsStyles.scaledFontSize(10, scale)),
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: PlayerControlsStyles.scaledPadding(28, scale), minHeight: PlayerControlsStyles.scaledPadding(28, scale)),
              ),
            ]),
          ),
          const Divider(color: Colors.white12, height: 1),

          // 加载指示器
          if (manager.isLoading)
            Padding(
              padding: EdgeInsets.all(PlayerControlsStyles.scaledPadding(20, scale)),
              child: Center(child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                  color: PlayerControlsStyles.speedActive,
                  strokeWidth: 2,
                ),
              )),
            ),

          // 音轨列表
          if (!manager.isLoading) ...[
            Flexible(
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final track in manager.tracks)
                    _TrackItem(
                      track: track,
                      isActive: track.id == manager.activeTrack?.id,
                      onTap: () async {
                        // 获取 VideoPlayerController
                        final chewie = globalChewieNotifier.value;
                        if (chewie == null) return;
                        final vpc = chewie.videoPlayerController;

                        final success = await ref
                            .read(audioTrackManagerProvider)
                            .selectTrack(track, vpc);
                        if (success) {
                          onDismiss();
                        } else {
                          // 切换失败提示
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('音轨切换失败'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      },
                      scale: scale,
                    ),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _TrackItem extends StatelessWidget {
  final AudioTrack track;
  final bool isActive;
  final VoidCallback onTap;
  final double scale;

  const _TrackItem({
    required this.track,
    required this.isActive,
    required this.onTap,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          PlayerControlsStyles.scaledPadding(9, scale),
          PlayerControlsStyles.scaledPadding(9, scale),
          PlayerControlsStyles.scaledPadding(9, scale),
          PlayerControlsStyles.scaledPadding(9, scale),
        ),
        child: Row(children: [
          // 选中指示圆点
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? PlayerControlsStyles.speedActive : Colors.transparent,
              border: Border.all(
                color: isActive ? PlayerControlsStyles.speedActive : PlayerControlsStyles.speedInactive,
                width: 1.5,
              ),
            ),
          ),
          SizedBox(width: PlayerControlsStyles.scaledPadding(9, scale)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(track.label, style: TextStyle(
                color: isActive ? PlayerControlsStyles.speedActive : PlayerControlsStyles.textColor,
                fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              )),
              if (track.subtitle.isNotEmpty)
                Text(track.subtitle, style: TextStyle(
                  color: PlayerControlsStyles.textSecondary,
                  fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                )),
            ]),
          ),
          if (isActive)
            Icon(Icons.check, color: PlayerControlsStyles.speedActive, size: PlayerControlsStyles.scaledFontSize(10, scale)),
        ]),
      ),
    );
  }
}
