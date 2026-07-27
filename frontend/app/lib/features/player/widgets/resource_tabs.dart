import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart' show BuildContextThemeX;
import '../../../shared/models/resource_detail.dart';
import '../../../shared/widgets/m3u8_status_indicator.dart';

class ResourceTabs extends StatelessWidget {
  final List<PlaySource> sources;
  final int activeSourceIndex;
  final ValueChanged<int> onSelect;
  const ResourceTabs({super.key, required this.sources, required this.activeSourceIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (sources.length <= 1) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: colors.border)),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('播放线路', style: TextStyle(color: colors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: sources.asMap().entries.map((entry) {
          final idx = entry.key;
          final source = entry.value;
          final isActive = idx == activeSourceIndex;
          final sourceUrls = source.episodes.map((e) => e.url).toList();
          return GestureDetector(
            onTap: () => onSelect(idx),
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
                Text(source.name, style: TextStyle(color: isActive ? colors.primary : colors.textMuted, fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400)),
                const SizedBox(width: 4),
                Text('(${source.episodes.length})', style: TextStyle(color: isActive ? colors.primary : colors.textMuted, fontSize: 10)),
                const SizedBox(width: 4),
                M3u8SourceStatusBadge(urls: sourceUrls, size: 12),
                if (isActive) ...[const SizedBox(width: 4), Icon(Icons.check, size: 12, color: colors.primary)],
              ]),
            ),
          );
        }).toList()),
      ]),
    );
  }
}
