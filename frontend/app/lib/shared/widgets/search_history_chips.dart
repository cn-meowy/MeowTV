import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 搜索历史平铺展示组件。
///
/// 以 Wrap + ActionChip 方式平铺展示搜索历史关键词，
/// 默认只显示前 [maxDisplay] 条（默认 10 条）。
///
/// - 点击某条历史触发 [onTap] 回调
/// - 点击"清空"按钮触发 [onClear] 回调
class SearchHistoryChips extends StatelessWidget {
  final List<String> history;
  final ValueChanged<String> onTap;
  final VoidCallback onClear;
  final int maxDisplay;

  const SearchHistoryChips({
    super.key,
    required this.history,
    required this.onTap,
    required this.onClear,
    this.maxDisplay = 10,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayItems = history.take(maxDisplay).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '历史搜索',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              TextButton(
                onPressed: onClear,
                child: Text(
                  '清空',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: displayItems.map((t) => ActionChip(
              label: Text(t, style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
              )),
              avatar: Icon(Icons.history, size: 14, color: colors.textMuted),
              backgroundColor: colors.card,
              side: BorderSide(color: colors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onPressed: () => onTap(t),
            )).toList(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
