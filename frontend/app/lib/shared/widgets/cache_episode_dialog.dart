import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/cache/cache_meta.dart';
import '../../core/cache/play_cache_download_service.dart';
import '../../core/cache/play_cache_service.dart';
import '../../core/cache/cache_status_provider.dart';
import '../../core/theme/app_theme.dart' show BuildContextThemeX, AppColors;
import '../models/resource_detail.dart';
import 'cache_icons.dart';

/// 多集批量缓存选集弹窗
///
/// UI 模式复用 DownloadEpisodeDialog：
/// - 源切换标签（仅多源时显示）
/// - 剧集网格多选
/// - 全选/取消
/// - 提交按钮
class CacheEpisodeDialog extends ConsumerStatefulWidget {
  final List<PlaySource> sources;
  final int defaultSourceIndex;
  final int? defaultEpIndex;
  final String resourceDomain;
  final int vodId;

  const CacheEpisodeDialog({
    super.key,
    required this.sources,
    this.defaultSourceIndex = 0,
    this.defaultEpIndex,
    required this.resourceDomain,
    required this.vodId,
  });

  static Future<void> show(
    BuildContext context, {
    required List<PlaySource> sources,
    int defaultSourceIndex = 0,
    int? defaultEpIndex,
    required String resourceDomain,
    required int vodId,
  }) {
    return showDialog(
      context: context,
      builder: (_) => CacheEpisodeDialog(
        sources: sources,
        defaultSourceIndex: defaultSourceIndex,
        defaultEpIndex: defaultEpIndex,
        resourceDomain: resourceDomain,
        vodId: vodId,
      ),
    );
  }

  @override
  ConsumerState<CacheEpisodeDialog> createState() => _CacheEpisodeDialogState();
}

class _CacheEpisodeDialogState extends ConsumerState<CacheEpisodeDialog> {
  late int _sourceIndex;
  late Set<int> _selectedEps;
  bool _submitting = false;
  String? _resultMsg;
  bool _resultIsError = false;

  @override
  void initState() {
    super.initState();
    _sourceIndex = widget.defaultSourceIndex.clamp(0, widget.sources.length - 1);
    _selectedEps = {};
    if (widget.defaultEpIndex != null && widget.defaultEpIndex! >= 0) {
      final maxEp = (widget.sources[_sourceIndex].episodes.length - 1).clamp(0, 999999);
      final epIdx = widget.defaultEpIndex!.clamp(0, maxEp);
      _selectedEps = {epIdx};
    }

    // 预加载当前源的缓存状态
    Future.microtask(() {
      final episodes = widget.sources[_sourceIndex].episodes;
      ref.read(cacheStatusProvider.notifier).checkStatuses(
        episodes,
        _sourceIndex,
        widget.resourceDomain,
        widget.vodId,
      );
    });
  }

  List<PlayEpisode> get _currentEpisodes => widget.sources[_sourceIndex].episodes;

  void _toggleSource(int idx) {
    if (idx == _sourceIndex) return;
    setState(() {
      _sourceIndex = idx;
      _selectedEps = {};
      _resultMsg = null;
    });
    // 切换源时预加载缓存状态
    final episodes = widget.sources[idx].episodes;
    ref.read(cacheStatusProvider.notifier).checkStatuses(
      episodes,
      idx,
      widget.resourceDomain,
      widget.vodId,
    );
  }

  void _toggleEp(int epIdx) {
    setState(() {
      final next = Set<int>.from(_selectedEps);
      if (next.contains(epIdx)) {
        next.remove(epIdx);
      } else {
        next.add(epIdx);
      }
      _selectedEps = next;
    });
  }

  void _toggleAll() {
    setState(() {
      if (_selectedEps.length == _currentEpisodes.length) {
        _selectedEps = {};
      } else {
        _selectedEps = Set.from(List.generate(_currentEpisodes.length, (i) => i));
      }
    });
  }

  Future<void> _handleSubmit() async {
    if (_selectedEps.isEmpty) return;
    setState(() {
      _submitting = true;
      _resultMsg = null;
    });

    final episodes = _currentEpisodes;
    final items = _selectedEps.map((epIdx) {
      final ep = episodes[epIdx];
      return (
        key: PlayCacheService.instance.cacheKey(widget.resourceDomain, widget.vodId, _sourceIndex, epIdx),
        url: ep.url,
        resourceDomain: widget.resourceDomain,
        vodId: widget.vodId,
        sourceIndex: _sourceIndex,
        epIndex: epIdx,
      );
    }).toList();

    // 调用批量下载
    try {
      await PlayCacheDownloadService.instance.startBatchDownload(items);

      setState(() {
        _resultMsg = '已添加 ${_selectedEps.length} 个缓存任务';
        _resultIsError = false;
        _selectedEps = {};
      });

      // 刷新缓存状态
      ref.read(cacheStatusProvider.notifier).checkStatuses(
        episodes,
        _sourceIndex,
        widget.resourceDomain,
        widget.vodId,
      );
    } catch (e) {
      setState(() {
        _resultMsg = '失败: $e';
        _resultIsError = true;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final episodes = _currentEpisodes;
    final cacheStatuses = ref.watch(cacheStatusProvider);

    // 获取当前源所有剧集的缓存状态
    Map<int, EpisodeCacheStatus> currentCacheStatuses() {
      final result = <int, EpisodeCacheStatus>{};
      for (var i = 0; i < episodes.length; i++) {
        final key = PlayCacheService.instance.cacheKey(widget.resourceDomain, widget.vodId, _sourceIndex, i);
        final status = cacheStatuses[key];
        if (status != null) {
          result[i] = status;
        }
      }
      return result;
    }

    final currentStatuses = currentCacheStatuses();

    return AlertDialog(
      backgroundColor: colors.card,
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Row(
        children: [
          Icon(Icons.storage_outlined, size: 20, color: colors.textPrimary),
          const SizedBox(width: 8),
          Text('缓存剧集', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Source tabs (only show when multiple sources)
              if (widget.sources.length > 1) ...[
                const SizedBox(height: 4),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.sources.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final src = widget.sources[idx];
                      final isActive = idx == _sourceIndex;
                      return GestureDetector(
                        onTap: () => _toggleSource(idx),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isActive ? colors.primary.withValues(alpha: 0.15) : colors.elevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isActive ? colors.primary.withValues(alpha: 0.4) : colors.border),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.dns, size: 12, color: isActive ? colors.primary : colors.textMuted),
                            const SizedBox(width: 4),
                            Text(src.name.isNotEmpty ? src.name : '线路${idx + 1}',
                                style: TextStyle(color: isActive ? colors.primary : colors.textMuted, fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400)),
                            const SizedBox(width: 4),
                            Text('(${src.episodes.length})', style: TextStyle(color: isActive ? colors.primary : colors.textMuted, fontSize: 10)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Select all / count
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('已选 ${_selectedEps.length}/${episodes.length} 集',
                      style: TextStyle(color: colors.textMuted, fontSize: 12)),
                  GestureDetector(
                    onTap: _toggleAll,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _selectedEps.length == episodes.length
                            ? colors.primary.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _selectedEps.length == episodes.length ? '取消全选' : '全选',
                        style: TextStyle(color: colors.primary, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Episode grid
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(episodes.length, (idx) {
                      final ep = episodes[idx];
                      final selected = _selectedEps.contains(idx);
                      final cacheStatus = currentStatuses[idx];

                      return GestureDetector(
                        onTap: () => _toggleEp(idx),
                        child: _CacheEpButton(
                          epName: ep.name,
                          selected: selected,
                          cacheStatus: cacheStatus,
                          colors: colors,
                        ),
                      );
                    }),
                  ),
                ),
              ),

              // Result message
              if (_resultMsg != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _resultIsError
                        ? colors.error.withValues(alpha: 0.08)
                        : colors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(
                      _resultIsError ? Icons.error_outline : Icons.check_circle_outline,
                      size: 14,
                      color: _resultIsError ? colors.error : colors.success,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_resultMsg!,
                          style: TextStyle(color: _resultIsError ? colors.error : colors.success, fontSize: 12)),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting || _selectedEps.isEmpty ? null : _handleSubmit,
          style: TextButton.styleFrom(
            foregroundColor: colors.primary,
          ),
          child: _submitting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
                )
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.save_alt, size: 14),
                  const SizedBox(width: 4),
                  Text('缓存选中 (${_selectedEps.length})'),
                ]),
        ),
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('关闭', style: TextStyle(color: colors.textMuted)),
        ),
      ],
    );
  }
}

/// 单个剧集缓存按钮，显示缓存状态标记
class _CacheEpButton extends StatelessWidget {
  final String epName;
  final bool selected;
  final EpisodeCacheStatus? cacheStatus;
  final AppColors colors;

  const _CacheEpButton({
    required this.epName,
    required this.selected,
    this.cacheStatus,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final isComplete = cacheStatus?.isComplete ?? false;
    final isCaching = cacheStatus?.isCaching ?? false;
    final isPaused = cacheStatus?.taskStatus == CacheTaskStatus.paused;
    final hasPartialCache = (cacheStatus?.downloadedBytes ?? 0) > 0 && !isComplete;

    Color borderColor;
    Color bgColor;
    Color textColor;
    // 缓存状态徽章 Widget（自带语义色，无需 statusIconColor）
    Widget? statusIcon;
    // selected 分支的选择勾颜色
    Color statusIconColor = colors.primary;

    if (isComplete) {
      borderColor = colors.success.withValues(alpha: 0.4);
      bgColor = colors.success.withValues(alpha: 0.08);
      textColor = colors.success;
      statusIcon = CacheIcons.cacheComplete(size: 12);
    } else if (isCaching) {
      borderColor = colors.primary.withValues(alpha: 0.4);
      bgColor = colors.primary.withValues(alpha: 0.08);
      textColor = colors.primary;
      statusIcon = CacheIcons.cacheCaching(size: 12);
    } else if (isPaused) {
      borderColor = colors.warning.withValues(alpha: 0.4);
      bgColor = colors.warning.withValues(alpha: 0.08);
      textColor = colors.warning;
      statusIcon = CacheIcons.cachePaused(size: 12);
    } else if (hasPartialCache) {
      borderColor = colors.warning.withValues(alpha: 0.4);
      bgColor = colors.warning.withValues(alpha: 0.08);
      textColor = colors.warning;
      statusIcon = CacheIcons.cachePartial(size: 12);
    } else if (selected) {
      borderColor = colors.primary;
      bgColor = colors.primary.withValues(alpha: 0.15);
      textColor = colors.primary;
      statusIcon = null;
      statusIconColor = colors.primary;
    } else {
      borderColor = colors.border;
      bgColor = colors.elevated;
      textColor = colors.textMuted;
      statusIcon = null;
      statusIconColor = colors.textMuted;
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 60),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (statusIcon != null) ...[
          statusIcon,
          const SizedBox(width: 4),
        ] else if (selected) ...[
          Icon(Icons.check_circle, size: 12, color: statusIconColor),
          const SizedBox(width: 4),
        ],
        Text(
          epName,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ]),
    );
  }
}
