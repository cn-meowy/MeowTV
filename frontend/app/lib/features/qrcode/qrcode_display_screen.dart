import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import 'qrcode_display_provider.dart';

/// Apple TV 端二维码登录页面 — 显示登录码等待手机扫码确认
class QRCodeDisplayScreen extends ConsumerStatefulWidget {
  const QRCodeDisplayScreen({super.key});

  @override
  ConsumerState<QRCodeDisplayScreen> createState() => _QRCodeDisplayScreenState();
}

class _QRCodeDisplayScreenState extends ConsumerState<QRCodeDisplayScreen> {
  @override
  void initState() {
    super.initState();
    // 页面加载后自动请求登录码
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(qrcodeDisplayProvider.notifier).requestCode();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayState = ref.watch(qrcodeDisplayProvider);

    ref.listen<QRCodeDisplayState>(qrcodeDisplayProvider, (prev, next) {
      if (next.status == QRCodeDisplayStatus.confirmed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('登录成功！'),
            backgroundColor: colors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // GoRouter 的 refreshListenable 会自动跳转到 /home
      } else if (next.status == QRCodeDisplayStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error ?? '请求登录码失败'),
            backgroundColor: colors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          '扫码登录',
          style: TextStyle(color: colors.textPrimary, fontSize: 18),
        ),
      ),
      body: Center(
        child: _buildContent(colors, displayState),
      ),
    );
  }

  Widget _buildContent(AppColors colors, QRCodeDisplayState displayState) {
    switch (displayState.status) {
      case QRCodeDisplayStatus.idle:
      case QRCodeDisplayStatus.loading:
        return _buildLoading(colors);

      case QRCodeDisplayStatus.displaying:
        return _buildCodeDisplay(colors, displayState);

      case QRCodeDisplayStatus.confirmed:
        return _buildConfirmed(colors);

      case QRCodeDisplayStatus.expired:
        return _buildExpired(colors);

      case QRCodeDisplayStatus.error:
        return _buildError(colors, displayState.error ?? '未知错误');
    }
  }

  Widget _buildLoading(AppColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: colors.primary),
        const SizedBox(height: 16),
        Text(
          '正在获取登录码...',
          style: TextStyle(color: colors.textSecondary, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildCodeDisplay(AppColors colors, QRCodeDisplayState displayState) {
    final code = displayState.code ?? '';
    final qrUrl = displayState.qrUrl ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 登录码大字显示
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: colors.primary.withValues(alpha: 0.4), width: 2),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.15),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                '登录码',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _formatCode(code),
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                ),
              ),
              if (qrUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  qrUrl,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '请使用手机端 PurrTV 扫码\n或在手机端输入登录码',
          style: TextStyle(color: colors.textSecondary, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        // 等待提示
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '等待扫码确认...',
              style: TextStyle(color: colors.textMuted, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }

  /// 将登录码格式化为易读形式，如 "ABCD EFGH"
  String _formatCode(String code) {
    if (code.length == 8) {
      return '${code.substring(0, 4)} ${code.substring(4)}';
    }
    return code;
  }

  Widget _buildConfirmed(AppColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline, size: 64, color: colors.primary),
        const SizedBox(height: 16),
        Text(
          '登录成功！',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildExpired(AppColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_off, size: 64, color: colors.textSecondary),
        const SizedBox(height: 16),
        Text(
          '登录码已过期',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '请点击下方按钮重新获取',
          style: TextStyle(color: colors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => ref.read(qrcodeDisplayProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh),
          label: const Text('重新获取'),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusButton),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError(AppColors colors, String error) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 64, color: colors.error),
        const SizedBox(height: 16),
        Text(
          error,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => ref.read(qrcodeDisplayProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusButton),
            ),
          ),
        ),
      ],
    );
  }
}
