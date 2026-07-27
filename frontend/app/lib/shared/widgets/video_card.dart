import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import 'favorite_star_button.dart';

/// Video card widget — replaces MovieCard with design-spec aligned styling.
class VideoCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final String? badge;
  final Map<String, String>? httpHeaders;
  final VoidCallback onTap;

  // Favorite star parameters
  final int? vodId;
  final String? vodName;
  final String? vodPic;
  final String? doubanId;
  final String? resourceDomain;
  final String? resourceName;

  const VideoCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.badge,
    this.httpHeaders,
    required this.onTap,
    this.vodId,
    this.vodName,
    this.vodPic,
    this.doubanId,
    this.resourceDomain,
    this.resourceName,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) => setState(() => _hovered = false),
      onTapCancel: () => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: AppTheme.cardWidth,
        transform: Matrix4.identity()..scaleByDouble(_hovered ? 0.95 : 1.0, _hovered ? 0.95 : 1.0, 1.0, 1.0),
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
                child: CachedNetworkImage(
                    imageUrl: widget.imageUrl,
                    httpHeaders: widget.httpHeaders,
                    fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: colors.card),
                  errorWidget: (_, _, _) => Container(
                    color: colors.card,
                    child: Center(child: Icon(Icons.movie, color: colors.textMuted, size: 40)),
                  ),
                ),
              ),
              // Badge
              if (widget.badge != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.badge!,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              // Favorite star (top-right)
              if (widget.vodName != null && (widget.vodId != null || widget.doubanId != null))
                Positioned(
                  top: 8,
                  right: 8,
                  child: FavoriteStarButton(
                    vodId: widget.vodId,
                    vodName: widget.vodName!,
                    vodPic: widget.vodPic,
                    doubanId: widget.doubanId,
                    resourceDomain: widget.resourceDomain,
                    resourceName: widget.resourceName,
                    mode: FavoriteStarMode.card,
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
                        widget.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 4),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          shadows: [
                            Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 3),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
