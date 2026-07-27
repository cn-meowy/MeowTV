import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/m3u8_check_result.dart';
import '../../features/detail/m3u8_check_provider.dart';

/// M3u8 URL 检测状态指示器
/// 显示在播放源 Tab 或剧集按钮上
class M3u8StatusIndicator extends ConsumerWidget {
  /// 要检测的 URL
  final String url;
  /// 指示器大小
  final double size;
  /// 是否显示文字错误信息（tooltip）
  final bool showTooltip;

  const M3u8StatusIndicator({
    super.key,
    required this.url,
    this.size = 12,
    this.showTooltip = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkState = ref.watch(m3u8CheckProvider);
    final status = checkState.statusOf(url);
    final error = checkState.errorOf(url);

    final Widget indicator;
    switch (status) {
      case UrlCheckStatus.unchecked:
        indicator = Icon(Icons.circle_outlined, size: size, color: Colors.grey);
        break;
      case UrlCheckStatus.checking:
        indicator = SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade300),
          ),
        );
        break;
      case UrlCheckStatus.available:
        indicator = Icon(Icons.check_circle, size: size, color: Colors.green);
        break;
      case UrlCheckStatus.unavailable:
        indicator = Icon(Icons.error, size: size, color: Colors.red);
        break;
    }

    if (!showTooltip || error == null || error.isEmpty) {
      return indicator;
    }

    return Tooltip(
      message: error,
      child: indicator,
    );
  }
}

/// 播放线路/资源可用性批量状态指示器
/// 当整条线路有任一 URL 不可用时显示警告
class M3u8SourceStatusBadge extends ConsumerWidget {
  /// 该线路的所有剧集 URLs
  final List<String> urls;
  /// 徽章尺寸
  final double size;

  const M3u8SourceStatusBadge({
    super.key,
    required this.urls,
    this.size = 12,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkState = ref.watch(m3u8CheckProvider);

    // 统计该线路的检测状态
    int unchecked = 0;
    int checking = 0;
    int available = 0;
    int unavailable = 0;

    for (final url in urls) {
      final status = checkState.statusOf(url);
      switch (status) {
        case UrlCheckStatus.unchecked:
          unchecked++;
          break;
        case UrlCheckStatus.checking:
          checking++;
          break;
        case UrlCheckStatus.available:
          available++;
          break;
        case UrlCheckStatus.unavailable:
          unavailable++;
          break;
      }
    }

    // 如果全部检测完成且都可用，显示绿色勾
    if (unchecked == 0 && checking == 0 && unavailable == 0 && available > 0) {
      return Tooltip(
        message: '全部可用 ($available)',
        child: Icon(Icons.check_circle, size: size, color: Colors.green),
      );
    }

    // 如果有不可用，显示红色警告
    if (unavailable > 0) {
      return Tooltip(
        message: '$unavailable 个不可用',
        child: Icon(Icons.error, size: size, color: Colors.red),
      );
    }

    // 如果有检测中的
    if (checking > 0) {
      return Tooltip(
        message: '检测中...',
        child: SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade300),
          ),
        ),
      );
    }

    // 未检测或部分检测
    return Tooltip(
      message: '未检测',
      child: Icon(Icons.circle_outlined, size: size, color: Colors.grey),
    );
  }
}
