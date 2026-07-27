import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowtv_mobile/core/logger/app_logger.dart';
import 'package:meowtv_mobile/core/utils/native_file_picker.dart';
import 'package:meowtv_mobile/features/player/subtitle/subtitle_manager.dart';
import 'package:meowtv_mobile/features/player/subtitle/subtitle_model.dart';
import 'package:meowtv_mobile/features/player/subtitle/subtitle_parser.dart';
import 'package:meowtv_mobile/features/player/subtitle/subtitle_provider.dart';
import 'styles.dart';

/// 字幕设置面板
class SubtitlePanel extends ConsumerStatefulWidget {
  final VoidCallback onDismiss;
  final double scale;
  final double maxHeight;
  final double playerWidth;

  const SubtitlePanel({
    super.key,
    required this.onDismiss,
    required this.scale,
    required this.maxHeight,
    required this.playerWidth,
  });

  @override
  ConsumerState<SubtitlePanel> createState() => _SubtitlePanelState();
}

class _SubtitlePanelState extends ConsumerState<SubtitlePanel> {
  bool _searching = false;
  List<SubtitleSearchResult>? _searchResults;
  String? _searchError;

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(subtitleManagerProvider);
    final registry = ref.read(subtitleSourceRegistryProvider);
    final isOff = manager.mode == SubtitleMode.off;
    final scale = widget.scale;

    return Container(
      width: PlayerControlsStyles.scaledWidth(260, widget.playerWidth),
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      decoration: BoxDecoration(
        color: PlayerControlsStyles.panelBg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(PlayerControlsStyles.scaledPadding(9, scale)),
          bottomLeft: Radius.circular(PlayerControlsStyles.scaledPadding(9, scale)),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Header ──
          Padding(
            padding: EdgeInsets.fromLTRB(
              PlayerControlsStyles.scaledPadding(9, scale),
              PlayerControlsStyles.scaledPadding(9, scale),
              PlayerControlsStyles.scaledPadding(7, scale),
              PlayerControlsStyles.scaledPadding(7, scale),
            ),
            child: Row(children: [
              Text('字幕', style: TextStyle(
                color: PlayerControlsStyles.textColor,
                fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                fontWeight: FontWeight.w600,
              )),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close,
                    color: PlayerControlsStyles.iconColor, size: PlayerControlsStyles.scaledFontSize(10, scale)),
                onPressed: widget.onDismiss,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: PlayerControlsStyles.scaledPadding(28, scale), minHeight: PlayerControlsStyles.scaledPadding(28, scale)),
              ),
            ]),
          ),
          const Divider(color: Colors.white12, height: 1),

          // ── Off ──
          _RadioItem(
            title: '关闭',
            isActive: isOff,
            onTap: () {
              manager.disable();
            },
            scale: scale,
          ),

          // ── Embedded tracks ──
          if (manager.embeddedTracks.isNotEmpty) ...[
            _SectionHeader('内嵌字幕', scale: scale),
            for (final track in manager.embeddedTracks)
              _RadioItem(
                title: track.label.isNotEmpty ? track.label : '轨道 ${track.index}',
                subtitle: track.language.isNotEmpty ? track.language : null,
                isActive: manager.mode == SubtitleMode.embedded &&
                    manager.activeTrack?.id == 'embedded_${track.index}',
                onTap: () => _selectEmbeddedTrack(manager, track),
                scale: scale,
              ),
          ],

          // ── External subtitle ──
          _SectionHeader('外挂字幕', scale: scale),
          _ActionItem(
            title: manager.mode == SubtitleMode.external
                ? (manager.activeTrack?.label ?? '已加载外挂字幕')
                : '加载字幕文件...',
            isActive: manager.mode == SubtitleMode.external,
            icon: Icons.folder_open,
            onTap: _loadExternalSubtitle,
            scale: scale,
          ),

          // ── Online search ──
          if (registry.hasSources) ...[
            _SectionHeader('在线搜索', scale: scale),
            if (_searching)
              Padding(
                padding: EdgeInsets.symmetric(vertical: PlayerControlsStyles.scaledPadding(9, scale)),
                child: Center(child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: PlayerControlsStyles.speedActive,
                  ),
                )),
              )
            else if (_searchResults != null)
              ..._buildSearchResults(manager, _searchResults!)
            else if (_searchError != null)
              _ErrorItem(_searchError!, onRetry: _searchOnline, scale: scale)
            else
              _ActionItem(
                title: '搜索在线字幕...',
                icon: Icons.search,
                isActive: false,
                onTap: _searchOnline,
                scale: scale,
              ),
          ],

          // ── Timeline offset ──
          _SectionHeader('时间轴偏移', scale: scale),
          _OffsetControl(
            offsetMs: manager.offsetMs,
            onOffsetChanged: (ms) => manager.setOffset(ms),
            scale: scale,
          ),

          SizedBox(height: PlayerControlsStyles.scaledPadding(7, scale)),
        ]),
      ),
    );
  }

  // ── Embedded track selection ──────────────────────────────────────────────

  void _selectEmbeddedTrack(SubtitleManager manager, EmbeddedSubtitleTrack track) {
    // Embedded tracks come from the native player; we create a SubtitleTrack
    // placeholder. The actual cue population is handled by the native layer.
    manager.selectTrack(SubtitleTrack(
      id: 'embedded_${track.index}',
      label: track.label.isNotEmpty ? track.label : '轨道 ${track.index}',
      language: track.language,
      source: SubtitleSource.embedded,
      cues: const [], // cues populated by native player
    ));
  }

  // ── External subtitle loading ─────────────────────────────────────────────

  Future<void> _loadExternalSubtitle() async {
    try {
      final uri = await NativeFilePicker.pickFile(mimeTypes: [
        'text/plain',
        'application/x-subrip',
        'text/vtt',
        'application/x-ass',
        'application/x-ssa',
      ]);
      if (uri == null) return;

      // Determine format from file extension
      final ext = uri.split('.').last.toLowerCase();
      final parser = SubtitleParserFactory.create(ext);
      if (parser == null) {
        appLogger.w('[SubtitlePanel] 不支持的字幕格式: $ext');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('不支持的字幕格式')),
          );
        }
        return;
      }

      // Read file content via native channel
      final content = await NativeFilePicker.readFileContent(uri);
      if (content == null || content.trim().isEmpty) {
        appLogger.w('[SubtitlePanel] 字幕文件内容为空');
        return;
      }

      final cues = await parser.parse(content);
      if (cues.isEmpty) {
        appLogger.w('[SubtitlePanel] 未解析到字幕条目');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未解析到字幕条目')),
          );
        }
        return;
      }

      // Extract display name from URI
      final fileName = uri.split('/').last;

      final manager = ref.read(subtitleManagerProvider);
      manager.selectTrack(SubtitleTrack(
        id: 'external_$uri',
        label: fileName,
        language: '',
        source: SubtitleSource.external,
        cues: cues,
      ));

      appLogger.i('[SubtitlePanel] 加载外挂字幕: $fileName (${cues.length} 条)');
    } catch (e) {
      appLogger.w('[SubtitlePanel] 加载外挂字幕失败: $e');
    }
  }

  // ── Online search ─────────────────────────────────────────────────────────

  Future<void> _searchOnline() async {
    final registry = ref.read(subtitleSourceRegistryProvider);
    if (!registry.hasSources) return;

    setState(() {
      _searching = true;
      _searchResults = null;
      _searchError = null;
    });

    try {
      // Use the first available source for now
      final source = registry.available.first;
      // TODO: Build query from current video metadata when available
      const query = SubtitleSearchQuery(language: 'zh');
      final results = await source.search(query);
      if (mounted) {
        setState(() {
          _searching = false;
          _searchResults = results;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          _searchError = e.toString();
        });
      }
    }
  }

  List<Widget> _buildSearchResults(SubtitleManager manager, List<SubtitleSearchResult> results) {
    final scale = widget.scale;
    if (results.isEmpty) {
      return [
        Padding(
          padding: EdgeInsets.symmetric(
            vertical: PlayerControlsStyles.scaledPadding(7, scale),
            horizontal: PlayerControlsStyles.scaledPadding(9, scale),
          ),
          child: Text('未找到在线字幕', style: TextStyle(
            color: PlayerControlsStyles.textSecondary,
            fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
          )),
        ),
      ];
    }

    return results.map((result) {
      final isActive = manager.mode == SubtitleMode.online &&
          manager.activeTrack?.id == 'online_${result.id}';
      return _RadioItem(
        title: result.label,
        subtitle: result.language,
        isActive: isActive,
        onTap: () => _downloadOnlineSubtitle(result),
        scale: scale,
      );
    }).toList();
  }

  Future<void> _downloadOnlineSubtitle(SubtitleSearchResult result) async {
    final registry = ref.read(subtitleSourceRegistryProvider);
    final source = registry.get(result.sourceId);
    if (source == null) return;

    try {
      final download = await source.download(result);
      final parser = SubtitleParserFactory.create(download.format);
      if (parser == null) return;

      final cues = await parser.parse(download.content);
      if (cues.isEmpty) return;

      final manager = ref.read(subtitleManagerProvider);
      manager.selectTrack(SubtitleTrack(
        id: 'online_${result.id}',
        label: result.label,
        language: result.language,
        source: SubtitleSource.online,
        cues: cues,
      ));
    } catch (e) {
      appLogger.w('[SubtitlePanel] 下载在线字幕失败: $e');
    }
  }
}

// ── UI Components ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final double scale;
  const _SectionHeader(this.title, {required this.scale});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        PlayerControlsStyles.scaledPadding(9, scale),
        PlayerControlsStyles.scaledPadding(9, scale),
        PlayerControlsStyles.scaledPadding(9, scale),
        PlayerControlsStyles.scaledPadding(4, scale),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: TextStyle(
          color: PlayerControlsStyles.textSecondary,
          fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
          fontWeight: FontWeight.w600,
        )),
      ),
    );
  }
}

class _RadioItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isActive;
  final VoidCallback onTap;
  final double scale;

  const _RadioItem({
    required this.title,
    this.subtitle,
    required this.isActive,
    required this.onTap,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: PlayerControlsStyles.scaledPadding(9, scale),
          vertical: PlayerControlsStyles.scaledPadding(7, scale),
        ),
        child: Row(children: [
          // Radio indicator
          Container(
            width: 14, height: 14,
            margin: EdgeInsets.only(right: PlayerControlsStyles.scaledPadding(9, scale)),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive
                    ? PlayerControlsStyles.speedActive
                    : PlayerControlsStyles.speedInactive,
                width: 2,
              ),
            ),
            child: isActive
                ? Center(child: Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: PlayerControlsStyles.speedActive,
                    ),
                  ))
                : null,
          ),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(
                color: isActive
                    ? PlayerControlsStyles.speedActive
                    : PlayerControlsStyles.speedInactive,
                fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              )),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(
                  color: PlayerControlsStyles.textSecondary,
                  fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
                )),
            ],
          )),
        ]),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final String title;
  final bool isActive;
  final IconData icon;
  final VoidCallback onTap;
  final double scale;

  const _ActionItem({
    required this.title,
    required this.isActive,
    required this.icon,
    required this.onTap,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: PlayerControlsStyles.scaledPadding(9, scale),
          vertical: PlayerControlsStyles.scaledPadding(9, scale),
        ),
        child: Row(children: [
          Icon(icon,
              color: isActive
                  ? PlayerControlsStyles.speedActive
                  : PlayerControlsStyles.speedInactive,
              size: PlayerControlsStyles.scaledFontSize(10, scale)),
          SizedBox(width: PlayerControlsStyles.scaledPadding(7, scale)),
          Expanded(child: Text(title, style: TextStyle(
            color: isActive
                ? PlayerControlsStyles.speedActive
                : PlayerControlsStyles.speedInactive,
            fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ))),
        ]),
      ),
    );
  }
}

class _ErrorItem extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final double scale;

  const _ErrorItem(this.message, {required this.onRetry, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: PlayerControlsStyles.scaledPadding(7, scale),
        horizontal: PlayerControlsStyles.scaledPadding(9, scale),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message, style: TextStyle(
          color: PlayerControlsStyles.speedInactive,
          fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
        ), maxLines: 2, overflow: TextOverflow.ellipsis),
        SizedBox(height: PlayerControlsStyles.scaledPadding(7, scale)),
        GestureDetector(
          onTap: onRetry,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: PlayerControlsStyles.scaledPadding(9, scale),
              vertical: PlayerControlsStyles.scaledPadding(5, scale),
            ),
            decoration: BoxDecoration(
              color: PlayerControlsStyles.speedActive,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('重试', style: TextStyle(
              color: Colors.white, fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
            )),
          ),
        ),
      ]),
    );
  }
}

class _OffsetControl extends StatelessWidget {
  final double offsetMs;
  final ValueChanged<double> onOffsetChanged;
  final double scale;

  const _OffsetControl({
    required this.offsetMs,
    required this.onOffsetChanged,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: PlayerControlsStyles.scaledPadding(9, scale),
        vertical: PlayerControlsStyles.scaledPadding(5, scale),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Current offset display
        Text(
          offsetMs == 0.0 ? '0 ms' : '${offsetMs > 0 ? '+' : ''}${offsetMs.round()} ms',
          style: TextStyle(
            color: offsetMs == 0.0
                ? PlayerControlsStyles.textSecondary
                : PlayerControlsStyles.speedActive,
            fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: PlayerControlsStyles.scaledPadding(5, scale)),
        // Offset buttons
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _offsetButton('-1s', -1000),
          _offsetButton('-0.5s', -500),
          _offsetButton('重置', 0, isReset: true),
          _offsetButton('+0.5s', 500),
          _offsetButton('+1s', 1000),
        ]),
      ]),
    );
  }

  Widget _offsetButton(String label, double delta, {bool isReset = false}) {
    final isActive = isReset
        ? offsetMs == 0.0
        : false;

    return Expanded(
      child: GestureDetector(
        onTap: () => onOffsetChanged(isReset ? 0.0 : offsetMs + delta),
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: PlayerControlsStyles.scaledPadding(2, scale)),
          padding: EdgeInsets.symmetric(vertical: PlayerControlsStyles.scaledPadding(5, scale)),
          decoration: BoxDecoration(
            color: isActive
                ? PlayerControlsStyles.speedActive.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(child: Text(label, style: TextStyle(
            color: isActive
                ? PlayerControlsStyles.speedActive
                : PlayerControlsStyles.speedInactive,
            fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ))),
        ),
      ),
    );
  }
}
