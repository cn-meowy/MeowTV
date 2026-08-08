import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/user_data.dart';
import '../history/history_provider.dart';
import '../settings/douban_image_proxy_provider.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(doubanImageProxyProvider.notifier).init();
      ref.read(historyProvider.notifier).loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(historyProvider);
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('播放历史'),
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
          : state.error != null && state.items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: colors.error),
                        const SizedBox(height: 16),
                        Text('加载失败', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(state.error!, style: TextStyle(color: colors.textMuted, fontSize: 13), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => ref.read(historyProvider.notifier).loadHistory(),
                          child: Text('重试', style: TextStyle(color: colors.primary)),
                        ),
                      ],
                    ),
                  ),
                )
              : state.items.isEmpty
                  ? Center(child: Text('暂无播放记录', style: TextStyle(color: colors.textMuted)))
                  : ListView.builder(
                  padding: const EdgeInsets.all(AppTheme.md),
                  itemCount: state.items.length,
                  itemBuilder: (context, i) => _HistoryItemCard(
                    item: state.items[i],
                    onTap: () {
                      context.push('/play', extra: {
                        'resource_domain': state.items[i].resourceDomain,
                        'vod_id': state.items[i].vodId,
                        'source_index': state.items[i].sourceIndex,
                        'ep_index': state.items[i].epIndex,
                      });
                    },
                    onDelete: () => ref.read(historyProvider.notifier).deleteItem(state.items[i].id),
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
        title: Text('清空历史', style: TextStyle(color: colors.textPrimary)),
        content: Text('确定清空所有播放历史？', style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              ref.read(historyProvider.notifier).clearHistory();
              Navigator.pop(context);
            },
            child: Text('清空', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
  }
}

class _HistoryItemCard extends ConsumerWidget {
  final PlayHistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _HistoryItemCard({required this.item, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final proxyState = ref.watch(doubanImageProxyProvider);
    ref.read(doubanImageProxyProvider.notifier).checkAndRefresh();
    final baseUrl = ref.read(apiClientProvider).baseUrl;
    final imageUrl = proxyState.resolveImageUrl(item.vodPic, baseUrl) ?? '';
    final headers = proxyState.httpHeadersForUrl(item.vodPic);
    final progressPercent = item.progress.round().clamp(0, 100);
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
                  Text('${item.epName} - ${item.resourceName}', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 6),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (item.progress / 100).clamp(0.0, 1.0),
                      backgroundColor: colors.elevated,
                      valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('$progressPercent%', style: TextStyle(color: colors.textMuted, fontSize: 11)),
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
