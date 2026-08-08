import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/logger/app_logger.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/search_result.dart';
import '../../shared/widgets/download_episode_dialog.dart';
import '../../shared/widgets/cache_episode_dialog.dart';
import '../../shared/widgets/cache_icons.dart';
import '../../shared/widgets/m3u8_status_indicator.dart';
import '../search/search_provider.dart';
import '../settings/douban_image_proxy_provider.dart';
import '../detail/detail_provider.dart';
import '../detail/m3u8_check_provider.dart';
import '../../shared/models/resource_detail.dart';

class DetailScreen extends ConsumerStatefulWidget {
  final String resourceDomain;
  final int vodId;
  final String? groupKey;
  final String? groupName;

  const DetailScreen({
    super.key,
    required this.resourceDomain,
    required this.vodId,
    this.groupKey,
    this.groupName,
  });

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  late String _activeDomain;
  int? _selectedResourceIndex;

  /// 记录已触发 m3u8 检测的 URL 集合，避免 build 重复触发。
  Set<String> _checkedUrls = {};

  @override
  void initState() {
    super.initState();
    _activeDomain = widget.resourceDomain;
    Future.microtask(() {
      // 确保图片代理就绪（loadMode + token），避免 buildImageUrl 因 token 为空回退到原始 URL
      ref.read(doubanImageProxyProvider.notifier).init();
      ref.read(detailProvider.notifier).fetchDetail(widget.resourceDomain, widget.vodId);
    });
  }

  @override
  void didUpdateWidget(covariant DetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 resourceDomain 或 vodId 变化时，重置检测缓存
    if (oldWidget.resourceDomain != widget.resourceDomain ||
        oldWidget.vodId != widget.vodId) {
      _checkedUrls = {};
    }
  }

  /// Handle resource switch — load detail for the new resource.
  void _handleResourceChange(SearchResultItem item, {int? expandIndex}) {
    if (item.resourceDomain == _activeDomain) return;
    setState(() {
      _activeDomain = item.resourceDomain;
      _selectedResourceIndex = expandIndex;
    });
    if (item.vodId != null) {
      ref.read(detailProvider.notifier).fetchDetail(item.resourceDomain, item.vodId!);
    }
  }

  /// Toggle resource selection for episode display.
  void _toggleResourceExpand(int index, List<SearchResultItem> items) {
    final item = items[index];
    final isTogglingOff = _selectedResourceIndex == index;

    if (isTogglingOff) {
      // Collapse: hide episodes
      setState(() => _selectedResourceIndex = null);
    } else {
      // Expand: show episodes for this resource
      if (item.resourceDomain != _activeDomain) {
        // Switch to new resource and expand
        _handleResourceChange(item, expandIndex: index);
      } else {
        // Same resource, just expand
        setState(() => _selectedResourceIndex = index);
      }
    }
  }

  /// 触发 m3u8 链接可用性检测（仅检测新增 URL，避免 build 重复触发）。
  void _triggerM3u8CheckOnce(List<PlaySource> sources) {
    if (sources.isEmpty) return;
    final allUrls = <String>[];
    for (final source in sources) {
      for (final ep in source.episodes) {
        if (ep.url.isNotEmpty) allUrls.add(ep.url);
      }
    }
    // 过滤出尚未检测过的 URL
    final newUrls = allUrls.where((url) => !_checkedUrls.contains(url)).toList();
    if (newUrls.isEmpty) return;
    _checkedUrls = {..._checkedUrls, ...newUrls};
    Future.microtask(() {
      appLogger.i('[DetailScreen] triggering m3u8 check: ${newUrls.length} new URLs (total checked: ${_checkedUrls.length})');
      ref.read(m3u8CheckProvider.notifier).checkUrls(newUrls);
    });
  }

  /// Deduplicate group items by resourceDomain, keeping the first occurrence.
  List<SearchResultItem> _deduplicateByDomain(List<SearchResultItem> items) {
    final seen = <String>{};
    return items.where((item) {
      if (seen.contains(item.resourceDomain)) return false;
      seen.add(item.resourceDomain);
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(detailProvider);
    final detail = state.detail;
    final colors = context.colors;

    // Get same-group items from search provider, deduplicate by resourceDomain
    final rawGroupItems = widget.groupKey != null
        ? ref.read(searchProvider).groupedResults[widget.groupKey] ?? <SearchResultItem>[]
        : <SearchResultItem>[];
    final groupItems = _deduplicateByDomain(rawGroupItems);

    // Initial loading: show full-screen indicator only when there's no detail yet
    if (state.isLoading && detail == null) {
      return Scaffold(
        backgroundColor: colors.background,
        body: Center(child: CircularProgressIndicator(color: colors.primary)),
      );
    }

    if (detail == null) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
        body: Center(child: Text(state.error ?? '加载失败', style: TextStyle(color: colors.textSecondary))),
      );
    }

    final sources = detail.parsedSources;
    // Auto-select the active resource index on first build
    final effectiveSelectedIndex = _selectedResourceIndex ??
        groupItems.indexWhere((item) => item.resourceDomain == _activeDomain);
    // Show episodes when a resource is selected, or when there's only one resource (auto-expand)
    final showEpisodes = effectiveSelectedIndex >= 0 || groupItems.length <= 1;

    // 批量检测所有播放源的 m3u8 链接可用性（仅检测新增 URL，避免 build 重复触发）
    _triggerM3u8CheckOnce(sources);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with backdrop
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: colors.background,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.arrow_back, size: 20),
              ),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: Icon(state.isFavorite ? Icons.star : Icons.star_outline, color: state.isFavorite ? colors.primary : colors.textSecondary),
                onPressed: () => ref.read(detailProvider.notifier).toggleFavorite(),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (detail.vodPic != null)
                    Builder(builder: (context) {
                      final proxyState = ref.watch(doubanImageProxyProvider);
                      ref.read(doubanImageProxyProvider.notifier).checkAndRefresh();
                      final baseUrl = ref.read(apiClientProvider).baseUrl;
                      final imgProxyUrl = proxyState.resolveImageUrl(detail.vodPic!, baseUrl) ?? '';
                      final imgHeaders = proxyState.httpHeadersForUrl(detail.vodPic!);
                      return CachedNetworkImage(
                        imageUrl: imgProxyUrl,
                        httpHeaders: imgHeaders,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: colors.card),
                        errorWidget: (_, _, _) => Container(color: colors.card),
                      );
                    }),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [colors.background.withValues(alpha: 0.3), colors.background],
                        stops: const [0.0, 0.85],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Movie info
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.md, 0, AppTheme.md, AppTheme.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + meta
                  Text(detail.vodName, style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  if (detail.vodSub != null)
                    Text(detail.vodSub!, style: TextStyle(color: colors.primary, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (detail.vodYear != null) _MetaChip(detail.vodYear!),
                      if (detail.vodArea != null) _MetaChip(detail.vodArea!),
                      if (detail.typeName != null) _MetaChip(detail.typeName!),
                      if (detail.vodScore != null) _MetaChip(detail.vodScore!, highlight: true),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.play_arrow,
                          label: '播放',
                          filled: true,
                          onTap: () {
                            if (sources.isNotEmpty && sources[0].episodes.isNotEmpty) {
                              context.push('/play', extra: {
                                'resource_domain': detail.resourceDomain,
                                'vod_id': detail.vodId,
                                'source_index': 0,
                                'ep_index': 0,
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        icon: state.isFavorite ? Icons.star : Icons.star_outline,
                        label: '',
                        onTap: () => ref.read(detailProvider.notifier).toggleFavorite(),
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        icon: Icons.download_outlined,
                        label: '',
                        onTap: () {
                          DownloadEpisodeDialog.show(
                            context,
                            sources: sources,
                            defaultSourceIndex: effectiveSelectedIndex >= 0 ? effectiveSelectedIndex : 0,
                            vodId: detail.vodId,
                            vodName: detail.vodName,
                            vodPic: detail.vodPic,
                            resourceDomain: detail.resourceDomain,
                            resourceName: detail.resourceName,
                            groupKey: widget.groupKey ?? '',
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        iconWidget: CacheIcons.cache(size: 18, color: colors.textSecondary),
                        label: '',
                        onTap: () {
                          CacheEpisodeDialog.show(
                            context,
                            sources: sources,
                            defaultSourceIndex: effectiveSelectedIndex >= 0 ? effectiveSelectedIndex : 0,
                            resourceDomain: detail.resourceDomain,
                            vodId: detail.vodId,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Description
                  if (detail.vodBlurb != null) ...[
                    Text('简介', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(detail.vodBlurb!, style: TextStyle(color: colors.textSecondary, fontSize: 14, height: 1.6), maxLines: 4, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
          ),

          // Resource list (same-group resources) — clickable to expand episodes
          if (groupItems.length > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppTheme.md, 0, AppTheme.md, AppTheme.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('资源列表', style: TextStyle(color: colors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppTheme.sm),
                    Wrap(
                      spacing: AppTheme.sm,
                      runSpacing: AppTheme.sm,
                      children: [
                        for (var i = 0; i < groupItems.length; i++)
                          _ResourceChip(
                            item: groupItems[i],
                            isActive: groupItems[i].resourceDomain == _activeDomain,
                            isExpanded: effectiveSelectedIndex == i,
                            onTap: () => _toggleResourceExpand(i, groupItems),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Switching indicator
          if (state.isLoading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.md),
                child: Row(
                  children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary)),
                    const SizedBox(width: 8),
                    Text('切换资源中...', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ),

          // Play sources + episodes (show when a resource is selected or only one resource)
          if (showEpisodes) ...[
            for (var si = 0; si < sources.length; si++) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppTheme.md, 8, AppTheme.md, 8),
                  child: Text(sources[si].name, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: MediaQuery.of(context).size.width > 600 ? 6 : 4,
                    childAspectRatio: 2.5,
                    crossAxisSpacing: AppTheme.sm,
                    mainAxisSpacing: AppTheme.sm,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, ei) {
                      final ep = sources[si].episodes[ei];
                      return GestureDetector(
                        onTap: () {
                          context.push('/play', extra: {
                            'resource_domain': detail.resourceDomain,
                            'vod_id': detail.vodId,
                            'source_index': si,
                            'ep_index': ei,
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: colors.card,
                            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                            border: Border.all(color: colors.border),
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Center(
                                child: Text(ep.name, style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                              ),
                              // M3u8 检测状态指示器（左下角）
                              Positioned(
                                left: 2,
                                bottom: 2,
                                child: M3u8StatusIndicator(url: ep.url, size: 10),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: sources[si].episodes.length,
                  ),
                ),
              ),
            ],
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final bool highlight;
  const _MetaChip(this.label, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight ? colors.primary.withValues(alpha: 0.15) : colors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: highlight ? colors.primary.withValues(alpha: 0.3) : colors.border),
      ),
      child: Text(label, style: TextStyle(color: highlight ? colors.primary : colors.textSecondary, fontSize: 12)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData? icon;
  /// 自定义图标 Widget（SVG 等）。优先于 [icon] 使用。
  final Widget? iconWidget;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _ActionButton({this.icon, this.iconWidget, required this.label, this.filled = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isIconOnly = label.isEmpty;
    // 构建图标：优先 iconWidget，否则回退到 IconData
    Widget buildIcon(double size) {
      if (iconWidget != null) {
        return SizedBox(width: size, height: size, child: Center(child: iconWidget!));
      }
      return Icon(icon, size: size, color: filled ? colors.textInverse : colors.textSecondary);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: isIconOnly ? 0 : 12),
        constraints: isIconOnly ? const BoxConstraints(minWidth: 36) : null,
        decoration: BoxDecoration(
          color: filled ? colors.primary : colors.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: filled ? null : Border.all(color: colors.border),
        ),
        child: isIconOnly
            ? Center(child: buildIcon(18))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildIcon(16),
                  const SizedBox(width: 4),
                  Text(label, style: TextStyle(color: filled ? colors.textInverse : colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }
}

/// Resource chip widget for the resource list in detail page.
class _ResourceChip extends StatelessWidget {
  final SearchResultItem item;
  final bool isActive;
  final bool isExpanded;
  final VoidCallback onTap;

  const _ResourceChip({
    required this.item,
    required this.isActive,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? colors.primary.withValues(alpha: 0.15) : colors.elevated,
          borderRadius: BorderRadius.circular(AppTheme.radiusTag),
          border: Border.all(
            color: isActive
                ? colors.primary.withValues(alpha: 0.4)
                : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.public,
              size: 12,
              color: isActive ? colors.primary : colors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              item.resourceName,
              style: TextStyle(
                color: isActive ? colors.primary : colors.textSecondary,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 4),
              Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                size: 14,
                color: colors.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
