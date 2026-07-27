import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_theme.dart';

/// Loading shimmer placeholder.
class LoadingShimmer extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const LoadingShimmer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Shimmer.fromColors(
      baseColor: colors.card,
      highlightColor: colors.elevated,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: borderRadius ?? BorderRadius.circular(AppTheme.radiusCard),
        ),
      ),
    );
  }
}
