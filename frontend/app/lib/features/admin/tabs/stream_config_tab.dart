import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/admin_stream.dart';
import '../admin_provider.dart';

class StreamConfigTab extends ConsumerStatefulWidget {
  const StreamConfigTab({super.key});

  @override
  ConsumerState<StreamConfigTab> createState() => _StreamConfigTabState();
}

class _StreamConfigTabState extends ConsumerState<StreamConfigTab> {
  late TextEditingController _bufferSizeCtrl;
  late TextEditingController _generalWorkersCtrl;
  late TextEditingController _maxWorkersCtrl;
  late TextEditingController _maxDiskCacheCtrl;
  bool _enabled = false;
  bool _autoSave = false;

  @override
  void initState() {
    super.initState();
    _bufferSizeCtrl = TextEditingController();
    _generalWorkersCtrl = TextEditingController();
    _maxWorkersCtrl = TextEditingController();
    _maxDiskCacheCtrl = TextEditingController();
    Future.microtask(
        () => ref.read(adminProvider.notifier).fetchStreamConfig());
  }

  @override
  void dispose() {
    _bufferSizeCtrl.dispose();
    _generalWorkersCtrl.dispose();
    _maxWorkersCtrl.dispose();
    _maxDiskCacheCtrl.dispose();
    super.dispose();
  }

  void _applyConfig(StreamConfig c) {
    _enabled = c.enabled;
    _autoSave = c.autoSave;
    _bufferSizeCtrl.text = c.bufferSize.toString();
    _generalWorkersCtrl.text = c.generalWorkers.toString();
    _maxWorkersCtrl.text = c.maxWorkers.toString();
    _maxDiskCacheCtrl.text = c.maxDiskCacheMB.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(adminProvider);

    ref.listen(adminProvider, (prev, next) {
      if (prev?.streamConfig != next.streamConfig &&
          next.streamConfig != null) {
        _applyConfig(next.streamConfig!);
      }
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.md),
      child: state.loading && state.streamConfig == null
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
                    Text('流代理配置',
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
                        borderRadius:
                              BorderRadius.circular(AppTheme.radiusCard),
                      ),
                      child: Text(
                        '启用后，播放 m3u8 视频时将通过后端流代理服务器进行转发，支持并行下载和缓冲控制。',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: AppTheme.md),
                    // 启用远程代理
                    _switchRow('启用远程代理', _enabled, (v) {
                      setState(() => _enabled = v);
                    }, colors),
                    const Divider(),
                    // 前瞻窗口大小
                    _textField(_bufferSizeCtrl, '前瞻窗口大小', colors,
                        keyboardType: TextInputType.number),
                    const SizedBox(height: AppTheme.sm),
                    // 通用协程数
                    _textField(_generalWorkersCtrl, '通用协程数', colors,
                        keyboardType: TextInputType.number),
                    const SizedBox(height: AppTheme.sm),
                    // 总协程上限
                    _textField(_maxWorkersCtrl, '总协程上限', colors,
                        keyboardType: TextInputType.number),
                    const SizedBox(height: AppTheme.sm),
                    // 自动保存进度
                    _switchRow('自动保存进度', _autoSave, (v) {
                      setState(() => _autoSave = v);
                    }, colors),
                    const SizedBox(height: AppTheme.sm),
                    // 磁盘缓存上限
                    _textField(_maxDiskCacheCtrl, '磁盘缓存上限(MB)', colors,
                        keyboardType: TextInputType.number),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '0 表示不限制，默认 10240（10GB）',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: AppTheme.lg),
                    // 保存按钮
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: colors.textInverse),
                        onPressed: () async {
                          final config = StreamConfig(
                            enabled: _enabled,
                            bufferSize:
                                int.tryParse(_bufferSizeCtrl.text) ?? 20,
                            generalWorkers:
                                int.tryParse(_generalWorkersCtrl.text) ??
                                    5,
                            maxWorkers:
                                int.tryParse(_maxWorkersCtrl.text) ?? 8,
                            autoSave: _autoSave,
                            maxDiskCacheMB:
                                int.tryParse(_maxDiskCacheCtrl.text) ??
                                    10240,
                          );
                          final ok = await ref
                              .read(adminProvider.notifier)
                              .saveStreamConfig(config);
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

  Widget _switchRow(
      String label, bool value, ValueChanged<bool> onChanged, AppColors colors) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(color: colors.textPrimary, fontSize: 14)),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: colors.primary,
        ),
      ],
    );
  }

  void _showSnack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: color));
}
