import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/search_result.dart';
import '../../shared/widgets/equal_width_site_wrap.dart';
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
  final _pageInputController = TextEditingController();
  final _pageInputFocusNode = FocusNode();
  bool _isFocused = false;
  bool _sitesExpanded = false;

  /// 底部安全间距 = 导航栏高度（56）。
  /// 配合 [MediaQuery.padding.bottom] 使用，保证滚动内容既不被
  /// `extendBody: true` 的 TabBar 遮挡，又无多余空隙。
  /// 与 favorites/search 一致；分页组件内部 `Padding(vertical: sm)`
  /// 提供上下 8px 视觉呼吸，此处不再叠加。
  static const double _bottomSafeGap = AppTheme.tabBarHeight;

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
    _pageInputController.dispose();
    _pageInputFocusNode.dispose();
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
    return proxyState.resolveImageUrl(cover, baseUrl) ?? '';
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
            // 仅当存在多个资源站点时才显示站点标签栏，
            // 单一站点时无需切换，直接隐藏整块 UI。
            if (state.sites.length > 1) _buildSiteTags(state),

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

  Widget _buildSiteTags(ResourceState state) {
    final colors = context.colors;
    final tags = state.sites.map((site) {
      final isActive = site.domain == state.selectedResource;
      return GestureDetector(
        onTap: () => ref.read(resourceProvider.notifier).handleResourceChange(site.domain),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: AppTheme.sm),
          alignment: Alignment.center,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? colors.textInverse : colors.textSecondary,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
    }).toList();

    // Expand/collapse toggle — placed below the tag Wrap, not inside it.
    // Always shown: with equal-width chips many sites still overflow one row,
    // so the toggle remains useful for scrolling the expanded area.
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

    // Equal-width chips shared between collapsed & expanded states.
    final tagWrap = EqualWidthSiteWrap(
      itemCount: tags.length,
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
                : // Collapsed: show only one row (clip the rest)
                  ClipRect(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: _tagRowHeight),
                      child: tagWrap,
                    ),
                  ),
          ),
          // Toggle button below the tags
          toggleRow,
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
    final bottomInset = _bottomSafeGap + MediaQuery.of(context).padding.bottom;

    return CustomScrollView(
      slivers: [
        // Result count
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '共 ${state.total} 条结果',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ),
            ),
          ),
        ),

        // Grid
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: state.crossAxisCount,
              childAspectRatio: 0.58,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _buildCard(state.results[i]),
              childCount: state.results.length,
            ),
          ),
        ),

        // Pagination — 跟随卡片滚动，仅多页时出现；
        // 底部安全间距（导航栏 + 系统安全区）集中在此 sliver 的 bottom padding
        if (state.totalPages > 1)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(AppTheme.md, 0, AppTheme.md, bottomInset),
            sliver: SliverToBoxAdapter(child: _buildPagination(state)),
          )
        else
          // 单页时无分页条，底部留白由占位 sliver 补齐，保持与加载态一致
          SliverPadding(
            padding: EdgeInsets.only(bottom: bottomInset),
            sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
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
    final items = _buildCompactPageButtons(state.page, state.totalPages);

    return Padding(
      // 已位于滚动区内，仅保留上下 sm 间距，不再叠加导航栏底部留白
      padding: const EdgeInsets.symmetric(vertical: AppTheme.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // « first
          _IconPageButton(
            icon: Icons.first_page,
            enabled: state.page > 1,
            onTap: () => ref.read(resourceProvider.notifier).handlePageChange(1),
          ),
          const SizedBox(width: AppTheme.xs),
          // ‹ prev
          _IconPageButton(
            icon: Icons.chevron_left,
            enabled: state.page > 1,
            onTap: () => ref.read(resourceProvider.notifier).handlePageChange(state.page - 1),
          ),
          const SizedBox(width: AppTheme.xs),

          // 页码窗口：Flexible 收缩避免窄屏 Row 溢出，动态 maxWidth + 居中保留宽屏视觉
          Flexible(
            fit: FlexFit.loose,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 内容自然宽度：每项 28(按钮) + 4(单边 padding) = 32
                final contentWidth = items.length * 32.0;
                // 上限：父容器剩余可用宽度（Flexible 已约束为真实剩余空间，
                //   宽屏下 contentWidth 较小自然居中，窄屏下占满避免溢出）
                final maxWidth = contentWidth.clamp(0.0, constraints.maxWidth);
                return ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Center(
                    // SingleChildScrollView 横向滚动兜底，避免极端窄屏 RenderFlex 溢出
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: items.map((item) {
                          if (item is EllipsisItem) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppTheme.xs),
                              child: Text(
                                '…',
                                style: TextStyle(color: colors.textMuted, fontSize: 14),
                              ),
                            );
                          }
                          final pageNum = (item as NumItem).page;
                          final isCurrent = pageNum == state.page;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: isCurrent
                                  ? null
                                  : () => ref.read(resourceProvider.notifier).handlePageChange(pageNum),
                              child: Container(
                                width: 28,
                                height: 28,
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
                                  '$pageNum',
                                  maxLines: 1,
                                  overflow: TextOverflow.visible,
                                  style: TextStyle(
                                    color: isCurrent ? colors.textInverse : colors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(width: AppTheme.xs),
          // › next
          _IconPageButton(
            icon: Icons.chevron_right,
            enabled: state.page < state.totalPages,
            onTap: () => ref.read(resourceProvider.notifier).handlePageChange(state.page + 1),
          ),
          const SizedBox(width: AppTheme.xs),
          // » last
          _IconPageButton(
            icon: Icons.last_page,
            enabled: state.page < state.totalPages,
            onTap: () => ref.read(resourceProvider.notifier).handlePageChange(state.totalPages),
          ),

          const SizedBox(width: AppTheme.sm),
          // 跳转到指定页输入框
          SizedBox(
            width: 64,
            child: TextField(
              controller: _pageInputController,
              focusNode: _pageInputFocusNode,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.go,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                isDense: true,
                hintText: '${state.page}',
                hintStyle: TextStyle(color: colors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusTag),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusTag),
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
              onSubmitted: _jumpToInputPage,
            ),
          ),
          const SizedBox(width: AppTheme.xs),
          Text(
            '/ ${state.totalPages} 页',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// 跳转到输入的页码。非数字/空/越界时清空 + 失焦；
  /// 越界由 [ResourceNotifier.handlePageChange] 兜底返回。
  void _jumpToInputPage(String value) {
    final n = int.tryParse(value.trim());
    if (n == null) {
      _pageInputController.clear();
      _pageInputFocusNode.unfocus();
      return;
    }
    ref.read(resourceProvider.notifier).handlePageChange(n);
    _pageInputController.clear();
    _pageInputFocusNode.unfocus();
  }

  /// 生成结构化页码列表。
  ///
  /// - `total <= 7`：依次输出 `1..total`。
  /// - `total > 7`：固定输出 `1`，按需插入 `…`，输出窗口
  ///   `[current-2, current+2]`（裁剪到 `[2, total-1]`），按需插入 `…`，
  ///   固定输出 `total`。仅当页码与上一个已输出页码不同时才追加，
  ///   防止边缘情况下出现重复的 `1` 或 `N`。
  List<_PageItem> _buildCompactPageButtons(int current, int total) {
    final items = <_PageItem>[];
    int? lastEmitted;

    void emitPage(int p) {
      if (lastEmitted != p) {
        items.add(NumItem(p));
        lastEmitted = p;
      }
    }

    void emitEllipsis() {
      items.add(const EllipsisItem());
    }

    if (total <= 7) {
      for (var i = 1; i <= total; i++) {
        emitPage(i);
      }
      return items;
    }

    // 固定首页
    emitPage(1);
    // 首页与窗口之间是否需要省略号
    final windowStart = (current - 2).clamp(2, total - 1);
    final windowEnd = (current + 2).clamp(2, total - 1);
    if (windowStart > 2) emitEllipsis();
    // 窗口
    for (var i = windowStart; i <= windowEnd; i++) {
      emitPage(i);
    }
    // 窗口与末页之间是否需要省略号
    if (windowEnd < total - 1) emitEllipsis();
    // 固定末页
    emitPage(total);

    return items;
  }

  // ─── Loading Shimmer ───────────────────────────────────────────────────────

  Widget _buildLoadingShimmer() {
    final colors = context.colors;
    // 与结果网格保持相同的响应式列数，骨架屏行数固定为 3 行
    final crossAxisCount = ref.read(resourceProvider).crossAxisCount;
    // 与 _buildResults 共用同一底部安全间距，避免加载/结果态切换时视觉跳动
    final bottomInset = _bottomSafeGap + MediaQuery.of(context).padding.bottom;
    return Shimmer.fromColors(
      baseColor: colors.card,
      highlightColor: colors.elevated,
      child: GridView.builder(
        padding: EdgeInsets.fromLTRB(AppTheme.md, 0, AppTheme.md, bottomInset),
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

// ─── Page Navigation Item (structured) ───────────────────────────────────────

/// 结构化页码项，替代旧的字符串 `'...'` 解析方案。
sealed class _PageItem {
  const _PageItem();
}

/// 具体页码。
class NumItem extends _PageItem {
  final int page;
  const NumItem(this.page);
}

/// 省略号占位。
class EllipsisItem extends _PageItem {
  const EllipsisItem();
}

// ─── Icon Page Button (first/prev/next/last) ─────────────────────────────────

class _IconPageButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _IconPageButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      // 28×28 视觉 + 10 内边距 = 48×48 Material 命中区
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusTag),
            border: Border.all(
              color: enabled ? colors.border : colors.border.withValues(alpha: 0.4),
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? colors.textSecondary : colors.textMuted,
          ),
        ),
      ),
    );
  }
}
