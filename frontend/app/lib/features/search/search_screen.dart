import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/search_result.dart';
import '../../shared/widgets/video_card.dart';
import '../../shared/widgets/name_grouped_card.dart';
import '../../shared/widgets/resource_dropdown.dart';
import '../../shared/widgets/search_history_chips.dart';
import '../settings/douban_image_proxy_provider.dart';
import 'search_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final String? initialDoubanId;
  final String? initialQuery;

  const SearchScreen({
    super.key,
    this.initialDoubanId,
    this.initialQuery,
  });

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isFocused = false;
  String? _activeDoubanId;

  @override
  void initState() {
    super.initState();
    // Rebuild when _controller.text changes so the clear button
    // visibility condition (_controller.text.isNotEmpty) is re-evaluated.
    _controller.addListener(() => setState(() {}));
    // Track focus loss to hide search history.
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isFocused) {
        setState(() => _isFocused = false);
      }
    });
    Future.microtask(() {
      // 确保图片代理就绪（loadMode + token），避免 buildImageUrl 因 token 为空回退到原始 URL
      ref.read(doubanImageProxyProvider.notifier).init();
      ref.read(searchProvider.notifier).loadSites();
      ref.read(searchProvider.notifier).loadSearchHistory();

      // Auto-search if initial params provided
      if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
        _controller.text = widget.initialQuery!;
        _activeDoubanId = widget.initialDoubanId;
        ref.read(searchProvider.notifier).search(
              widget.initialQuery!,
              doubanId: widget.initialDoubanId,
            );
      }
    });
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery ||
        widget.initialDoubanId != oldWidget.initialDoubanId) {
      if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
        _controller.text = widget.initialQuery!;
        _activeDoubanId = widget.initialDoubanId;
        ref.read(searchProvider.notifier).search(
              widget.initialQuery!,
              doubanId: widget.initialDoubanId,
            );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _search(String q) {
    if (q.trim().isEmpty) return;
    ref.read(searchProvider.notifier).collapseExpanded();
    ref.read(searchProvider.notifier).search(q, doubanId: _activeDoubanId);
  }

  void _onSearchTextChanged(String text) {
    if (widget.initialQuery != null && text != widget.initialQuery && _activeDoubanId != null) {
      _activeDoubanId = null;
      ref.read(searchProvider.notifier).clearDoubanId();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);
    final colors = context.colors;
    debugPrint('[SearchScreen] build: _isFocused=$_isFocused, searchHistory.length=${state.searchHistory.length}, controller.text="${_controller.text}"');

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: NestedScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            // Search bar with resource trigger button on the left
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.md),
                child: Container(
                  height: AppTheme.inputHeight,
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSearch),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    children: [
                      // 仅当存在多个资源站点时才显示资源选择器及分隔线，
                      // 单一站点时隐藏，避免无意义的切换 UI。
                      if (state.sites.length > 1) ...[
                        const ResourceDropdownWidget(compact: true),
                        Container(
                          width: 1,
                          height: 20,
                          color: colors.border,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Icon(Icons.search, color: colors.textMuted, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            onTap: () {
                              if (!_isFocused) setState(() => _isFocused = true);
                            },
                            style: TextStyle(color: colors.textPrimary, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: '输入关键词搜索...',
                            hintStyle: TextStyle(color: colors.textMuted),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                          onSubmitted: _search,
                          onChanged: _onSearchTextChanged,
                          textInputAction: TextInputAction.search,
                        ),
                      ),
                      if (_controller.text.isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.close, color: colors.textMuted, size: 18),
                          onPressed: () {
                            _controller.clear();
                            _activeDoubanId = null;
                            ref.read(searchProvider.notifier).cancelSearch();
                            ref.read(searchProvider.notifier).clearDoubanId();
                          },
                        ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),

            // Resource selection panel
            if (state.isExpanded)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: SingleChildScrollView(
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: const ResourceDropdownPanel(),
                      ),
                    ),
                  ),
                ),
              ),

            // Search history chips below search bar
            if (state.searchHistory.isNotEmpty && _isFocused)
              SliverToBoxAdapter(
                child: SearchHistoryChips(
                  history: state.searchHistory,
                  onTap: (t) {
                    _controller.text = t;
                    _activeDoubanId = null;
                    ref.read(searchProvider.notifier).clearDoubanId();
                    _search(t);
                  },
                  onClear: () => ref.read(searchProvider.notifier).clearSearchHistory(),
                ),
              ),
          ],
          body: state.results.isEmpty && !state.isSearching
              ? _buildEmptyHint(state)
              : _buildResults(state),
        ),
      ),
    );
  }


  /// Empty hint when no search results and no search in progress
  Widget _buildEmptyHint(SearchState state) {
    final colors = context.colors;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search, size: 48, color: colors.textMuted),
        const SizedBox(height: AppTheme.sm),
        Text('输入关键词开始搜索', style: TextStyle(color: colors.textSecondary, fontSize: 14)),
      ]),
    );
  }

  Widget _buildResults(SearchState state) {
    final colors = context.colors;
    return Column(
      children: [
        // Search status
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
          child: Row(
            children: [
              Expanded(child: Text(
                state.isSearching ? '搜索中...' : '"${state.query}" ${state.totalResults}条结果',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              )),
              // Group mode toggle
              Row(
                children: [
                  GestureDetector(
                    onTap: () => ref.read(searchProvider.notifier).setGroupMode(SearchGroupMode.bySite),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: state.groupMode == SearchGroupMode.bySite ? colors.primary : colors.card,
                        borderRadius: BorderRadius.circular(AppTheme.radiusTag),
                      ),
                      child: Text('按资源', style: TextStyle(color: state.groupMode == SearchGroupMode.bySite ? colors.textInverse : colors.textSecondary, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => ref.read(searchProvider.notifier).setGroupMode(SearchGroupMode.byName),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: state.groupMode == SearchGroupMode.byName ? colors.primary : colors.card,
                        borderRadius: BorderRadius.circular(AppTheme.radiusTag),
                      ),
                      child: Text('按名称', style: TextStyle(color: state.groupMode == SearchGroupMode.byName ? colors.textInverse : colors.textSecondary, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (state.error != null && state.error!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.md,
              vertical: 4,
            ),
            child: Text(
              state.error!,
              style: TextStyle(color: colors.error, fontSize: 13),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(child: _buildGroupedResults(state)),
      ],
    );
  }

  Widget _buildGroupedResults(SearchState state) {
    final colors = context.colors;
    if (state.groupMode == SearchGroupMode.bySite) {
      // Group by resource domain, display resourceName as group title
      final groups = <String, List<SearchResultItem>>{};
      for (final item in state.results) {
        groups.putIfAbsent(item.resourceDomain, () => []).add(item);
      }
      return ListView(
        // body 在 SafeArea(bottom:true) 内，padding.bottom 已被消耗为 0，
        // 此处只需补足导航栏高度
        padding: EdgeInsets.fromLTRB(AppTheme.md, 0, AppTheme.md, AppTheme.tabBarHeight + MediaQuery.of(context).padding.bottom),
        children: groups.entries.map((e) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(e.value.first.resourceName, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(width: 8),
                  Text('${e.value.length}条', style: TextStyle(color: colors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: e.value.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final item = e.value[i];
                  final proxyState = ref.watch(doubanImageProxyProvider);
                  ref.read(doubanImageProxyProvider.notifier).checkAndRefresh();
                  final baseUrl = ref.read(apiClientProvider).baseUrl;
                  final imgProxyUrl = proxyState.resolveImageUrl(item.cover ?? '', baseUrl) ?? '';
                  final imgHeaders = proxyState.httpHeadersForUrl(item.cover ?? '');
                  return VideoCard(
                    title: item.title,
                    subtitle: item.year ?? item.resourceName,
                    imageUrl: imgProxyUrl,
                    httpHeaders: imgHeaders,
                    vodId: item.vodId,
                    vodName: item.title,
                    vodPic: item.cover,
                    doubanId: item.doubanId,
                    resourceDomain: item.resourceDomain,
                    resourceName: item.resourceName,
                    onTap: () {
                      context.push('/detail', extra: {
                        'resource_domain': item.resourceDomain,
                        'vod_id': item.vodId ?? 0,
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        )).toList(),
      );
    } else {
      // Group by name (douban_id or title) — single card per group.
      // Use groupedResults directly; it's already merged by mergeNameGroups
      // so that items without doubanId are consolidated into matching
      // doubanId-based groups, preventing duplicate cards for the same movie.
      final groupEntries = state.groupedResults.entries.toList();

      return GridView.builder(
        padding: EdgeInsets.fromLTRB(AppTheme.md, 0, AppTheme.md, AppTheme.tabBarHeight + MediaQuery.of(context).padding.bottom),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 3,
          childAspectRatio: AppTheme.cardWidth / 210,
          crossAxisSpacing: AppTheme.sm,
          mainAxisSpacing: AppTheme.md,
        ),
        itemCount: groupEntries.length,
        itemBuilder: (context, index) {
          final entry = groupEntries[index];
          final items = entry.value;
          final first = items.first;
          final proxyState = ref.watch(doubanImageProxyProvider);
          ref.read(doubanImageProxyProvider.notifier).checkAndRefresh();
          final baseUrl = ref.read(apiClientProvider).baseUrl;
          final cover = items.firstWhere(
            (i) => i.cover != null && i.cover!.isNotEmpty,
            orElse: () => first,
          ).cover ?? '';
          final imgProxyUrl = proxyState.resolveImageUrl(cover, baseUrl) ?? '';
          final imgHeaders = proxyState.httpHeadersForUrl(cover);

          return NameGroupedCard(
            items: items,
            groupKey: entry.key,
            imageUrl: imgProxyUrl,
            httpHeaders: imgHeaders,
            onTap: () {
              context.push('/detail', extra: {
                'resource_domain': first.resourceDomain,
                'vod_id': first.vodId ?? 0,
                'group_key': entry.key,
                'name': first.title,
              });
            },
          );
        },
      );
    }
  }
}
