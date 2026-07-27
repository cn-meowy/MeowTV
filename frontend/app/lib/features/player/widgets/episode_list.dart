import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart' show BuildContextThemeX;
import '../../../core/cache/cache_status_provider.dart';
import '../../../core/cache/cache_meta.dart';
import '../../../core/cache/play_cache_service.dart';
import '../../../shared/models/resource_detail.dart';
import '../../../shared/widgets/m3u8_status_indicator.dart';
import '../../../shared/widgets/cache_icons.dart';

const _collapseThreshold = 24;
const _groupSize = 20;
/// Max height for the episode Wrap when expanded (scrollable when exceeded).
const _expandedMaxHeight = 280.0;

class EpisodeList extends ConsumerStatefulWidget {
  final List<PlayEpisode> episodes;
  final int activeIndex;
  final int vodId;
  final int sourceIndex;
  final ValueChanged<int> onSelect;
  const EpisodeList({super.key, required this.episodes, required this.activeIndex, required this.vodId, required this.sourceIndex, required this.onSelect});
  @override
  ConsumerState<EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends ConsumerState<EpisodeList> {
  bool _reversed = false;
  bool _expanded = false;
  int _activeGroupStart = 0;

  @override
  void initState() {
    super.initState();
    _activeGroupStart = (widget.activeIndex ~/ _groupSize) * _groupSize;
  }

  @override
  void didUpdateWidget(covariant EpisodeList old) {
    super.didUpdateWidget(old);
    if (old.activeIndex != widget.activeIndex) {
      final gs = (widget.activeIndex ~/ _groupSize) * _groupSize;
      if (gs != _activeGroupStart) setState(() => _activeGroupStart = gs);
    }
  }

  List<PlayEpisode> get _displayList {
    final list = _reversed ? widget.episodes.reversed.toList() : widget.episodes;
    if (!_expanded && list.length > _collapseThreshold) return list.sublist(0, _collapseThreshold);
    return list;
  }

  int _origIdx(int i) => _reversed ? widget.episodes.length - 1 - i : i;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (widget.episodes.isEmpty) { return Container(
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: colors.border)),
      padding: const EdgeInsets.all(16),
      child: Center(child: Text('暂无剧集', style: TextStyle(color: colors.textMuted, fontSize: 12))),
    ); }
    final display = _displayList;
    final hasMore = widget.episodes.length > _collapseThreshold && !_expanded;
    final gridWidth = (MediaQuery.of(context).size.width - 56) / 4 - 6;

    return Container(
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: colors.border)),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('剧集列表 · 共 ${widget.episodes.length} 集', style: TextStyle(color: colors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(onTap: () => setState(() => _reversed = !_reversed), child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: _reversed ? colors.primary.withValues(alpha: 0.15) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.swap_vert, size: 12, color: _reversed ? colors.primary : colors.textMuted),
              const SizedBox(width: 2),
              Text(_reversed ? '倒序' : '正序', style: TextStyle(color: _reversed ? colors.primary : colors.textMuted, fontSize: 11)),
            ]),
          )),
        ]),
        const SizedBox(height: 8),
        if (widget.episodes.length > _groupSize) GroupNav(
          total: widget.episodes.length, activeIndex: widget.activeIndex,
          activeGroupStart: _activeGroupStart,
          onSelect: (s) => setState(() { _activeGroupStart = s; if (!_expanded && widget.episodes.length > _collapseThreshold) _expanded = true; }),
        ),
        if (widget.episodes.length > _groupSize) const SizedBox(height: 8),
        // Constrain episode Wrap height when expanded to prevent unbounded growth
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: _expanded ? _expandedMaxHeight : double.infinity),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Wrap(spacing: 6, runSpacing: 6, children: display.asMap().entries.map((e) {
              final orig = _origIdx(e.key);
              final active = orig == widget.activeIndex;
              return _EpisodeButton(
                episode: e.value,
                isActive: active,
                cacheKey: PlayCacheService.instance.cacheKey(
                  '', // resourceDomain 在 EpisodeList 层面不可知，传空由内部处理
                  widget.vodId,
                  widget.sourceIndex,
                  orig,
                ),
                onTap: () => widget.onSelect(orig),
                gridWidth: gridWidth,
              );
            }).toList()),
          ),
        ),
        if (hasMore || _expanded) Padding(padding: const EdgeInsets.only(top: 8), child: GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 14, color: colors.primary),
              const SizedBox(width: 4),
              Text(_expanded ? '收起' : '展开全部 ${widget.episodes.length} 集', style: TextStyle(color: colors.primary, fontSize: 12)),
            ]),
          ),
        )),
      ]),
    );
  }
}

class GroupNav extends StatelessWidget {
  final int total;
  final int activeIndex;
  final int activeGroupStart;
  final ValueChanged<int> onSelect;
  const GroupNav({super.key, required this.total, required this.activeIndex, required this.activeGroupStart, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final groups = <_Grp>[];
    for (var i = 0; i < total; i += _groupSize) {
      final end = (i + _groupSize - 1).clamp(0, total - 1);
      groups.add(_Grp('${i + 1}-${end + 1}', i, end));
    }
    if (groups.length <= 1) return const SizedBox.shrink();
    final activeIdx = groups.indexWhere((g) => activeIndex >= g.start && activeIndex <= g.end);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(color: colors.elevated, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        // 上一组
        GestureDetector(onTap: activeIdx > 0 ? () => onSelect(groups[activeIdx - 1].start) : null, child: Container(
          width: 24, height: 24, alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
          child: Icon(Icons.chevron_left, size: 16, color: activeIdx > 0 ? colors.textMuted : colors.textMuted.withValues(alpha: 0.4)),
        )),
        // 分组标签
        Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: groups.asMap().entries.map((e) {
          final idx = e.key;
          final g = e.value;
          final active = idx == activeIdx;
          return GestureDetector(onTap: () => onSelect(g.start), child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: active ? colors.primary.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: active ? Border.all(color: colors.primary.withValues(alpha: 0.3)) : null,
            ),
            child: Text(g.label, style: TextStyle(color: active ? colors.primary : colors.textMuted, fontSize: 11, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
          ));
        }).toList()))),
        // 下一组
        GestureDetector(onTap: activeIdx < groups.length - 1 ? () => onSelect(groups[activeIdx + 1].start) : null, child: Container(
          width: 24, height: 24, alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
          child: Icon(Icons.chevron_right, size: 16, color: activeIdx < groups.length - 1 ? colors.textMuted : colors.textMuted.withValues(alpha: 0.4)),
        )),
      ]),
    );
  }
}

class _Grp {
  final String label;
  final int start;
  final int end;
  const _Grp(this.label, this.start, this.end);
}

/// 剧集按钮，含缓存状态标记
class _EpisodeButton extends ConsumerWidget {
  final PlayEpisode episode;
  final bool isActive;
  final String cacheKey;
  final VoidCallback onTap;
  final double gridWidth;

  const _EpisodeButton({
    required this.episode,
    required this.isActive,
    required this.cacheKey,
    required this.onTap,
    required this.gridWidth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final cacheStatus = ref.watch(cacheStatusProvider)[cacheKey];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: gridWidth,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? colors.primary.withValues(alpha: 0.15) : colors.elevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? colors.primary.withValues(alpha: 0.4) : colors.border),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Text(
                episode.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? colors.primary : colors.textMuted,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            // 缓存状态标记
            if (cacheStatus != null && cacheStatus.hasCache)
              Positioned(
                right: 2,
                top: 2,
                child: _CacheStatusBadge(status: cacheStatus),
              ),
            // M3u8 检测状态标记 (左下角)
            Positioned(
              left: 2,
              bottom: 2,
              child: M3u8StatusIndicator(url: episode.url, size: 10),
            ),
          ],
        ),
      ),
    );
  }
}

/// 缓存状态徽章
class _CacheStatusBadge extends StatelessWidget {
  final EpisodeCacheStatus status;

  const _CacheStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    // 缓存状态徽章缩小至 80%（14 -> 11.2）
    if (status.isComplete) {
      return CacheIcons.cacheComplete(size: 14 * 0.8);
    }
    if (status.isCaching) {
      return CacheIcons.cacheCaching(size: 14 * 0.8);
    }
    if (status.taskStatus == CacheTaskStatus.paused) {
      return CacheIcons.cachePaused(size: 14 * 0.8);
    }
    if (status.downloadedBytes > 0) {
      return CacheIcons.cachePartial(size: 14 * 0.8);
    }
    return const SizedBox.shrink();
  }
}
