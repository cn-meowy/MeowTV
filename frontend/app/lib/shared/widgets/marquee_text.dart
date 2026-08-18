import 'dart:async';

import 'package:flutter/material.dart';

/// 文本超长时自动横向无缝滚动的展示组件。
///
/// 行为：
/// - 先以 [staticMaxLines] 行静态展示，并用 [TextPainter] 测量是否溢出。
/// - 不溢出：静态渲染（多行自然换行，不截断）。
/// - 溢出：降级为单行 Marquee 横向滚动，文本 + 分隔符重复两段以实现无缝回绕。
///
/// 测量在 `addPostFrameCallback` 中进行，宽度来源由 [LayoutBuilder] 提供，
/// 因此父级必须给出有界水平宽度（`Expanded` / `Positioned(left,right)` 等即可）。
/// 不引入第三方 marquee 依赖；实现参照播放器内 `_ScrollingBanner` 的同模式。
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// 静态展示时尝试的最大行数；超长则降级为 1 行 marquee。
  final int staticMaxLines;

  /// 滚动速度，px/s，默认 30（与 [PlayerControlsStyles.castBannerScrollSpeed] 对齐）。
  final double speed;

  /// 段间分隔，默认 8 空格。
  final String separator;

  final StrutStyle? strutStyle;

  /// 可选外部传入宽度约束；为 null 时取 [LayoutBuilder] 的 maxWidth。
  /// 在无界水平滚动列表中需要显式传入以兜底。
  final double? maxWidth;

  final EdgeInsetsGeometry? padding;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.staticMaxLines = 1,
    this.speed = 30.0,
    this.separator = '        ',
    this.strutStyle,
    this.maxWidth,
    this.padding,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _controller = ScrollController();
  Timer? _timer;

  /// 是否需要滚动（内容超过可用宽度/行数时为 true）。
  bool _needsScroll = false;

  /// 单段（文本 + 分隔符）宽度，用于回绕计算。
  double _loopExtent = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndStart());
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.staticMaxLines != widget.staticMaxLines ||
        oldWidget.separator != widget.separator ||
        oldWidget.maxWidth != widget.maxWidth) {
      // 文本/样式/约束变化：重新测量并重置滚动
      _stop();
      if (_controller.hasClients) _controller.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndStart());
    }
  }

  @override
  void dispose() {
    _stop();
    _controller.dispose();
    super.dispose();
  }

  double _resolveMaxWidth(double layoutMaxWidth) {
    if (widget.maxWidth != null && widget.maxWidth!.isFinite) {
      return widget.maxWidth!;
    }
    return layoutMaxWidth;
  }

  void _measureAndStart() {
    if (!mounted) return;
    // LayoutBuilder 在 build 阶段已给出约束；此处通过当前 BuildContext 的 RenderBox
    // 取可用宽度更稳妥（与 _ScrollingBanner 一致地依赖已挂载的 RenderBox）。
    final renderBox = context.findRenderObject() as RenderBox?;
    double availableWidth;
    if (renderBox != null && renderBox.hasSize) {
      availableWidth = _resolveMaxWidth(renderBox.size.width);
    } else {
      // 兜底：用屏幕宽度，避免首帧测量失败导致永远不滚动。
      availableWidth = _resolveMaxWidth(
          MediaQuery.maybeSizeOf(context)?.width ?? double.infinity);
    }
    if (!availableWidth.isFinite || availableWidth <= 0) {
      // 无法确定宽度，延迟到下一帧再试
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndStart());
      }
      return;
    }

    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textAlign: widget.textAlign ?? TextAlign.start,
      textDirection: TextDirection.ltr,
      strutStyle: widget.strutStyle,
      maxLines: widget.staticMaxLines,
      ellipsis: '…',
    )..layout(maxWidth: availableWidth);

    final overflows = tp.didExceedMaxLines || tp.width > availableWidth;

    if (!overflows) {
      _needsScroll = false;
      if (mounted) setState(() {});
      return;
    }

    // 溢出：测量单段（文本 + 分隔符）宽度用于回绕
    final segTp = TextPainter(
      text: TextSpan(text: widget.text + widget.separator, style: widget.style),
      textDirection: TextDirection.ltr,
      strutStyle: widget.strutStyle,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);
    _loopExtent = segTp.width;
    _needsScroll = true;

    // 约 16ms 一帧推进，步长 = 速度(px/s) * 帧间隔(s)
    final step = widget.speed / 60.0;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_controller.hasClients) return;
      final next = _controller.offset + step;
      if (next >= _loopExtent) {
        _controller.jumpTo(next - _loopExtent);
      } else {
        _controller.jumpTo(next);
      }
    });
    if (mounted) setState(() {});
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        // LayoutBuilder 保证父级给出有界宽度；测量在 postFrame 中进行，
        // 这里仅负责渲染。若尚未测量完成，先按静态展示（避免空白闪烁）。
        return _buildContent();
      },
    );
    if (widget.padding != null) {
      content = Padding(padding: widget.padding!, child: content);
    }
    return content;
  }

  Widget _buildContent() {
    final textWidget = Text(
      widget.text,
      style: widget.style,
      textAlign: widget.textAlign,
      strutStyle: widget.strutStyle,
    );

    // 未滚动（或尚未测量完成时先静态展示）
    if (!_needsScroll) {
      return textWidget;
    }

    final segment = widget.text + widget.separator;
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(segment, style: widget.style, strutStyle: widget.strutStyle),
          // 重复一次以实现无缝回绕
          Text(segment, style: widget.style, strutStyle: widget.strutStyle),
        ],
      ),
    );
  }
}
