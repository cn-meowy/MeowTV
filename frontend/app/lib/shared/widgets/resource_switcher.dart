import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/search_result.dart';

/// Resource switcher — displays a list of same-group resources as selectable
/// buttons. Mirrors Web ResourceSwitcher.tsx behavior.
///
/// When [items] has ≤ 1 entry the widget returns [SizedBox.shrink].
class ResourceSwitcher extends StatelessWidget {
  final List<SearchResultItem> items;
  final String activeDomain;
  final ValueChanged<SearchResultItem> onChange;

  const ResourceSwitcher({
    super.key,
    required this.items,
    required this.activeDomain,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    if (items.length <= 1) return const SizedBox.shrink();

    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppTheme.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Text(
            '同组资源',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.sm),
          // Resource buttons
          Wrap(
            spacing: AppTheme.sm,
            runSpacing: AppTheme.sm,
            children: items.map((item) {
              final isActive = item.resourceDomain == activeDomain;
              return GestureDetector(
                onTap: () => onChange(item),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive ? colors.primary.withValues(alpha: 0.15) : colors.elevated,
                    borderRadius: BorderRadius.circular(AppTheme.radiusTag),
                    border: Border.all(
                      color: isActive
                          ? colors.primary.withValues(alpha: 0.4)
                          : colors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.public,
                        size: 12,
                        color: isActive ? colors.primary : colors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.resourceName,
                        style: TextStyle(
                          color: isActive ? colors.primary : colors.textSecondary,
                          fontSize: 12,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.check, size: 12, color: colors.primary),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
