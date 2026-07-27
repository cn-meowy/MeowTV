import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/search_result.dart';
import '../../shared/widgets/search_history_chips.dart';
import '../../shared/widgets/video_card.dart';
import '../settings/douban_image_proxy_provider.dart';
import 'resource_provider.dart';

class ResourceScreen extends ConsumerStatefulWidget {
  const ResourceScreen({super.key});

  @override
  ConsumerState<ResourceScreen> createState() => _ResourceScreenState();
}

class _ResourceScreenState extends ConsumerState<ResourceScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isFocused = false;
  bool _sitesExpanded = false;

  @override
  void initState() {
    super.initState();
    // Track focus loss to hide search history.
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isFocused) {
        setState(() => _isFocused = false);
      }
    });
    Future.microtask(() {
      ref.read(doubanImageProxyProvider.notifier).init();
      ref.read(resourceProvider.notifier).loadSites();
      ref.read(resourceProvider.notifier).loadSearchHistory();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 屏幕尺寸变化（旋转/窗口缩放）时重算网格列数。
  /// 列数变化会联动更新 pageSize 并重新拉取数据，
  /// 保证每页数据填满完整行，避免最后一行不满。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.of(context).size.width;
    final count = width > 600 ? 4 : 3;
    // 延迟到下一帧执行，避免在 build 阶段同步触发网络请求
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(resourceProvider.notifier).setCrossAxisCount(count);
    });
  }

  /// Build the proxy image URL for resource covers using unified proxy logic.
  String _buildProxyUrl(String? cover) {
    if (cover == null || cover.isEmpty) return '';
    final proxyState = ref.read(doubanImageProxyProvider);
    final baseUrl = ref.read(apiClientProvider).baseUrl;
    return proxyState.buildImageUrl(cover, baseUrl);
  }

  /// Build HTTP headers for resource cover images.
  Map<String, String>? _buildProxyHeaders(String? cover) {
    if (cover == null || cover.isEmpty) return null;
    final proxyState = ref.read(doubanImageProxyProvider);
    return proxyState.httpHeadersForUrl(cover);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(resourceProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ─── Search Bar ─────────────────────────────────────────────
            _buildSearchBar(state),

            // ─── Search History Chips ────────────────────────────────────
            if (state.searchHistory.isNotEmpty && _isFocused)
              SearchHistoryChips(
                history: state.searchHistory,
                onTap: (t) {
                  _searchController.text = t;
                  ref.read(resourceProvider.notifier).handleKeywordChange(t);
                  ref.read(resourceProvider.notifier).handleSearch();
                },
                onClear: () => ref.read(resourceProvider.notifier).clearSearchHistory(),
              ),

            // ─── Resource Site Tags ──────────────────────────────────────
            if (state.sites.isNotEmpty) _buildSiteTags(state),

            // ─── Content Area ───────────────────────────────────────────
            Expanded(child: _buildContent(state)),
          ],
        ),
      ),
    );
  }

  // ─── Search Bar ────────────────────────────────────────────────────────────

  Widget _buildSearchBar(ResourceState state) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppTheme.md, AppTheme.md, AppTheme.md, AppTheme.sm),
      child: Container(
        height: AppTheme.inputHeight,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusSearch),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(Icons.search, color: colors.textMuted, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                onTap: () {
                  if (!_isFocused) setState(() => _isFocused = true);
                },
                style: TextStyle(color: colors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: '搜索资源...',
                  hintStyle: TextStyle(color: colors.textMuted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onChanged: (v) => ref.read(resourceProvider.notifier).handleKeywordChange(v),
                onSubmitted: (_) => ref.read(resourceProvider.notifier).handleSearch(),
                textInputAction: TextInputAction.search,
              ),
            ),
            if (state.keyword.isNotEmpty)
              IconButton(
                icon: Icon(Icons.close, color: colors.textMuted, size: 18),
                onPressed: () {
                  _searchController.clear();
                  ref.read(resourceProvider.notifier).handleClearKeyword();
                },
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  // ─── Resource Site Tags (Wrap layout with expand/collapse) ────────────────

  /// Height of a single row of site tags (used for clipping when collapsed).
  static const double _tagRowHeight = 40.0;

  /// Max height for expanded tags area (scrollable when exceeded).
  static const double _tagExpandedMaxHeight = 160.0;

  /// Whether there are enough tags to warrant an expand/collapse toggle.
  /// We assume ~4 tags fit in one row on a typical mobile screen.
  static const int _tagsPerRow = 4;

  Widget _buildSiteTags(ResourceState state) {
    final colors = context.colors;
    final tags = state.sites.map((site) {
      final isActive = site.domain == state.selectedResource;
      return GestureDetector(
        onTap: () => ref.read(resourceProvider.notifier).handleResourceChange(site.domain),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.md, vertical: AppTheme.sm),
          decoration: BoxDecoration(
            color: isActive ? colors.primary : colors.card,
            borderRadius: BorderRadius.circular(AppTheme.radiusTag),
            border: Border.all(
              color: isActive ? colors.primary : colors.border,
            ),
            boxShadow: isActive
                ? [BoxShadow(color: colors.primaryGlow, blurRadius: 12)]
                : null,
          ),
          child: Text(
            site.name,
            style: TextStyle(
              color: isActive ? colors.textInverse : colors.textSecondary,
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
    }).toList();

    final needsExpand = tags.length > _tagsPerRow;

    // Expand/collapse toggle — placed below the tag Wrap, not inside it
    final toggleRow = GestureDetector(
      onTap: () => setState(() => _sitesExpanded = !_sitesExpanded),
      child: Padding(
        padding: const EdgeInsets.only(top: AppTheme.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _sitesExpanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: colors.primary,
            ),
            const SizedBox(width: 4),
            Text(
              _sitesExpanded ? '收起' : '展开全部 ${tags.length} 个站点',
              style: TextStyle(color: colors.primary, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );

    // Build the tag Wrap widget (shared between collapsed & expanded)
    final tagWrap = Wrap(
      spacing: AppTheme.sm,
      runSpacing: AppTheme.sm,
      children: tags,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Use AnimatedSize for smooth height transition instead of AnimatedCrossFade
          // which causes overflow when secondChild (expanded Wrap) is taller than available space
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _sitesExpanded
                ? // Expanded: constrained max height with internal scrolling
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: _tagExpandedMaxHeight),
                    child: SingleChildScrollView(
                      child: tagWrap,
                    ),
                  )
                : // Collapsed: show only one row with clip + "+N" hint
                  Stack(
                    children: [
                      ClipRect(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: _tagRowHeight),
                          child: tagWrap,
                        ),
                      ),
                      // Fade-out hint on the right edge when collapsed
                      if (needsExpand)
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 60,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  colors.background.withValues(alpha: 0),
                                  colors.background,
                                ],
                              ),
                            ),
                            alignment: Alignment.centerRight,
                            child: Text(
                              '+${tags.length - _tagsPerRow}',
                              style: TextStyle(
                                color: colors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          // Toggle button below the tags
          if (needsExpand) toggleRow,
        ],
      ),
    );
  }

  // ─── Content Area ──────────────────────────────────────────────────────────

  Widget _buildContent(ResourceState state) {
    if (state.loading) return _buildLoadingShimmer();

    if (state.error != null) return _buildError(state);

    if (state.results.isEmpty && state.selectedResource.isNotEmpty) return _buildEmpty();

    if (state.results.isEmpty) return _buildEmpty();

    return _buildResults(state);
  }

  // ─── Results Grid + Pagination ─────────────────────────────────────────────

  Widget _buildResults(ResourceState state) {
    final colors = context.colors;
    return Column(
      children: [
        // Result count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.md, vertical: AppTheme.sm),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '共 ${state.total} 条结果',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ),
        ),

        // Grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: state.crossAxisCount,
              childAspectRatio: 0.58,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: state.results.length,
            itemBuilder: (context, i) => _buildCard(state.results[i]),
          ),
        ),

        // Pagination
        if (state.totalPages > 1) _buildPagination(state),
      ],
    );
  }

  Widget _buildCard(SearchResultItem item) {
    final coverUrl = _buildProxyUrl(item.cover);
    final coverHeaders = _buildProxyHeaders(item.cover);

    return VideoCard(
      title: item.title,
      subtitle: item.remarks ?? item.year ?? item.resourceName,
      imageUrl: coverUrl,
      httpHeaders: coverHeaders,
      badge: item.remarks,
      vodId: item.vodId,
      vodName: item.title,
      vodPic: item.cover,
      doubanId: item.doubanId,
      resourceDomain: item.resourceDomain,
      resourceName: item.resourceName,
      onTap: () {
        // Navigate directly to play page
        context.push('/play', extra: {
          'resource_domain': item.resourceDomain,
          'vod_id': item.vodId ?? 0,
        });
      },
    );
  }

  // ─── Pagination Controls ───────────────────────────────────────────────────

  Widget _buildPagination(ResourceState state) {
    final colors = context.colors;
    final buttons = _getPageButtons(state.page, state.totalPages);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.sm, horizontal: AppTheme.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Previous
          _PageButton(
            label: '上一页',
            icon: Icons.chevron_left,
            enabled: state.page > 1,
            onTap: () => ref.read(resourceProvider.notifier).handlePageChange(state.page - 1),
          ),
          const SizedBox(width: 4),

          // Page number buttons
          ...buttons.map((btn) {
            if (btn == '...') {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('...', style: TextStyle(color: colors.textMuted, fontSize: 14)),
              );
            }
            final pageNum = int.parse(btn);
            final isCurrent = pageNum == state.page;
            return GestureDetector(
              onTap: () => ref.read(resourceProvider.notifier).handlePageChange(pageNum),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isCurrent ? colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.radiusTag),
                  border: Border.all(
                    color: isCurrent ? colors.primary : colors.border,
                  ),
                  boxShadow: isCurrent
                      ? [BoxShadow(color: colors.primaryGlow, blurRadius: 8)]
                      : null,
                ),
                child: Text(
                  btn,
                  style: TextStyle(
                    color: isCurrent ? colors.textInverse : colors.textSecondary,
                    fontSize: 14,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }),

          const SizedBox(width: 4),
          // Next
          _PageButton(
            label: '下一页',
            icon: Icons.chevron_right,
            iconTrailing: true,
            enabled: state.page < state.totalPages,
            onTap: () => ref.read(resourceProvider.notifier).handlePageChange(state.page + 1),
          ),
        ],
      ),
    );
  }

  /// Generate page button labels — mirrors Web getPageButtons().
  List<String> _getPageButtons(int current, int total) {
    final buttons = <String>[];
    if (total <= 7) {
      for (var i = 1; i <= total; i++) {
        buttons.add('$i');
      }
    } else {
      buttons.add('1');
      if (current > 3) {
        buttons.add('...');
      }
      final start = current <= 3 ? 2 : current - 1;
      final end = current >= total - 2 ? total - 1 : current + 1;
      for (var i = start; i <= end; i++) {
        buttons.add('$i');
      }
      if (current < total - 2) {
        buttons.add('...');
      }
      buttons.add('$total');
    }
    return buttons;
  }

  // ─── Loading Shimmer ───────────────────────────────────────────────────────

  Widget _buildLoadingShimmer() {
    final colors = context.colors;
    // 与结果网格保持相同的响应式列数，骨架屏行数固定为 3 行
    final crossAxisCount = ref.read(resourceProvider).crossAxisCount;
    return Shimmer.fromColors(
      baseColor: colors.card,
      highlightColor: colors.elevated,
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.58,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: crossAxisCount * 3,
        itemBuilder: (_, _) => Container(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
        ),
      ),
    );
  }

  // ─── Error State ───────────────────────────────────────────────────────────

  Widget _buildError(ResourceState state) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: colors.error.withValues(alpha: 0.7)),
          const SizedBox(height: 16),
          Text(
            state.error ?? '请求资源站失败',
            style: TextStyle(color: colors.error, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => ref.read(resourceProvider.notifier).retry(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTheme.radiusTag),
                border: Border.all(color: colors.error.withValues(alpha: 0.3)),
              ),
              child: Text('重试', style: TextStyle(color: colors.error, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Empty State ───────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 48, color: colors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('暂无数据', style: TextStyle(color: colors.textMuted, fontSize: 14)),
        ],
      ),
    );
  }
}

// ─── Page Navigation Button ──────────────────────────────────────────────────

class _PageButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool iconTrailing;
  final bool enabled;
  final VoidCallback onTap;

  const _PageButton({
    required this.label,
    required this.icon,
    this.iconTrailing = false,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: enabled ? colors.primary : colors.elevated,
          borderRadius: BorderRadius.circular(AppTheme.radiusTag),
          border: Border.all(
            color: enabled ? colors.primary : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: iconTrailing
              ? [
                  Text(label, style: TextStyle(
                    color: enabled ? colors.textInverse : colors.textMuted,
                    fontSize: 13,
                  )),
                  Icon(icon, size: 14, color: enabled ? colors.textInverse : colors.textMuted),
                ]
              : [
                  Icon(icon, size: 14, color: enabled ? colors.textInverse : colors.textMuted),
                  Text(label, style: TextStyle(
                    color: enabled ? colors.textInverse : colors.textMuted,
                    fontSize: 13,
                  )),
                ],
        ),
      ),
    );
  }
}
