import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'danmaku_provider.dart';
import 'danmaku_renderer.dart';

/// 弹幕渲染层
class DanmakuLayer extends ConsumerStatefulWidget {
  const DanmakuLayer({super.key});

  @override
  ConsumerState<DanmakuLayer> createState() => _DanmakuLayerState();
}

class _DanmakuLayerState extends ConsumerState<DanmakuLayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 100),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(danmakuControllerProvider);

    if (!controller.isEnabled || controller.activeItems.isEmpty) {
      return const SizedBox.expand();
    }

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        return LayoutBuilder(builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size.isEmpty) return const SizedBox.expand();

          return CustomPaint(
            size: size,
            painter: DanmakuRenderer(
              activeItems: controller.activeItems,
              videoPosition: controller.currentPosition,
              speed: controller.speed,
              opacity: controller.opacity,
              fontSizeScale: controller.fontSizeScale,
              displayArea: controller.displayArea,
              trackManager: controller.trackManager,
            ),
          );
        });
      },
    );
  }
}
