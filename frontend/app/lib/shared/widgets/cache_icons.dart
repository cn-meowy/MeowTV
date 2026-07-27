import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_theme.dart';

/// MeowTV 缓存图标封装
///
/// 提供统一的缓存相关 SVG 图标调用：
/// - 功能入口组（cache/cache_auto/cache_manual/cache_stream）：使用 currentColor，
///   由调用方通过 [color] 着色，遵循 [AppColors] 语义。
/// - 状态徽章组（cache_complete/cache_caching/cache_paused/cache_partial）：
///   SVG 内含固定语义色，无需调用方着色，14px 角标场景保证可辨识。
///
/// 设计文档：docs/superpowers/specs/2026-07-17-cache-icons-design.md
class CacheIcons {
  CacheIcons._();

  // ── 功能入口组 ────────────────────────────────────────────────────────

  /// 通用缓存入口（文件 + 下载箭头）。
  ///
  /// 替代 `Icons.cached`。默认 textMuted，可传 [color] 覆盖（如 primary）。
  static Widget cache({
    double size = 20,
    Color? color,
    BuildContext? context,
  }) =>
      _entryIcon('assets/images/cache.svg', size, color, context);

  /// 自动缓存分区图标（文件 + 箭头 + 右下圆点）。
  ///
  /// 用于播放缓存管理 Sheet 自动缓存分区标题，颜色 primary。
  static Widget cacheAuto({
    double size = 20,
    Color? color,
    BuildContext? context,
  }) =>
      _entryIcon('assets/images/cache_auto.svg', size, color, context);

  /// 手动缓存分区图标（文件 + 箭头 + 右下加号）。
  ///
  /// 用于播放缓存管理 Sheet 手动缓存分区标题，颜色 warning。
  static Widget cacheManual({
    double size = 20,
    Color? color,
    BuildContext? context,
  }) =>
      _entryIcon('assets/images/cache_manual.svg', size, color, context);

  /// 流代理缓存分区图标（文件 + 箭头 + 右下对勾）。
  ///
  /// 用于播放缓存管理 Sheet 流代理缓存分区标题，颜色 success。
  static Widget cacheStream({
    double size = 20,
    Color? color,
    BuildContext? context,
  }) =>
      _entryIcon('assets/images/cache_stream.svg', size, color, context);

  // ── 状态徽章组 ────────────────────────────────────────────────────────

  /// 缓存完成徽章（success 实心圆 + 反色对勾）。
  ///
  /// 用于剧集角标完成态，替代 `Icons.download_done`。
  /// SVG 内含固定色，[size] 控制整体尺寸，无需 [color]。
  static Widget cacheComplete({double size = 14}) =>
      _badgeIcon('assets/images/cache_complete.svg', size);

  /// 缓存中徽章（primary 缺口圆，自带旋转动画）。
  ///
  /// 用于剧集角标缓存中态，替代 `CircularProgressIndicator`。
  /// 内部用 [AnimationBuilder] + [Transform.rotate] 实现旋转。
  static Widget cacheCaching({double size = 14}) =>
      _CacheCachingIcon(size: size);

  /// 缓存暂停徽章（warning 实心圆 + 反色双竖线）。
  ///
  /// 用于剧集角标暂停态，替代 `Icons.pause_circle_outline`。
  static Widget cachePaused({double size = 14}) =>
      _badgeIcon('assets/images/cache_paused.svg', size);

  /// 部分缓存徽章（warning 描边圆 + 右半填充）。
  ///
  /// 用于剧集角标部分缓存态（downloadedBytes > 0 且未完成）。
  /// Material 无此语义图标，必须自绘。
  static Widget cachePartial({double size = 14}) =>
      _badgeIcon('assets/images/cache_partial.svg', size);

  // ── 内部工具 ──────────────────────────────────────────────────────────

  /// 功能入口图标统一构造。color 为空时取 [context] 的 textMuted。
  static Widget _entryIcon(
    String asset,
    double size,
    Color? color,
    BuildContext? context,
  ) {
    final resolved = color ??
        (context != null ? context.colors.textMuted : const Color(0xFF9AA0A6));
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn),
    );
  }

  /// 状态徽章图标统一构造。SVG 内含固定语义色，不着色。
  static Widget _badgeIcon(String asset, double size) => SvgPicture.asset(
        asset,
        width: size,
        height: size,
      );
}

/// `cache_caching` 旋转动画徽章。
///
/// 使用 [AnimationBuilder] + [Transform.rotate] 实现持续旋转，
/// 与原 `CircularProgressIndicator` 行为一致，但视觉与全套缓存图标统一。
class _CacheCachingIcon extends StatefulWidget {
  final double size;
  const _CacheCachingIcon({required this.size});

  @override
  State<_CacheCachingIcon> createState() => _CacheCachingIconState();
}

class _CacheCachingIconState extends State<_CacheCachingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * 3.141592653589793,
          child: child,
        );
      },
      child: SvgPicture.asset(
        'assets/images/cache_caching.svg',
        width: widget.size,
        height: widget.size,
      ),
    );
  }
}
