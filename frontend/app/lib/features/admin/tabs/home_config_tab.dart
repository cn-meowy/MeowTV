import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/admin_home.dart';
import '../admin_provider.dart';

/// 首页区块标题配置 Tab
///
/// 编辑 sys_config 中 config_key = "home_section_titles" 的配置项，
/// 对应首页"热门推荐"/"热播剧集"两个区块的标题（默认"最近添加"/"可能喜欢"）。
class HomeConfigTab extends ConsumerStatefulWidget {
  const HomeConfigTab({super.key});

  @override
  ConsumerState<HomeConfigTab> createState() => _HomeConfigTabState();
}

class _HomeConfigTabState extends ConsumerState<HomeConfigTab> {
  late TextEditingController _title1Ctrl;
  late TextEditingController _title2Ctrl;

  @override
  void initState() {
    super.initState();
    _title1Ctrl = TextEditingController();
    _title2Ctrl = TextEditingController();
    Future.microtask(() => ref.read(adminProvider.notifier).fetchHomeConfig());
  }

  @override
  void dispose() {
    _title1Ctrl.dispose();
    _title2Ctrl.dispose();
    super.dispose();
  }

  void _applyConfig(HomeSectionConfig c) {
    _title1Ctrl.text = c.sectionTitle1;
    _title2Ctrl.text = c.sectionTitle2;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(adminProvider);

    ref.listen(adminProvider, (prev, next) {
      if (prev?.homeConfig != next.homeConfig && next.homeConfig != null) {
        _applyConfig(next.homeConfig!);
      }
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.md),
      child: state.loading && state.homeConfig == null
          ? const Center(child: CircularProgressIndicator())
          : Container(
              padding: const EdgeInsets.all(AppTheme.md),
              decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('首页区块标题配置',
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppTheme.sm),
                    // 说明
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppTheme.sm),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      ),
                      child: Text(
                        '配置首页两个内容区块的标题文字。区块一对应电影列表，区块二对应剧集列表。留空将使用默认值。',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: AppTheme.md),
                    // 区块一标题
                    _textField(_title1Ctrl, '区块一标题', colors),
                    const SizedBox(height: AppTheme.sm),
                    // 区块二标题
                    _textField(_title2Ctrl, '区块二标题', colors),
                    const SizedBox(height: AppTheme.lg),
                    // 保存按钮
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: colors.textInverse),
                        onPressed: () async {
                          final config = HomeSectionConfig(
                            sectionTitle1: _title1Ctrl.text.trim().isEmpty
                                ? '最近添加'
                                : _title1Ctrl.text.trim(),
                            sectionTitle2: _title2Ctrl.text.trim().isEmpty
                                ? '可能喜欢'
                                : _title2Ctrl.text.trim(),
                          );
                          final ok = await ref
                              .read(adminProvider.notifier)
                              .saveHomeConfig(config);
                          if (mounted) {
                            _showSnack(
                                ok ? '保存成功' : '保存失败',
                                ok ? colors.success : colors.error);
                          }
                        },
                        child: const Text('保存'),
                      ),
                    ),
                  ]),
            ),
    );
  }

  Widget _textField(TextEditingController ctrl, String label, AppColors colors,
          {TextInputType? keyboardType}) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboardType,
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

  void _showSnack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: color));
}
