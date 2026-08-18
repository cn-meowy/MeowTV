import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../player/widgets/player_controls/aspect_ratio_panel.dart';

/// 画面比例 Notifier
class DisplayAspectRatioNotifier extends StateNotifier<DisplayAspectRatio> {
  DisplayAspectRatioNotifier() : super(DisplayAspectRatio.autoAdapt);

  void setRatio(DisplayAspectRatio ratio) {
    state = ratio;
  }
}

/// 画面比例 Provider
final displayAspectRatioProvider =
    StateNotifierProvider<DisplayAspectRatioNotifier, DisplayAspectRatio>((ref) {
  return DisplayAspectRatioNotifier();
});
