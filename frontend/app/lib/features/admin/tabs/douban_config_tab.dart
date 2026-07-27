import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/admin_subscribe.dart';
import '../../../shared/widgets/ink_list_tile.dart';
import '../admin_provider.dart';

class DoubanConfigTab extends ConsumerStatefulWidget {
  const DoubanConfigTab({super.key});

  @override
  ConsumerState<DoubanConfigTab> createState() => _DoubanConfigTabState();
}

class _DoubanConfigTabState extends ConsumerState<DoubanConfigTab> {
  /// 编辑中的配置项（key -> DoubanConfigItem）
  final Map<String, DoubanConfigItem> _edited = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(adminProvider.notifier).fetchDoubanRankConfig());
  }

  DoubanConfigItem _getOrOriginal(DoubanConfigItem original) {
    return _edited[original.configKey] ?? original;
  }

  void _update(String key, DoubanConfigItem item) {
    setState(() { _edited[key] = item; });
  }

  Future<void> _saveItem(DoubanConfigItem item) async {
    setState(() => _saving = true);
    final ok = await ref.read(adminProvider.notifier).saveDoubanConfigItem(item);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _edited.remove(item.configKey);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.title} 已保存'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    for (final item in _edited.values) {
      await ref.read(adminProvider.notifier).saveDoubanConfigItem(item);
    }
    if (!mounted) return;
    setState(() { _saving = false; _edited.clear(); });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('全部保存完成'), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(adminProvider);
    final configs = state.doubanConfigs;

    if (state.loading && configs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 操作栏
        Row(children: [
          TextButton.icon(
            onPressed: () => ref.read(adminProvider.notifier).fetchDoubanRankConfig(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('刷新'),
          ),
          const SizedBox(width: AppTheme.sm),
          ElevatedButton.icon(
            onPressed: _saving ? null : _saveAll,
            icon: const Icon(Icons.save, size: 16),
            label: const Text('全部保存'),
          ),
        ]),
        const SizedBox(height: AppTheme.md),

        // 配置分组卡片
        ...configs.map((cfg) {
          final item = _getOrOriginal(cfg);
          return _buildConfigCard(item, colors);
        }),
      ]),
    );
  }

  Widget _buildConfigCard(DoubanConfigItem item, AppColors colors) {
    final isNode = item.configKey.startsWith('douban_image_node_');
    final nodeKey = isNode ? item.configKey.replaceFirst('douban_image_node_', '') : null;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.md),
      padding: const EdgeInsets.all(AppTheme.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 标题行
        Row(children: [
          Expanded(child: Text(item.title,
              style: TextStyle(color: colors.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.bold))),
          if (nodeKey != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(nodeKey,
                  style: TextStyle(color: colors.primary, fontSize: 12)),
            ),
        ]),
        const SizedBox(height: AppTheme.sm),

        // value1
        if (item.title1.isNotEmpty) _buildField(item, 1, colors),
        // value2
        if (item.title2.isNotEmpty) _buildField(item, 2, colors),
        // value3: 分流节点用途说明（只读），其他可编辑
        if (item.title3.isNotEmpty) ...[
          if (isNode)
            _buildReadOnlyField(item.title3, item.value3, colors)
          else
            _buildField(item, 3, colors),
        ],
        // value4: 分流节点启用开关，其他可编辑
        if (item.title4.isNotEmpty) ...[
          if (isNode)
            _buildSwitchField(item, 4, colors)
          else
            _buildField(item, 4, colors),
        ],
        // value5
        if (item.title5.isNotEmpty) _buildField(item, 5, colors),

        // 保存按钮
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _saving ? null : () => _saveItem(item),
            icon: const Icon(Icons.save, size: 16),
            label: const Text('保存'),
          ),
        ),
      ]),
    );
  }

  Widget _buildField(DoubanConfigItem item, int idx, AppColors colors) {
    final title = idx == 1 ? item.title1 : idx == 2 ? item.title2 : idx == 3 ? item.title3 : idx == 4 ? item.title4 : item.title5;
    final value = idx == 1 ? item.value1 : idx == 2 ? item.value2 : idx == 3 ? item.value3 : idx == 4 ? item.value4 : item.value5;

    // 判断是否为布尔值
    if (value == 'true' || value == 'false') {
      return _buildBoolField(item, idx, colors, title, value == 'true');
    }

    // 判断是否为数字值（Cron表达式除外）
    final isNumber = int.tryParse(value) != null && !title.contains('Cron');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 140,
          child: Text(title, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        ),
        Expanded(
          child: TextFormField(
            initialValue: value,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.textSecondary.withValues(alpha: 0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.textSecondary.withValues(alpha: 0.2)),
              ),
            ),
            onChanged: (v) {
              final newItem = _updateValueAtIndex(item, idx, v);
              _update(item.configKey, newItem);
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildBoolField(DoubanConfigItem item, int idx, AppColors colors, String title, bool checked) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkSwitchListTile(
        dense: true,
        title: Text(title, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        value: checked,
        activeThumbColor: colors.primary,
        onChanged: (v) {
          final newItem = _updateValueAtIndex(item, idx, v.toString());
          _update(item.configKey, newItem);
        },
      ),
    );
  }

  Widget _buildSwitchField(DoubanConfigItem item, int idx, AppColors colors) {
    final title = idx == 4 ? item.title4 : item.title5;
    final value = idx == 4 ? item.value4 : item.value5;
    return _buildBoolField(item, idx, colors, title, value == 'true');
  }

  Widget _buildReadOnlyField(String title, String value, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 140,
          child: Text(title, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        ),
        Expanded(
          child: Text(value, style: TextStyle(color: colors.textMuted, fontSize: 14)),
        ),
      ]),
    );
  }

  DoubanConfigItem _updateValueAtIndex(DoubanConfigItem item, int idx, String value) {
    switch (idx) {
      case 1: return item.copyWith(value1: value);
      case 2: return item.copyWith(value2: value);
      case 3: return item.copyWith(value3: value);
      case 4: return item.copyWith(value4: value);
      case 5: return item.copyWith(value5: value);
      default: return item;
    }
  }
}
