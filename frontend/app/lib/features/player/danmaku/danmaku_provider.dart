import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'danmaku_controller.dart';

final danmakuControllerProvider = ChangeNotifierProvider<DanmakuController>((ref) {
  final controller = DanmakuController();
  ref.onDispose(() => controller.dispose());
  return controller;
});
