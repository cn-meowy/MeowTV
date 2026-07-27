import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/search_result.dart';
import '../../features/favorites/favorite_toggle_provider.dart';

/// Helper: first non-null/non-empty value of a field among items.
T? _firstOf<T>(List<SearchResultItem> items, T? Function(SearchResultItem) selector) {
  for (final item in items) {
    final v = selector(item);
    if (v != null && v.toString().isNotEmpty) return v;
  }
  return null;
}

/// Pick best score: prefer douban_score, then score.
String _pickScore(List<SearchResultItem> items) {
  final db = items.firstWhere(
    (i) => i.doubanScore != null && i.doubanScore!.isNotEmpty,
    orElse: () => items.first,
  );
  if (db.doubanScore != null && db.doubanScore!.isNotEmpty) return db.doubanScore!;
  final sc = items.firstWhere(
    (i) => i.score != null && i.score!.isNotEmpty,
    orElse: () => items.first,
  );
  return sc.score ?? '';
}

/// Build cache key for NameGroupedCard favorite status.
/// Uses FavoriteToggleNotifier.buildKey with isNameGroup=true.
String _buildNameGroupFavKey(List<SearchResultItem> items) {
  final first = items.first;
  return FavoriteToggleNotifier.buildKey(
    resourceDomain: first.resourceDomain,
    vodId: first.vodId,
    doubanId: first.doubanId,
    isNameGroup: true,
  );
}

/// Name-grouped card — displays a single card for a group of search results
/// sharing the same groupKey (doubanId or title).
///
/// Mirrors Web NameGroupedCard.tsx behavior:
/// - Cover from first item with cover
/// - Aggregated meta: score, year, type, area, resource count
/// - Favorite star with name-group-aware cache key
/// - Tap navigates to detail with group_key + name + site
class NameGroupedCard extends ConsumerStatefulWidget {
  final List<SearchResultItem> items;
  final String groupKey;
  final String imageUrl;
  final Map<String, String>? httpHeaders;
  final VoidCallback? onTap;

  const NameGroupedCard({
    super.key,
    required this.items,
    required this.groupKey,
    required this.imageUrl,
    this.httpHeaders,
    this.onTap,
  });

  @override
  ConsumerState<NameGroupedCard> createState() => _NameGroupedCardState();
}

class _NameGroupedCardState extends ConsumerState<NameGroupedCard> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    // Check favorite status on first build — use isNameGroup for cache key
    Future.microtask(() {
      if (!mounted) return;
      final first = widget.items.first;
      ref.read(favoriteToggleProvider.notifier).checkFavorite(
            resourceDomain: first.resourceDomain,
            vodId: first.vodId,
            doubanId: first.doubanId,
            isNameGroup: true,
          );
    });
  }

  String get _favKey => _buildNameGroupFavKey(widget.items);

  bool get _isFav => ref.watch(favoriteToggleProvider).cache[_favKey] ?? false;

  void _toggleFavorite() {
    final first = widget.items.first;
    if (first.doubanId != null) {
      // Has doubanId: use doubanId + vod_name as identifier
      ref.read(favoriteToggleProvider.notifier).toggleFavorite(
            vodName: first.title,
            vodPic: first.cover,
            doubanId: first.doubanId,
            resourceDomain: first.resourceDomain,
            resourceName: first.resourceName,
            vodId: first.vodId,
            groupKey: widget.groupKey,
            isNameGroup: true,
          );
    } else {
      // No doubanId: use first item's vodId + resourceDomain
      ref.read(favoriteToggleProvider.notifier).toggleFavorite(
            vodName: first.title,
            vodPic: first.cover,
            resourceDomain: first.resourceDomain,
            resourceName: first.resourceName,
            vodId: first.vodId,
            groupKey: widget.groupKey,
            isNameGroup: true,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final displayScore = _pickScore(items);
    final year = _firstOf(items, (i) => i.year);
    final type = _firstOf(items, (i) => i.type);
    final area = _firstOf(items, (i) => i.area);
    final hasPlayUrl = items.any((i) => i.playUrl != null && i.playUrl!.isNotEmpty);
    final isFav = _isFav;
    final first = items.first;
    final colors = context.colors;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) => setState(() => _hovered = false),
      onTapCancel: () => setState(() => _hovered = false),
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: AppTheme.cardWidth,
      transform: Matrix4.identity()
          ..scaleByDouble(_hovered ? 0.97 : 1.0, _hovered ? 0.97 : 1.0, 1.0, 1.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          child: Stack(
            children: [
              // Poster image
              Positioned.fill(
                child: widget.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: widget.imageUrl,
                        httpHeaders: widget.httpHeaders,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: colors.card),
                        errorWidget: (_, _, _) => Container(
                          color: colors.card,
                          child: Center(
                              child: Icon(Icons.movie, color: colors.textMuted, size: 40)),
                        ),
                      )
                    : Container(
                        color: colors.card,
                        child: Center(
                            child: Icon(Icons.movie, color: colors.textMuted, size: 40)),
                      ),
              ),
              // --- Badges (top-left) ---
              Positioned(
                top: 8,
                left: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Rating badge
                    if (displayScore.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, size: 10, color: colors.warning),
                            const SizedBox(width: 2),
                            Text(
                              double.tryParse(displayScore)?.toStringAsFixed(1) ?? displayScore,
                              style: TextStyle(
                                  color: colors.warning, fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    // Resource count badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: hasPlayUrl
                            ? colors.primary
                            : colors.card.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        hasPlayUrl ? '可播放' : '${items.length}个资源',
                        style: TextStyle(
                          color: hasPlayUrl ? Colors.white : Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Favorite star (top-right)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: _toggleFavorite,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFav ? colors.primary : Colors.black.withValues(alpha: 0.5),
                    ),
                    child: Icon(
                      isFav ? Icons.star : Icons.star_outline,
                      size: 16,
                      color: isFav ? Colors.white : Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),

              // Bottom info
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        first.title,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 4),
                            ]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Meta line: year / type / area
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          if (year != null)
                            Text(year, style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              shadows: [
                                Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 3),
                              ],
                            )),
                          if (type != null)
                            Text(type, style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              shadows: [
                                Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 3),
                              ],
                            )),
                          if (area != null)
                            Text(area, style: TextStyle(
                              color: Colors.white60,
                              fontSize: 10,
                              shadows: [
                                Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 3),
                              ],
                            )),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
