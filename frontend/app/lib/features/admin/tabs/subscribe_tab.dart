import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/admin_subscribe.dart';
import '../../../shared/widgets/ink_list_tile.dart';
import '../admin_provider.dart';
import '../admin_state.dart';

class SubscribeTab extends ConsumerStatefulWidget {
  const SubscribeTab({super.key});

  @override
  ConsumerState<SubscribeTab> createState() => _SubscribeTabState();
}

class _SubscribeTabState extends ConsumerState<SubscribeTab> {
  late TextEditingController _urlCtrl;
  late TextEditingController _cronCtrl;
  bool _autoSub = false;
  bool _subEnabled = true;

  late TextEditingController _proxyHostCtrl;
  late TextEditingController _proxyPortCtrl;
  late TextEditingController _proxyUserCtrl;
  late TextEditingController _proxyPassCtrl;
  String _proxyProtocol = 'http';
  bool _proxyEnabled = false;

  bool _fetching = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();
    _cronCtrl = TextEditingController();
    _proxyHostCtrl = TextEditingController();
    _proxyPortCtrl = TextEditingController();
    _proxyUserCtrl = TextEditingController();
    _proxyPassCtrl = TextEditingController();
    // Fetch on first build
    Future.microtask(() => ref.read(adminProvider.notifier).fetchSubscribeConfig());
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _cronCtrl.dispose();
    _proxyHostCtrl.dispose();
    _proxyPortCtrl.dispose();
    _proxyUserCtrl.dispose();
    _proxyPassCtrl.dispose();
    super.dispose();
  }

  void _applyState() {
    final s = ref.read(adminProvider).subscribeConfig;
    final p = ref.read(adminProvider).proxyConfig;
    if (s != null) {
      _urlCtrl.text = s.subscribeUrl;
      _cronCtrl.text = s.cronExpr;
      _autoSub = s.autoSubscribe;
      _subEnabled = s.isEnabled;
    }
    if (p != null) {
      _proxyProtocol = p.protocol;
      _proxyHostCtrl.text = p.host;
      _proxyPortCtrl.text = p.port;
      _proxyUserCtrl.text = p.username;
      _proxyPassCtrl.text = p.passwordMasked ? '' : p.password;
      _proxyEnabled = p.enabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(adminProvider);
    // Sync controllers when data arrives
    ref.listen(adminProvider, (prev, next) {
      if (prev?.subscribeConfig != next.subscribeConfig ||
          prev?.proxyConfig != next.proxyConfig) {
        _applyState();
      }
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('订阅配置', colors),
        _buildSubscribeForm(state, colors),
        const SizedBox(height: AppTheme.lg),
        _sectionTitle('代理配置', colors),
        _buildProxyForm(state, colors),
        const SizedBox(height: AppTheme.lg),
        _sectionTitle('操作', colors),
        _buildActions(state, colors),
      ]),
    );
  }

  Widget _sectionTitle(String text, AppColors colors) => Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.sm),
        child: Text(text,
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
      );

  Widget _buildSubscribeForm(AdminState state, AppColors colors) => Container(
        padding: const EdgeInsets.all(AppTheme.md),
        decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
        child: Column(children: [
          _textField(_urlCtrl, '订阅地址', colors, maxLines: 2),
          const SizedBox(height: AppTheme.sm),
          _textField(_cronCtrl, 'Cron 表达式', colors),
          const SizedBox(height: AppTheme.sm),
          _switchTile('自动订阅', _autoSub, (v) => setState(() => _autoSub = v), colors),
          _switchTile('启用', _subEnabled, (v) => setState(() => _subEnabled = v), colors),
          const SizedBox(height: AppTheme.sm),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.textInverse),
              onPressed: () async {
                final ok = await ref.read(adminProvider.notifier).saveSubscribeConfig(
                    SubscribeConfig(
                        subscribeUrl: _urlCtrl.text,
                        autoSubscribe: _autoSub,
                        cronExpr: _cronCtrl.text,
                        isEnabled: _subEnabled));
                if (mounted) {
                  _showSnack(ok ? '保存成功' : '保存失败',
                      ok ? colors.success : colors.error);
                }
              },
              child: const Text('保存订阅配置'),
            ),
          ),
        ]),
      );

  Widget _buildProxyForm(AdminState state, AppColors colors) => Container(
        padding: const EdgeInsets.all(AppTheme.md),
        decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
        child: Column(children: [
          DropdownButtonFormField<String>(
            initialValue: _proxyProtocol,
            decoration: InputDecoration(
                labelText: '协议',
                labelStyle: TextStyle(color: colors.textSecondary),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: colors.border))),
            dropdownColor: colors.card,
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
            items: ['http', 'socks5']
                .map((v) => DropdownMenuItem(value: v, child: Text(v, style: TextStyle(color: colors.textPrimary))))
                .toList(),
            onChanged: (v) => setState(() => _proxyProtocol = v ?? 'http'),
          ),
          const SizedBox(height: AppTheme.sm),
          Row(children: [
            Expanded(flex: 3, child: _textField(_proxyHostCtrl, '主机', colors)),
            const SizedBox(width: AppTheme.sm),
            Expanded(flex: 1, child: _textField(_proxyPortCtrl, '端口', colors)),
          ]),
          const SizedBox(height: AppTheme.sm),
          _textField(_proxyUserCtrl, '用户名', colors),
          const SizedBox(height: AppTheme.sm),
          _textField(_proxyPassCtrl, '密码', colors, obscure: true),
          const SizedBox(height: AppTheme.sm),
          _switchTile('启用代理', _proxyEnabled, (v) => setState(() => _proxyEnabled = v), colors),
          const SizedBox(height: AppTheme.sm),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.textInverse),
              onPressed: () async {
                final ok = await ref.read(adminProvider.notifier).saveProxyConfig(
                    ProxyConfig(
                        protocol: _proxyProtocol,
                        host: _proxyHostCtrl.text,
                        port: _proxyPortCtrl.text,
                        username: _proxyUserCtrl.text,
                        password: _proxyPassCtrl.text,
                        enabled: _proxyEnabled));
                if (mounted) {
                  _showSnack(ok ? '保存成功' : '保存失败',
                      ok ? colors.success : colors.error);
                }
              },
              child: const Text('保存代理配置'),
            ),
          ),
        ]),
      );

  Widget _buildActions(AdminState state, AppColors colors) => Container(
        padding: const EdgeInsets.all(AppTheme.md),
        decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
        child: Column(children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: colors.warning,
                  foregroundColor: colors.textInverse),
              onPressed: _fetching
                  ? null
                  : () async {
                      setState(() => _fetching = true);
                      final resp = await ref
                          .read(adminProvider.notifier)
                          .fetchSubscribe();
                      setState(() => _fetching = false);
                      if (mounted && resp != null) {
                        _showSnack(
                            '拉取完成: 总${resp.total} 新增${resp.added} 更新${resp.updated}',
                            colors.success);
                      } else if (mounted) {
                        _showSnack('拉取失败', colors.error);
                      }
                    },
              child: _fetching
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('手动拉取订阅'),
            ),
          ),
          const SizedBox(height: AppTheme.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  side: BorderSide(color: colors.primary)),
              onPressed: _testing
                  ? null
                  : () async {
                      setState(() => _testing = true);
                      final result =
                          await ref.read(adminProvider.notifier).testProxy();
                      setState(() => _testing = false);
                      if (mounted) {
                        _showSnack(result ?? '代理测试失败',
                            result != null ? colors.success : colors.error);
                      }
                    },
              child: _testing
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('测试代理连通性'),
            ),
          ),
        ]),
      );

  Widget _textField(TextEditingController ctrl, String label, AppColors colors,
          {int maxLines = 1, bool obscure = false}) =>
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        obscureText: obscure,
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

  Widget _switchTile(String title, bool value, ValueChanged<bool> onChanged, AppColors colors) =>
      InkSwitchListTile(
        title: Text(title, style: TextStyle(color: colors.textPrimary)),
        value: value,
        onChanged: onChanged,
        activeThumbColor: colors.primary,
      );

  void _showSnack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: color));
}
