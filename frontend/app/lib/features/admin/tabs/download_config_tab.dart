import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/admin_download.dart';
import '../admin_provider.dart';

class DownloadConfigTab extends ConsumerStatefulWidget {
  const DownloadConfigTab({super.key});

  @override
  ConsumerState<DownloadConfigTab> createState() =>
      _DownloadConfigTabState();
}

class _DownloadConfigTabState extends ConsumerState<DownloadConfigTab> {
  late TextEditingController _dirCtrl;
  late TextEditingController _maxCtrl;
  late TextEditingController _segCtrl;

  @override
  void initState() {
    super.initState();
    _dirCtrl = TextEditingController();
    _maxCtrl = TextEditingController();
    _segCtrl = TextEditingController();
    Future.microtask(
        () => ref.read(adminProvider.notifier).fetchDownloadConfig());
  }

  @override
  void dispose() {
    _dirCtrl.dispose();
    _maxCtrl.dispose();
    _segCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(adminProvider);

    ref.listen(adminProvider, (prev, next) {
      if (prev?.downloadConfig != next.downloadConfig &&
          next.downloadConfig != null) {
        final c = next.downloadConfig!;
        _dirCtrl.text = c.downloadDir;
        _maxCtrl.text = c.maxConcurrent.toString();
        _segCtrl.text = c.segmentConcurrency.toString();
      }
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.md),
      child: state.loading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              padding: const EdgeInsets.all(AppTheme.md),
              decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusCard)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('下载配置',
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppTheme.md),
                    _textField(_dirCtrl, '下载目录', colors),
                    const SizedBox(height: AppTheme.sm),
                    _textField(_maxCtrl, '最大并发数', colors,
                        keyboardType: TextInputType.number),
                    const SizedBox(height: AppTheme.sm),
                    _textField(_segCtrl, '分片并发数', colors,
                        keyboardType: TextInputType.number),
                    const SizedBox(height: AppTheme.lg),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: colors.textInverse),
                        onPressed: () async {
                          final config = DownloadConfig(
                            downloadDir: _dirCtrl.text,
                            maxConcurrent:
                                int.tryParse(_maxCtrl.text) ?? 2,
                            segmentConcurrency:
                                int.tryParse(_segCtrl.text) ?? 10,
                          );
                          final ok = await ref
                              .read(adminProvider.notifier)
                              .saveDownloadConfig(config);
                          if (mounted) {
                            _showSnack(
                                ok ? '保存成功' : '保存失败',
                                ok
                                    ? colors.success
                                    : colors.error);
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
