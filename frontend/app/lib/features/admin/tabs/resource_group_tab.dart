import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/admin_config.dart';
import '../admin_provider.dart';

class ResourceGroupTab extends ConsumerStatefulWidget {
  const ResourceGroupTab({super.key});

  @override
  ConsumerState<ResourceGroupTab> createState() => _ResourceGroupTabState();
}

class _ResourceGroupTabState extends ConsumerState<ResourceGroupTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(adminProvider.notifier).fetchConfigList(group: 'resource_site'));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(adminProvider);
    final items = state.configItems;

    return RefreshIndicator(
      onRefresh: () => ref.read(adminProvider.notifier).fetchConfigList(group: 'resource_site'),
      child: state.loading && items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? _emptyState(colors)
              : ListView.builder(
                  padding: const EdgeInsets.all(AppTheme.md),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _configCard(items[i], colors),
                ),
    );
  }

  Widget _emptyState(AppColors colors) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_outlined,
              size: 48, color: colors.textMuted),
          const SizedBox(height: AppTheme.sm),
          Text('暂无资源站点', style: TextStyle(color: colors.textSecondary)),
          const SizedBox(height: AppTheme.md),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.textInverse),
            onPressed: () => _showCreateDialog(),
            child: const Text('添加站点'),
          ),
        ]),
      );

  Widget _configCard(SysConfigItem item, AppColors colors) => Container(
        margin: const EdgeInsets.only(bottom: AppTheme.sm),
        padding: const EdgeInsets.all(AppTheme.md),
        decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(item.title.isNotEmpty ? item.title : item.configKey,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            Switch(
              value: item.isEnabled,
              onChanged: (_) async {
                await ref
                    .read(adminProvider.notifier)
                    .toggleConfigEnabled(item);
              },
              activeThumbColor: colors.primary,
            ),
          ]),
          const SizedBox(height: AppTheme.xs),
          Text('域名: ${item.configKey}',
              style: TextStyle(color: colors.textSecondary, fontSize: 12)),
          if (item.value1.isNotEmpty)
            Text('API: ${item.value1}',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          if (item.value2.isNotEmpty)
            Text('详情: ${item.value2}',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          if (item.value3.isNotEmpty)
            Text('备注: ${item.value3}',
                style: TextStyle(color: colors.textMuted, fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => _showEditDialog(item),
              child: Text('编辑', style: TextStyle(color: colors.primary)),
            ),
            TextButton(
              onPressed: () => _confirmDelete(item),
              child: Text('删除', style: TextStyle(color: colors.error)),
            ),
          ]),
        ]),
      );

  void _showCreateDialog() => _showConfigDialog(null);

  void _showEditDialog(SysConfigItem item) => _showConfigDialog(item);

  void _showConfigDialog(SysConfigItem? existing) {
    final isEdit = existing != null;
    final keyCtrl = TextEditingController(text: existing?.configKey ?? '');
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final apiCtrl = TextEditingController(text: existing?.value1 ?? '');
    final detailCtrl = TextEditingController(text: existing?.value2 ?? '');
    final commentCtrl = TextEditingController(text: existing?.value3 ?? '');
    final colors = context.colors;

    showDialog(
      context: context,
      builder: (ctx) {
        final dialogColors = ctx.colors;
        return AlertDialog(
          backgroundColor: dialogColors.card,
          title: Text(isEdit ? '编辑站点' : '添加站点',
              style: TextStyle(color: dialogColors.textPrimary)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dialogField(keyCtrl, '域名（唯一标识）', dialogColors, enabled: !isEdit),
              _dialogField(titleCtrl, '名称', dialogColors),
              _dialogField(apiCtrl, 'API 地址', dialogColors, maxLines: 2),
              _dialogField(detailCtrl, '详情地址', dialogColors),
              _dialogField(commentCtrl, '备注', dialogColors),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: dialogColors.primary,
                  foregroundColor: dialogColors.textInverse),
              onPressed: () async {
                final item = SysConfigItem(
                  id: existing?.id ?? 0,
                  configKey: keyCtrl.text,
                  configGroup: 'resource_site',
                  title: titleCtrl.text,
                  title1: 'API地址', title2: '详情地址', title3: '备注',
                  value1: apiCtrl.text, value2: detailCtrl.text, value3: commentCtrl.text,
                  value4: '', value5: '', value6: '',
                  isEnabled: existing?.isEnabled ?? true,
                );
                final ok = isEdit
                    ? await ref.read(adminProvider.notifier).updateConfig(item)
                    : await ref.read(adminProvider.notifier).createConfig(item);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  _showSnack(ok ? '操作成功' : '操作失败',
                      ok ? colors.success : colors.error);
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  Widget _dialogField(TextEditingController ctrl, String label, AppColors colors,
          {int maxLines = 1, bool enabled = true}) =>
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        enabled: enabled,
        style: TextStyle(color: colors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: colors.textSecondary),
          enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colors.border)),
          focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colors.primary)),
        ),
      );

  void _confirmDelete(SysConfigItem item) {
    final colors = context.colors;
    showDialog(
        context: context,
        builder: (ctx) {
          final dialogColors = ctx.colors;
          return AlertDialog(
            backgroundColor: dialogColors.card,
            title: Text('确认删除',
                style: TextStyle(color: dialogColors.textPrimary)),
            content: Text('确定要删除 ${item.title.isNotEmpty ? item.title : item.configKey} 吗？',
                style: TextStyle(color: dialogColors.textSecondary)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: dialogColors.error,
                    foregroundColor: dialogColors.textInverse),
                onPressed: () async {
                  final ok = await ref
                      .read(adminProvider.notifier)
                      .deleteConfig(item.id, item.configGroup);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    _showSnack(ok ? '删除成功' : '删除失败',
                        ok ? colors.success : colors.error);
                  }
                },
                child: const Text('删除'),
              ),
            ],
          );
        },
      );
  }

  void _showSnack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: color));
}
