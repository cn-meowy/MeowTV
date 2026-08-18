import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/resource_site.dart';
import '../../shared/widgets/equal_width_site_wrap.dart';
import '../../features/search/search_provider.dart';

/// Dropdown-style resource site selector with select-all and adult filter controls.
///
/// When [compact] is true, only renders the trigger button (for embedding in
/// the search bar). The expanded panel is rendered separately via
/// [ResourceDropdownPanel] placed below the search bar.
class ResourceDropdownWidget extends ConsumerWidget {
  final bool compact;

  const ResourceDropdownWidget({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchProvider);
    final sites = state.sites;
    final selected = state.selectedResources;
    final colors = context.colors;

    // Label for the collapsed button
    String label;
    if (selected.isEmpty) {
      label = '未选择';
    } else if (selected.length == sites.length) {
      label = '全部资源';
    } else {
      label = '${selected.length}个资源';
    }

    if (compact) {
      // Compact mode: just the trigger button inside the search bar
      return GestureDetector(
        onTap: () => ref.read(searchProvider.notifier).toggleExpanded(),
        child: Container(
          height: AppTheme.inputHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colors.elevated,
            borderRadius: BorderRadius.circular(AppTheme.radiusTag),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.layers, size: 14, color: colors.textSecondary),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              )),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: state.isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.expand_more, size: 14, color: colors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    // Non-compact: full widget with inline panel (used elsewhere if needed)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => ref.read(searchProvider.notifier).toggleExpanded(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(AppTheme.radiusTag),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.layers, size: 16, color: colors.textSecondary),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                )),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: state.isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, size: 18, color: colors.textMuted),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: state.isExpanded
              ? ResourceDropdownPanel()
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Expanded panel with control chips and site pills in a Wrap layout.
/// Designed to be placed below the search bar as a full-width area.
class ResourceDropdownPanel extends ConsumerWidget {
  const ResourceDropdownPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchProvider);
    final sites = state.sites;
    final selected = state.selectedResources;
    final colors = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Control row: Select All + Adult toggle ──
          Row(
            children: [
              _ControlChip(
                label: '全选',
                selected: state.isAllSelected,
                selectedColor: colors.primary,
                onTap: () => ref.read(searchProvider.notifier).toggleAllResources(),
              ),
              if (state.hasAdultSites) ...[
                const SizedBox(width: 10),
                _ControlChip(
                  label: '18禁',
                  selected: state.isAdultAllSelected,
                  selectedColor: colors.error,
                  onTap: () => ref.read(searchProvider.notifier).toggleAdultResources(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: 10),
          // ── Site pills (equal-width Wrap for multi-line flat layout) ──
          // The panel applies 12px padding on all sides, so horizontalPadding
          // must match to compute the correct available width.
          EqualWidthSiteWrap(
            itemCount: sites.length,
            horizontalPadding: 12,
            children: [
              for (final s in sites)
                _SitePill(
                  site: s,
                  isSelected: selected.contains(s.domain),
                  onTap: () => ref.read(searchProvider.notifier).toggleResource(s.domain),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A control chip for "Select All" or "Adult" toggle.
class _ControlChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _ControlChip({
    required this.label,
    required this.selected,
    required this.selectedColor,
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
          color: selected ? selectedColor.withValues(alpha: 0.15) : colors.elevated,
          borderRadius: BorderRadius.circular(AppTheme.radiusTag),
          border: Border.all(color: selected ? selectedColor.withValues(alpha: 0.4) : colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16,
              color: selected ? selectedColor : colors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? selectedColor : colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single resource site pill.
class _SitePill extends StatelessWidget {
  final ResourceSiteItem site;
  final bool isSelected;
  final VoidCallback onTap;

  const _SitePill({
    required this.site,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAdult = site.isAdult;
    final colors = context.colors;
    final activeColor = isAdult ? colors.error : colors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.15) : colors.elevated,
          borderRadius: BorderRadius.circular(AppTheme.radiusTag),
          border: Border.all(color: isSelected ? activeColor.withValues(alpha: 0.4) : colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14,
              color: isSelected ? activeColor : colors.textMuted,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                site.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? activeColor : colors.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
