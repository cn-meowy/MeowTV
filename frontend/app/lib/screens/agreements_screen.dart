import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/auth_provider.dart';

class AgreementsScreen extends ConsumerWidget {
  const AgreementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(color: colors.background),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '用户协议与隐私政策',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Divider(color: colors.divider, height: 1),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '欢迎使用 PurrTV！在使用本应用前，请您仔细阅读并同意以下协议。'
                        '点击"同意并继续"即表示您已阅读并同意以下协议的全部内容。',
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textSecondary,
                          height: 1.8,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _AgreementCard(
                        icon: Icons.description_outlined,
                        title: '用户协议',
                        subtitle: '查看用户协议全文',
                        onTap: () => context.push('/user-agreement'),
                      ),
                      const SizedBox(height: 12),
                      _AgreementCard(
                        icon: Icons.privacy_tip_outlined,
                        title: '隐私政策',
                        subtitle: '查看隐私政策全文',
                        onTap: () => context.push('/privacy-policy'),
                      ),
                    ],
                  ),
                ),
              ),
              // Bottom button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () =>
                        ref.read(authProvider.notifier).setAgreementsAccepted(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                      ),
                    ),
                    child: Text(
                      '同意并继续',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textInverse,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgreementCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AgreementCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: colors.primary, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
