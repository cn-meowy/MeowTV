import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/user_data.dart';
import '../favorites/favorites_provider.dart';
import '../settings/douban_image_proxy_provider.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(doubanImageProxyProvider.notifier).init();
      ref.read(favoritesProvider.notifier).loadFavorites();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(favoritesProvider);
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        }),
        actions: [
          if (state.items.isNotEmpty)
            TextButton(
              onPressed: () => _showClearDialog(context),
              child: Text('清空', style: TextStyle(color: colors.error)),
            ),
        ],
      ),
      body: state.isLoading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : state.items.isEmpty
              ? Center(child: Text('暂无收藏内容', style: TextStyle(color: colors.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(AppTheme.md),
                  itemCount: state.items.length,
                  itemBuilder: (context, i) => _FavoriteItemCard(
                    item: state.items[i],
                    onTap: () {
                      final item = state.items[i];
                      // If no resource domain or vodId, navigate to search page with douban_id + name
                      if (item.resourceDomain.isEmpty || item.vodId == 0) {
                        final encodedName = Uri.encodeComponent(item.vodName);
                        final doubanId = item.doubanId.isNotEmpty ? item.doubanId : '';
                        context.go('/search?douban_id=$doubanId&q=$encodedName');
                      } else {
                        context.push('/detail', extra: {
                          'resource_domain': item.resourceDomain,
                          'vod_id': item.vodId,
                        });
                      }
                    },
                    onDelete: () => ref.read(favoritesProvider.notifier).removeFavorite(state.items[i]),
                  ),
                ),
    );
  }

  void _showClearDialog(BuildContext context) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('清空收藏', style: TextStyle(color: colors.textPrimary)),
        content: Text('确定清空所有收藏？', style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              ref.read(favoritesProvider.notifier).clearFavorites();
              Navigator.pop(context);
            },
            child: Text('清空', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
  }
}

class _FavoriteItemCard extends ConsumerWidget {
  final FavoriteItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _FavoriteItemCard({required this.item, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final proxyState = ref.watch(doubanImageProxyProvider);
    ref.read(doubanImageProxyProvider.notifier).checkAndRefresh();
    final baseUrl = ref.read(apiClientProvider).baseUrl;
    final imageUrl = proxyState.buildImageUrl(item.vodPic, baseUrl);
    final headers = proxyState.httpHeadersForUrl(item.vodPic);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.sm),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                httpHeaders: headers,
                width: 60,
                height: 80,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: colors.elevated),
                errorWidget: (_, _, _) => Container(color: colors.elevated, child: Icon(Icons.movie, color: colors.textMuted)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.vodName, style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(item.resourceName, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            IconButton(icon: Icon(Icons.delete_outline, color: colors.textMuted, size: 20), onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}
