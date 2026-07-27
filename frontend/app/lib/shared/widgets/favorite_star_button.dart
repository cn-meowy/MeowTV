import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../features/favorites/favorite_toggle_provider.dart';

/// Display mode for the favorite star button.
enum FavoriteStarMode {
  /// Small circular star badge for card top-right corner (28x28).
  card,
  /// Text button with star icon + label.
  button,
  /// Icon-only button (24x24) for use in info panels alongside download/cache buttons.
  iconOnly,
}

/// A favorite star button that toggles favorite status via [favoriteToggleProvider].
///
/// Supports two modes:
/// - [FavoriteStarMode.card]: circular 28x28 badge, positioned at card top-right.
/// - [FavoriteStarMode.button]: row with star icon + "收藏"/"已收藏" text.
class FavoriteStarButton extends ConsumerStatefulWidget {
  final int? vodId;
  final String vodName;
  final String? vodPic;
  final String? doubanId;
  final String? resourceDomain;
  final String? resourceName;
  final String? groupKey;
  final FavoriteStarMode mode;

  const FavoriteStarButton({
    super.key,
    this.vodId,
    required this.vodName,
    this.vodPic,
    this.doubanId,
    this.resourceDomain,
    this.resourceName,
    this.groupKey,
    this.mode = FavoriteStarMode.card,
  });

  @override
  ConsumerState<FavoriteStarButton> createState() => _FavoriteStarButtonState();
}

class _FavoriteStarButtonState extends ConsumerState<FavoriteStarButton> {
  @override
  void initState() {
    super.initState();
    // Check favorite status on first build
    Future.microtask(() {
      ref.read(favoriteToggleProvider.notifier).checkFavorite(
            resourceDomain: widget.resourceDomain,
            vodId: widget.vodId,
            doubanId: widget.doubanId,
          );
    });
  }

  String get _key => FavoriteToggleNotifier.buildKey(
        resourceDomain: widget.resourceDomain,
        vodId: widget.vodId,
        doubanId: widget.doubanId,
      );

  void _toggle() {
    ref.read(favoriteToggleProvider.notifier).toggleFavorite(
          vodName: widget.vodName,
          vodPic: widget.vodPic,
          resourceDomain: widget.resourceDomain,
          resourceName: widget.resourceName,
          groupKey: widget.groupKey,
          vodId: widget.vodId,
          doubanId: widget.doubanId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final favState = ref.watch(favoriteToggleProvider);
    final isFav = favState.cache[_key] ?? false;
    final colors = context.colors;

    if (widget.mode == FavoriteStarMode.card) {
      return _buildCardMode(isFav, colors);
    } else if (widget.mode == FavoriteStarMode.iconOnly) {
      return _buildIconOnlyMode(isFav, colors);
    } else {
      return _buildButtonMode(isFav, colors);
    }
  }

  Widget _buildCardMode(bool isFav, AppColors colors) {
    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isFav
              ? colors.primary
              : Colors.black.withValues(alpha: 0.5),
        ),
        child: Icon(
          isFav ? Icons.star : Icons.star_outline,
          size: 16,
          color: isFav ? Colors.white : Colors.white.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  /// Icon-only 36x36 mode for use in info panels alongside download/cache buttons.
  Widget _buildIconOnlyMode(bool isFav, AppColors colors) {
    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isFav ? colors.primary.withValues(alpha: 0.15) : colors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isFav ? colors.primary.withValues(alpha: 0.4) : colors.border,
          ),
        ),
        child: Center(
          child: Icon(
            isFav ? Icons.star : Icons.star_outline,
            size: 18,
            color: isFav ? colors.primary : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildButtonMode(bool isFav, AppColors colors) {
    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isFav ? colors.primary.withValues(alpha: 0.15) : colors.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusTag),
          border: Border.all(
            color: isFav ? colors.primary.withValues(alpha: 0.4) : colors.border,
          ),
        ),
        child: Icon(
          isFav ? Icons.star : Icons.star_outline,
          size: 18,
          color: isFav ? colors.primary : colors.textSecondary,
        ),
      ),
    );
  }
}
