import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/logger/app_logger.dart';
import '../../core/theme/app_theme.dart';
import 'qrcode_scan_provider.dart';

/// 扫码登录 TV 端 - 独立页面
class QRCodeScanScreen extends ConsumerStatefulWidget {
  const QRCodeScanScreen({super.key});

  @override
  ConsumerState<QRCodeScanScreen> createState() => _QRCodeScanScreenState();
}

class _QRCodeScanScreenState extends ConsumerState<QRCodeScanScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: [BarcodeFormat.qrCode],
  );
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    // 显式启动扫描器
    _scannerController.start();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) {
      appLogger.w('扫码检测到条码但无有效内容');
      return;
    }

    appLogger.i('扫码识别成功: ${barcode.rawValue}');
    _hasScanned = true;
    _scannerController.stop();

    ref.read(qrcodeScanProvider.notifier).confirmScan(barcode.rawValue!);
  }

  void _retry() {
    _hasScanned = false;
    ref.read(qrcodeScanProvider.notifier).reset();
    _scannerController.start();
  }

  /// 扫描器错误提示 Widget（由 MobileScanner.errorBuilder 使用）
  Widget _buildScannerErrorWidget(AppColors colors) {
    return Container(
      color: colors.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, size: 64, color: colors.error),
            const SizedBox(height: 12),
            Text(
              '相机启动失败，请检查相机权限设置',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _retry,
              icon: Icon(Icons.refresh, size: 18, color: colors.primary),
              label: Text(
                '重试',
                style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scanState = ref.watch(qrcodeScanProvider);

    ref.listen<QRCodeScanState>(qrcodeScanProvider, (prev, next) {
      if (next.status == QRCodeScanStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('TV 端登录确认成功！'),
            backgroundColor: colors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // 延迟自动返回上一页，让用户看到成功提示
        // 使用 GoRouter.of() 在回调外部获取 navigator，避免跨 async gap 使用 context
        final router = GoRouter.of(context);
        Future.delayed(const Duration(milliseconds: 1500), () {
          router.pop();
        });
      } else if (next.status == QRCodeScanStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error ?? '扫码确认失败'),
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
      body: Column(
        children: [
          // 扫码区域
          Expanded(
            flex: 3,
            child: _buildScannerArea(colors, scanState),
          ),
          // 底部状态/操作区
          Expanded(
            flex: 2,
            child: _buildStatusArea(colors, scanState),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerArea(AppColors colors, QRCodeScanState scanState) {
    final isScanning = scanState.status == QRCodeScanStatus.idle ||
        scanState.status == QRCodeScanStatus.scanning;

    if (!isScanning) {
      // 扫码已结束，显示结果图标
      return Container(
        color: colors.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                scanState.status == QRCodeScanStatus.success
                    ? Icons.check_circle_outline
                    : scanState.status == QRCodeScanStatus.confirming
                        ? Icons.hourglass_top
                        : Icons.error_outline,
                size: 64,
                color: scanState.status == QRCodeScanStatus.success
                    ? colors.primary
                    : scanState.status == QRCodeScanStatus.confirming
                        ? colors.textSecondary
                        : colors.error,
              ),
              const SizedBox(height: 12),
              Text(
                scanState.status == QRCodeScanStatus.success
                    ? '确认成功'
                    : scanState.status == QRCodeScanStatus.confirming
                        ? '正在确认...'
                        : scanState.error ?? '扫码失败',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 摄像头扫码视图
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onDetect,
          errorBuilder: (context, error) {
            appLogger.e('扫描器错误: ${error.errorCode}');
            return _buildScannerErrorWidget(colors);
          },
        ),
        // 扫描框遮罩
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.5),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Center(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 扫描框边框
        Center(
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.primary, width: 2),
            ),
          ),
        ),
        // 提示文字
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Text(
            '将二维码放入框内扫描',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              shadows: [
                Shadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 4),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusArea(AppColors colors, QRCodeScanState scanState) {
    return Container(
      color: colors.surface,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.md, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_scanner, size: 32, color: colors.primary),
          const SizedBox(height: 8),
          Text(
            '扫码登录',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '在 TV 端选择二维码登录后，使用手机扫描屏幕上的二维码即可完成登录',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
            ),
          ),
          if (scanState.status == QRCodeScanStatus.error ||
              scanState.status == QRCodeScanStatus.success) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _retry,
                icon: Icon(Icons.refresh, size: 18, color: colors.primary),
                label: Text(
                  '重新扫码',
                  style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
