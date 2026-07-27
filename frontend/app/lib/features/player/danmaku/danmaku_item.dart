/// 弹幕模式
enum DanmakuMode {
  scroll,        // 右→左滚动 (B站 mode 1)
  topFixed,      // 顶部固定居中 (B站 mode 4)
  bottomFixed,   // 底部固定居中 (B站 mode 5)
}

/// 弹幕样式
class DanmakuStyle {
  final int fontSize;          // 字号 (px)
  final int color;             // 0xAARRGGBB
  final double opacity;        // 0.0 - 1.0
  final bool showStroke;       // 是否显示描边
  final int strokeColor;       // 描边颜色
  final double strokeWidth;    // 描边宽度

  const DanmakuStyle({
    this.fontSize = 25,
    this.color = 0xFFFFFFFF,
    this.opacity = 1.0,
    this.showStroke = true,
    this.strokeColor = 0xFF000000,
    this.strokeWidth = 2.0,
  });

  DanmakuStyle copyWith({
    int? fontSize,
    int? color,
    double? opacity,
    bool? showStroke,
    int? strokeColor,
    double? strokeWidth,
  }) {
    return DanmakuStyle(
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
      showStroke: showStroke ?? this.showStroke,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }
}

/// 弹幕项（统一内部格式）
class DanmakuItem {
  final String id;
  final DanmakuMode mode;
  final Duration startTime;    // 出现时间（相对视频时间轴）
  final String content;        // 文本内容
  final DanmakuStyle style;

  // 运行时状态（由渲染引擎维护）
  double? currentX;            // 当前 X 坐标
  double? currentY;            // 当前 Y 坐标
  int? assignedTrack;          // 分配的轨道号
  bool isActive;               // 是否正在屏幕上
  double? measuredWidth;       // 预计算的文本宽度

  DanmakuItem({
    required this.id,
    required this.mode,
    required this.startTime,
    required this.content,
    this.style = const DanmakuStyle(),
    this.currentX,
    this.currentY,
    this.assignedTrack,
    this.isActive = false,
    this.measuredWidth,
  });
}

/// 弹幕显示区域
enum DanmakuDisplayArea {
  full,        // 全屏
  topHalf,     // 上半屏
  bottomHalf,  // 下半屏
  quarterTop,  // 顶部 1/4
}

/// 弹幕过滤设置
class DanmakuFilter {
  final bool scrollEnabled;
  final bool topFixedEnabled;
  final bool bottomFixedEnabled;
  final List<int> blockColors;
  final Set<String> blockUsers;
  final int minFontSize;
  final int maxFontSize;

  const DanmakuFilter({
    this.scrollEnabled = true,
    this.topFixedEnabled = true,
    this.bottomFixedEnabled = true,
    this.blockColors = const [],
    this.blockUsers = const {},
    this.minFontSize = 0,
    this.maxFontSize = 999,
  });

  DanmakuFilter copyWith({
    bool? scrollEnabled,
    bool? topFixedEnabled,
    bool? bottomFixedEnabled,
    List<int>? blockColors,
    Set<String>? blockUsers,
    int? minFontSize,
    int? maxFontSize,
  }) {
    return DanmakuFilter(
      scrollEnabled: scrollEnabled ?? this.scrollEnabled,
      topFixedEnabled: topFixedEnabled ?? this.topFixedEnabled,
      bottomFixedEnabled: bottomFixedEnabled ?? this.bottomFixedEnabled,
      blockColors: blockColors ?? this.blockColors,
      blockUsers: blockUsers ?? this.blockUsers,
      minFontSize: minFontSize ?? this.minFontSize,
      maxFontSize: maxFontSize ?? this.maxFontSize,
    );
  }
}
