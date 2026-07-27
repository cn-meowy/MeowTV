import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/ink_list_tile.dart';
import '../auth/auth_provider.dart';

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: colors.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('关于', style: TextStyle(color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              // App icon & name
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: colors.card,
                  border: Border.all(color: colors.primary.withValues(alpha: 0.3), width: 2),
                ),
                child: Center(
                  child: Icon(Icons.play_circle_fill, color: colors.primary, size: 48),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'MeowTV',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'v$_version${_buildNumber.isNotEmpty ? ' ($_buildNumber)' : ''}',
                style: TextStyle(color: colors.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 32),

              // Info cards
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
                child: Column(
                  children: [
                    _InfoTile(
                      icon: Icons.info_outline,
                      title: '版本号',
                      value: 'v$_version',
                    ),
                    _InfoTile(
                      icon: Icons.dns_outlined,
                      title: '服务器地址',
                      value: authState.baseUrl ?? '未设置',
                    ),
                    _InfoTile(
                      icon: Icons.code,
                      title: '构建号',
                      value: _buildNumber.isNotEmpty ? _buildNumber : '-',
                    ),
                    _InfoTile(
                      icon: Icons.person_outline,
                      title: '开发者',
                      value: 'MeowTV Team',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Divider(color: colors.divider, height: 1),
              const SizedBox(height: 8),

              // Actions
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
                child: Column(
                  children: [
                    InkListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.description_outlined, color: colors.textSecondary, size: 22),
                      title: Text('开源许可', style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
                      trailing: Icon(Icons.chevron_right, color: colors.textMuted, size: 20),
                      onTap: () {
                        showLicensePage(
                          context: context,
                          applicationName: 'MeowTV',
                          applicationVersion: 'v$_version',
                          applicationIcon: Icon(Icons.play_circle_fill, color: colors.primary, size: 48),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Footer
              Text(
                'Made with ❤️ by MeowTV Team',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  const _InfoTile({required this.icon, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: colors.textSecondary, size: 22),
      title: Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: Text(value, style: TextStyle(color: colors.textMuted, fontSize: 13)),
    );
  }
}

