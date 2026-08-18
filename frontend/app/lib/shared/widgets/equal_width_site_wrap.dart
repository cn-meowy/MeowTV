import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/app_theme.dart';

/// A [Wrap]-like layout whose children are all forced to the same width,
/// computed from the **intrinsic content width** of the widest child rather
/// than the available space divided by the item count.
///
/// Width algorithm:
/// ```
/// available  = constraints.maxWidth - horizontalPadding * 2
/// contentMax = max(child.getMaxIntrinsicWidth(∞))
/// chipWidth  = contentMax.clamp(minItemWidth, available)
/// ```
///
/// Unlike the previous off-screen mirror + post-frame measurement design, the
/// intrinsic width is measured **synchronously inside [RenderObject.performLayout]**
/// by the custom [RenderObject]. This eliminates the `Stack`/`Positioned` mirror
/// layer (which caused a `StackParentData` vs `WrapParentData` conflict) and the
/// `addPostFrameCallback` + `setState` feedback loop (which raced with
/// `flushSemantics` and tripped the `!semantics.parentDataDirty` assertion).
/// The correct width is produced on the very first frame with no jump.
///
/// Public API is unchanged; callers pass [itemCount] and [children] as before.
class EqualWidthSiteWrap extends StatelessWidget {
  /// Number of items. Kept for API compatibility; must match [children].length.
  final int itemCount;

  /// Horizontal padding already applied by the ancestor (defaults to
  /// [AppTheme.md]). Subtracted from the available width.
  final double horizontalPadding;

  /// Horizontal gap between chips (defaults to [AppTheme.sm]).
  final double spacing;

  /// Vertical gap between rows (defaults to [AppTheme.sm]).
  final double runSpacing;

  /// Minimum chip width to prevent extreme squashing on very narrow screens.
  /// Defaults to 64.
  final double minItemWidth;

  /// The chip widgets. Each is laid out at the computed equal width.
  final List<Widget> children;

  const EqualWidthSiteWrap({
    super.key,
    required this.itemCount,
    required this.children,
    this.horizontalPadding = AppTheme.md,
    this.spacing = AppTheme.sm,
    this.runSpacing = AppTheme.sm,
    this.minItemWidth = 64.0,
  });

  @override
  Widget build(BuildContext context) {
    return _EqualWidthWrap(
      spacing: spacing,
      runSpacing: runSpacing,
      minItemWidth: minItemWidth,
      horizontalPadding: horizontalPadding,
      children: children,
    );
  }
}

/// [MultiChildRenderObjectWidget] that configures [_RenderEqualWidthWrap].
class _EqualWidthWrap extends MultiChildRenderObjectWidget {
  final double spacing;
  final double runSpacing;
  final double minItemWidth;
  final double horizontalPadding;

  const _EqualWidthWrap({
    required this.spacing,
    required this.runSpacing,
    required this.minItemWidth,
    required this.horizontalPadding,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderEqualWidthWrap(
      spacing: spacing,
      runSpacing: runSpacing,
      minItemWidth: minItemWidth,
      horizontalPadding: horizontalPadding,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderEqualWidthWrap renderObject,
  ) {
    renderObject
      ..spacing = spacing
      ..runSpacing = runSpacing
      ..minItemWidth = minItemWidth
      ..horizontalPadding = horizontalPadding;
  }
}

/// Custom [RenderBox] that measures the widest child's intrinsic width and lays
/// out all children at that equal width using a greedy wrap-flow algorithm.
///
/// Uses [WrapParentData] (via [setupParentData]) so children receive the same
/// parent data type a real [Wrap] would assign — this is the fix that removes
/// the parentData-type conflict that caused the semantics assertion.
class _RenderEqualWidthWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, WrapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, WrapParentData> {
  _RenderEqualWidthWrap({
    required double spacing,
    required double runSpacing,
    required double minItemWidth,
    required double horizontalPadding,
  })  : _spacing = spacing,
        _runSpacing = runSpacing,
        _minItemWidth = minItemWidth,
        _horizontalPadding = horizontalPadding;

  double _spacing;
  double get spacing => _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  double _runSpacing;
  double get runSpacing => _runSpacing;
  set runSpacing(double value) {
    if (_runSpacing == value) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  double _minItemWidth;
  double get minItemWidth => _minItemWidth;
  set minItemWidth(double value) {
    if (_minItemWidth == value) return;
    _minItemWidth = value;
    markNeedsLayout();
  }

  double _horizontalPadding;
  double get horizontalPadding => _horizontalPadding;
  set horizontalPadding(double value) {
    if (_horizontalPadding == value) return;
    _horizontalPadding = value;
    markNeedsLayout();
  }

  /// Assign [WrapParentData] to each child. This is the key fix: it guarantees
  /// children carry the correct parent data type (never `StackParentData`),
  /// eliminating the dirty-parentData conflict seen during `flushSemantics`.
  @override
  void setupParentData(covariant RenderObject child) {
    if (child.parentData is! WrapParentData) {
      child.parentData = WrapParentData();
    }
  }

  /// Computes the equal chip width for the given constraints.
  ///
  /// `available` subtracts `horizontalPadding * 2` (matching the previous
  /// formula) and clamps the measured max intrinsic width into
  /// `[minItemWidth, available]`.
  double _resolveChipWidth(BoxConstraints constraints) {
    final available =
        (constraints.maxWidth - _horizontalPadding * 2).clamp(0.0, double.infinity);
    double contentMax = 0.0;
    var child = firstChild;
    while (child != null) {
      final w = child.getMaxIntrinsicWidth(double.infinity);
      if (w > contentMax) contentMax = w;
      child = childAfter(child);
    }
    final upper = available.isFinite ? available : _minItemWidth;
    return contentMax.clamp(_minItemWidth, upper < _minItemWidth ? _minItemWidth : upper);
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    if (firstChild == null) {
      size = constraints.constrain(Size.zero);
      return;
    }

    final chipWidth = _resolveChipWidth(constraints);
    // The wrap boundary uses the real available width (constraints.maxWidth),
    // matching Wrap's behavior; chipWidth is clamped against the
    // padding-adjusted available width — identical arithmetic to before.
    final wrapWidth = constraints.maxWidth;

    double x = 0.0;
    double y = 0.0;
    double rowH = 0.0;
    double maxRowW = 0.0;

    var child = firstChild;
    while (child != null) {
      if (x > 0.0 && x + chipWidth > wrapWidth) {
        // Wrap to next row.
        y += rowH + _runSpacing;
        x = 0.0;
        rowH = 0.0;
      }
      child.layout(
        BoxConstraints.tightFor(width: chipWidth),
        parentUsesSize: true,
      );
      final parentData = child.parentData as WrapParentData;
      parentData.offset = Offset(x, y);
      final childH = child.size.height;
      if (childH > rowH) rowH = childH;
      x += chipWidth + _spacing;
      final rowEnd = x - _spacing; // width consumed by this row so far
      if (rowEnd > maxRowW) maxRowW = rowEnd;
      child = childAfter(child);
    }

    final width = constraints.constrainWidth(maxRowW);
    final height = constraints.constrainHeight(y + rowH);
    size = Size(width, height);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    if (firstChild == null) {
      return constraints.constrain(Size.zero);
    }
    final chipWidth = _resolveChipWidth(constraints);
    final wrapWidth = constraints.maxWidth;

    double x = 0.0;
    double y = 0.0;
    double rowH = 0.0;
    double maxRowW = 0.0;

    var child = firstChild;
    while (child != null) {
      if (x > 0.0 && x + chipWidth > wrapWidth) {
        y += rowH + _runSpacing;
        x = 0.0;
        rowH = 0.0;
      }
      final childSize = ChildLayoutHelper.dryLayoutChild(
        child,
        BoxConstraints.tightFor(width: chipWidth),
      );
      final childH = childSize.height;
      if (childH > rowH) rowH = childH;
      x += chipWidth + _spacing;
      final rowEnd = x - _spacing;
      if (rowEnd > maxRowW) maxRowW = rowEnd;
      child = childAfter(child);
    }

    return constraints.constrain(Size(maxRowW, y + rowH));
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    return _intrinsicDimension(
      (child) => child.getMinIntrinsicWidth(height),
    );
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return _intrinsicDimension(
      (child) => child.getMaxIntrinsicWidth(height),
    );
  }

  double _intrinsicDimension(double Function(RenderBox) measure) {
    var child = firstChild;
    if (child == null) return 0.0;
    double max = 0.0;
    while (child != null) {
      final v = measure(child);
      if (v > max) max = v;
      child = childAfter(child);
    }
    return max;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
