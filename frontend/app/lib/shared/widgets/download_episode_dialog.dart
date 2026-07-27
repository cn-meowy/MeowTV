import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/theme/app_theme.dart' show BuildContextThemeX;
import '../models/resource_detail.dart';

/// Props for creating a download task item.
class _DownloadItem {
  final int sourceIndex;
  final int epIndex;
  final String epName;
  final String m3u8Url;
  const _DownloadItem({
    required this.sourceIndex,
    required this.epIndex,
    required this.epName,
    required this.m3u8Url,
  });
  Map<String, dynamic> toJson() => {
    'source_index': sourceIndex,
    'ep_index': epIndex,
    'ep_name': epName,
    'm3u8_url': m3u8Url,
  };
}

/// Download episode selection dialog.
///
/// Mirrors the logic of Web's DownloadEpisodeDialog.tsx:
/// - Switches between sources (tabs)
/// - Multi-select episodes with checkboxes
/// - Select all / deselect all
/// - Submits to /api/download/create with the correct items array format
class DownloadEpisodeDialog extends ConsumerStatefulWidget {
  /// Multi-source episode lists.
  final List<PlaySource> sources;

  /// Default selected source index (e.g. current playing source).
  final int defaultSourceIndex;

  /// Default selected episode index (e.g. current playing episode).
  final int? defaultEpIndex;

  /// Video basic info for the download task.
  final int vodId;
  final String vodName;
  final String? vodPic;
  final String resourceDomain;
  final String resourceName;
  final String groupKey;

  const DownloadEpisodeDialog({
    super.key,
    required this.sources,
    this.defaultSourceIndex = 0,
    this.defaultEpIndex,
    required this.vodId,
    required this.vodName,
    this.vodPic,
    required this.resourceDomain,
    required this.resourceName,
    this.groupKey = '',
  });

  /// Show the dialog using showDialog.
  static Future<void> show(
    BuildContext context, {
    required List<PlaySource> sources,
    int defaultSourceIndex = 0,
    int? defaultEpIndex,
    required int vodId,
    required String vodName,
    String? vodPic,
    required String resourceDomain,
    required String resourceName,
    String groupKey = '',
  }) {
    return showDialog(
      context: context,
      builder: (_) => DownloadEpisodeDialog(
        sources: sources,
        defaultSourceIndex: defaultSourceIndex,
        defaultEpIndex: defaultEpIndex,
        vodId: vodId,
        vodName: vodName,
        vodPic: vodPic,
        resourceDomain: resourceDomain,
        resourceName: resourceName,
        groupKey: groupKey,
      ),
    );
  }

  @override
  ConsumerState<DownloadEpisodeDialog> createState() => _DownloadEpisodeDialogState();
}

class _DownloadEpisodeDialogState extends ConsumerState<DownloadEpisodeDialog> {
  late int _sourceIndex;
  late Set<int> _selectedEps;
  bool _submitting = false;
  String? _resultMsg;
  bool _resultIsError = false;

  @override
  void initState() {
    super.initState();
    _sourceIndex = widget.defaultSourceIndex.clamp(0, widget.sources.length - 1);
    // Default: select current episode (if provided) or none
    _selectedEps = {};
    if (widget.defaultEpIndex != null && widget.defaultEpIndex! >= 0) {
      final maxEp = (widget.sources[_sourceIndex].episodes.length - 1).clamp(0, 999999);
      final epIdx = widget.defaultEpIndex!.clamp(0, maxEp);
      _selectedEps = {epIdx};
    }
  }

  List<PlayEpisode> get _currentEpisodes => widget.sources[_sourceIndex].episodes;

  void _toggleSource(int idx) {
    if (idx == _sourceIndex) return;
    setState(() {
      _sourceIndex = idx;
      _selectedEps = {};
      _resultMsg = null;
    });
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
    final items = _selectedEps.map((epIdx) => _DownloadItem(
      sourceIndex: _sourceIndex,
      epIndex: epIdx,
      epName: episodes[epIdx].name,
      m3u8Url: episodes[epIdx].url,
    )).toList();

    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.post<Map<String, dynamic>>(ApiConstants.downloadCreate, data: {
        'vod_id': widget.vodId,
        'vod_name': widget.vodName,
        'vod_pic': widget.vodPic ?? '',
        'resource_domain': widget.resourceDomain,
        'resource_name': widget.resourceName,
        'group_key': widget.groupKey,
        'items': items.map((i) => i.toJson()).toList(),
      });

      final body = resp.data as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>?;
      final queued = data?['queued'] as int? ?? 0;
      final skipped = data?['skipped'] as int? ?? 0;
      setState(() {
        _resultMsg = '已添加 $queued 个任务${skipped > 0 ? '，跳过 $skipped 个（已存在）' : ''}';
        _resultIsError = false;
        _selectedEps = {};
      });
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

    return AlertDialog(
      backgroundColor: colors.card,
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Row(
        children: [
          Icon(Icons.download_outlined, size: 20, color: colors.textPrimary),
          const SizedBox(width: 8),
          Text('下载剧集', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
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
                    return GestureDetector(
                      onTap: () => _toggleEp(idx),
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 60),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? colors.primary.withValues(alpha: 0.15) : colors.elevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: selected ? colors.primary.withValues(alpha: 0.4) : colors.border),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (selected) ...[
                            Icon(Icons.check_circle, size: 12, color: colors.primary),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            ep.name,
                            style: TextStyle(
                              color: selected ? colors.primary : colors.textMuted,
                              fontSize: 12,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ]),
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
                  Icon(Icons.download, size: 14),
                  const SizedBox(width: 4),
                  Text('下载选中 (${_selectedEps.length})'),
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
