import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../core/theme/app_theme.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/douban.dart';
import 'home_provider.dart';
import 'douban_provider.dart';
import '../settings/douban_image_proxy_provider.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/video_card.dart';
import '../../shared/widgets/proxy_image_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // ignore: unused_field
  int _bannerIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // Load data on init — but only if not already loaded.
    // GoRouter's refreshListenable may cause this widget to be
    // dispose + recreate; without this guard, loadData() fires
    // again on every rebuild, causing an infinite request loop.
    Future.microtask(() {
      final homeState = ref.read(homeProvider);
      if (homeState.hotMovies.isEmpty && !homeState.isLoading) {
        // loadData() 内部已调用 init()（loadMode + ensureTokenLoaded），
        // 确保 token 在 subjects 数据渲染前就绪，无需再单独调用 ensureTokenLoaded。
        ref.read(homeProvider.notifier).loadData();
      } else {
        // 数据已加载但仍需确保代理就绪（如从其他页面返回时）
        ref.read(doubanImageProxyProvider.notifier).init();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    // loadData() already fetches subjects + tags; no need for a separate loadTags().
    await ref.read(homeProvider.notifier).loadData();
  }

  @override
  Widget build(BuildContext context) {
    final homeState = ref.watch(homeProvider);
    final doubanState = ref.watch(doubanProvider);
    final proxyState = ref.watch(doubanImageProxyProvider);
    ref.read(doubanImageProxyProvider.notifier).checkAndRefresh();
    final colors = context.colors;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: CustomScrollView(
            slivers: [
              // ─── Error Banner ────────────────────────────────────────────
              if (homeState.error != null)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.all(AppTheme.md),
                    padding: const EdgeInsets.all(AppTheme.md),
                    decoration: BoxDecoration(
                      color: colors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_off_rounded, color: colors.error, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '豆瓣数据无法加载，请下拉刷新重试',
                            style: TextStyle(color: colors.error, fontSize: 13),
                          ),
                        ),
                        GestureDetector(
                          onTap: _onRefresh,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: colors.error,
                              borderRadius: BorderRadius.circular(AppTheme.radiusTag),
                            ),
                            child: Text('重试', style: TextStyle(color: colors.textInverse, fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ─── Loading Indicator ───────────────────────────────────────
              if (homeState.isLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(AppTheme.md),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),

              // ─── Hero Banner ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: LayoutBuilder(
                builder: (context, constraints) {
                  final bannerHeight = constraints.maxWidth / (16 / 9);
                  return SizedBox(
                    height: bannerHeight,
                    child: Stack(
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: homeState.bannerSubjects.length,
                      onPageChanged: (i) => setState(() => _bannerIndex = i),
                      itemBuilder: (context, i) {
                        final subject = homeState.bannerSubjects[i];
                        final baseUrl = ref.read(apiClientProvider).baseUrl;
                        final imageUrl = proxyState.buildImageUrl(subject.originalCover, baseUrl);
                        final headers = proxyState.httpHeadersForUrl(subject.originalCover);
                        return _BannerCard(
                          subject: subject,
                          imageUrl: imageUrl,
                          httpHeaders: headers,
                          onTap: () {
                            // Navigate to search with douban_id + title
                            context.go('/search?douban_id=${subject.id}&q=${Uri.encodeComponent(subject.title)}');
                          },
                        );
                      },
                    ),
                    if (homeState.bannerSubjects.isNotEmpty)
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: SmoothPageIndicator(
                            controller: _pageController,
                            count: homeState.bannerSubjects.length,
                            effect: WormEffect(
                              dotWidth: 6,
                              dotHeight: 6,
                              activeDotColor: colors.primary,
                              dotColor: Colors.white38,
                            ),
                          ),
                        ),
                      ),
                  ],
                    ),
                  );
                },
              ),
            ),

            // ─── Stats Bar ────────────────────────────────────────────────
            // SliverToBoxAdapter(
            //   child: Padding(
            //     padding: const EdgeInsets.symmetric(horizontal: AppTheme.md, vertical: AppTheme.sm),
            //     child: Container(
            //       padding: const EdgeInsets.symmetric(vertical: 12, horizontal: AppTheme.md),
            //       decoration: BoxDecoration(
            //         color: colors.card,
            //         borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            //       ),
            //       child: const Row(
            //         mainAxisAlignment: MainAxisAlignment.spaceAround,
            //         children: [
            //           _StatItem(label: '电影', value: '12,400+'),
            //           _StatItem(label: '剧集', value: '3,800+'),
            //           _StatItem(label: '动漫', value: '5,200+'),
            //           _StatItem(label: '4K', value: '2,100+'),
            //         ],
            //       ),
            //     ),
            //   ),
            // ),

            // ─── Continue Watching (placeholder for logged-in users) ──────
            // TODO: implement when play-history API is ready

            // ─── Genre Pills ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.md, vertical: AppTheme.sm),
                child: SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: doubanState.movieTags.isNotEmpty ? doubanState.movieTags.length : 8,
                    separatorBuilder: (_, _) => const SizedBox(width: AppTheme.sm),
                    itemBuilder: (context, i) {
                      final tag = doubanState.movieTags.isNotEmpty ? doubanState.movieTags[i] : _defaultTags[i];
                      final isActive = tag == homeState.currentTag;
                      return GestureDetector(
                        onTap: () => ref.read(homeProvider.notifier).loadData(tag: tag),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppTheme.md, vertical: AppTheme.sm),
                          decoration: BoxDecoration(
                            color: isActive ? colors.primary : colors.card,
                            borderRadius: BorderRadius.circular(AppTheme.radiusTag),
                            border: Border.all(color: isActive ? colors.primary : colors.border),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              color: isActive ? colors.textInverse : colors.textSecondary,
                              fontSize: 13,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // ─── Hot Movies ───────────────────────────────────────────────
            if (homeState.hotMovies.isNotEmpty)
              SliverToBoxAdapter(
                child: _ContentSection(
                  title: '热门推荐',
                  items: homeState.hotMovies,
                ),
              ),

            // ─── Hot TV Series ────────────────────────────────────────────
            if (homeState.hotTvSeries.isNotEmpty)
              SliverToBoxAdapter(
                child: _ContentSection(
                  title: '热播剧集',
                  items: homeState.hotTvSeries,
                ),
              ),

            // ─── Membership promo banner ──────────────────────────────────
            // SliverToBoxAdapter(
            //   child: Padding(
            //     padding: const EdgeInsets.all(AppTheme.md),
            //     child: Container(
            //       padding: const EdgeInsets.all(AppTheme.md),
            //       decoration: BoxDecoration(
            //         gradient: LinearGradient(colors: [colors.primary, colors.primaryDark]),
            //         borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            //       ),
            //       child: Column(
            //         crossAxisAlignment: CrossAxisAlignment.start,
            //         children: [
            //           Text('解锁完整影视宇宙', style: TextStyle(color: colors.textInverse, fontSize: 18, fontWeight: FontWeight.w700)),
            //           const SizedBox(height: 4),
            //           Text('海量资源、极速搜索、无广告体验', style: TextStyle(color: colors.textInverse.withValues(alpha: 0.7), fontSize: 13)),
            //         ],
            //       ),
            //     ),
            //   ),
            // ),

            // Bottom padding for TabBar
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    ),
    );
  }

  static const _defaultTags = ['热门', '最新', '经典', '豆瓣高分', '冷门佳片', '华语', '欧美', '日本'];
}

class _BannerCard extends ConsumerStatefulWidget {
  final DoubanSubject subject;
  final String imageUrl;
  final VoidCallback onTap;
  final Map<String, String>? httpHeaders;
  const _BannerCard({required this.subject, required this.imageUrl, required this.onTap, this.httpHeaders});

  @override
  ConsumerState<_BannerCard> createState() => _BannerCardState();
}

class _BannerCardState extends ConsumerState<_BannerCard> {
  @override
  void initState() {
    super.initState();
    // 前端代理模式下触发图片下载
    if (widget.httpHeaders != null && widget.httpHeaders!.isNotEmpty) {
      Future.microtask(() {
        ref.read(proxyImageProvider(widget.imageUrl).notifier).load(widget.httpHeaders!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // 选择图片组件：前端代理模式用 ProxyImageProvider，否则用 CachedNetworkImage
    Widget imageWidget;
    if (widget.httpHeaders != null && widget.httpHeaders!.isNotEmpty) {
      final proxyState = ref.watch(proxyImageProvider(widget.imageUrl));
      if (proxyState.isLoading) {
        imageWidget = Container(color: colors.card);
      } else if (proxyState.hasError) {
        imageWidget = Container(color: colors.card);
      } else if (proxyState.localPath != null) {
        imageWidget = Image.file(
          File(proxyState.localPath!),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(color: colors.card),
        );
      } else {
        imageWidget = Container(color: colors.card);
      }
    } else {
      imageWidget = CachedNetworkImage(
        imageUrl: widget.imageUrl,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(color: colors.card),
        errorWidget: (_, _, _) => Container(color: colors.card),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppTheme.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          child: Stack(
            fit: StackFit.expand,
            children: [
              imageWidget,
              Positioned(
                left: AppTheme.md,
                right: AppTheme.md,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(AppTheme.radiusTag),
                      ),
                      child: Text('电影', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 8),
                    Text(widget.subject.title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.star, color: colors.warning, size: 14),
                        const SizedBox(width: 4),
                        Text(widget.subject.rate, style: TextStyle(color: colors.warning, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// class _StatItem extends StatelessWidget {
//   final String label;
//   final String value;
//   const _StatItem({required this.label, required this.value});
//
//   @override
//   Widget build(BuildContext context) {
//     final colors = context.colors;
//     return Column(
//       children: [
//         Text(value, style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
//         const SizedBox(height: 4),
//         Text(label, style: TextStyle(color: colors.textMuted, fontSize: 11)),
//       ],
//     );
//   }
// }

class _ContentSection extends ConsumerWidget {
  final String title;
  final List<DoubanSubject> items;
  const _ContentSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyState = ref.watch(doubanImageProxyProvider);
    ref.read(doubanImageProxyProvider.notifier).checkAndRefresh();
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.md),
      child: Column(
        children: [
          SectionHeader(title: title),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final baseUrl = ref.read(apiClientProvider).baseUrl;
                final imgProxyUrl = proxyState.buildImageUrl(items[i].cover, baseUrl);
                final headers = proxyState.httpHeadersForUrl(items[i].cover);
                return VideoCard(
                  title: items[i].title,
                  subtitle: items[i].rate,
                  imageUrl: imgProxyUrl,
                  httpHeaders: headers,
                  vodName: items[i].title,
                  vodPic: items[i].cover,
                  doubanId: items[i].id,
                  onTap: () {
                    // Navigate to search with douban_id + title
                    context.go('/search?douban_id=${items[i].id}&q=${Uri.encodeComponent(items[i].title)}');
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
