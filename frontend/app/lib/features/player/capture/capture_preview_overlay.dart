import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'media_capture_manager.dart';
import 'capture_provider.dart';

/// 截图/录制/GIF 预览浮层
class CapturePreviewOverlay extends ConsumerWidget {
  final VoidCallback? onGenerateGif;

  const CapturePreviewOverlay({super.key, this.onGenerateGif});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(captureManagerProvider);

    // 截图预览
    if (manager.lastScreenshot != null) {
      return _ScreenshotPreview(
        imageData: manager.lastScreenshot!.imageData,
        onSave: () => manager.saveScreenshotToGallery(),
        onShare: () => manager.shareScreenshot(),
        onDismiss: () => manager.dismissScreenshot(),
      );
    }

    // GIF 预览
    if (manager.lastGifPath != null) {
      return _GifPreview(
        gifPath: manager.lastGifPath!,
        onSave: () => manager.saveGifToGallery(manager.lastGifPath!),
        onShare: () => manager.shareGif(manager.lastGifPath!),
        onDismiss: () => manager.dismissGif(),
      );
    }

    // 录制预览
    if (manager.lastRecording != null) {
      return _RecordingPreview(
        result: manager.lastRecording!,
        onSave: () => manager.saveRecordingToGallery(),
        onShare: () => manager.shareRecording(),
        onGenerateGif: () => onGenerateGif?.call(),
        onDismiss: () => manager.dismissRecording(),
      );
    }

    return const SizedBox.shrink();
  }
}

class _ScreenshotPreview extends StatelessWidget {
  final Uint8List imageData;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onDismiss;

  const _ScreenshotPreview({
    required this.imageData,
    required this.onSave,
    required this.onShare,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Image.memory(imageData, height: 200, fit: BoxFit.contain),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _ActionButton(icon: Icons.save, label: '保存', onTap: onSave),
              const SizedBox(width: 16),
              _ActionButton(icon: Icons.share, label: '分享', onTap: onShare),
              const SizedBox(width: 16),
              _ActionButton(icon: Icons.close, label: '取消', onTap: onDismiss),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _GifPreview extends StatelessWidget {
  final String gifPath;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onDismiss;

  const _GifPreview({
    required this.gifPath,
    required this.onSave,
    required this.onShare,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.gif, color: Colors.white, size: 48),
          const SizedBox(height: 8),
          const Text('GIF 生成完成',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _ActionButton(icon: Icons.save, label: '保存', onTap: onSave),
            const SizedBox(width: 12),
            _ActionButton(icon: Icons.share, label: '分享', onTap: onShare),
            const SizedBox(width: 12),
            _ActionButton(icon: Icons.close, label: '取消', onTap: onDismiss),
          ]),
        ]),
      ),
    );
  }
}

class _RecordingPreview extends StatelessWidget {
  final RecordResult result;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onGenerateGif;
  final VoidCallback onDismiss;

  const _RecordingPreview({
    required this.result,
    required this.onSave,
    required this.onShare,
    required this.onGenerateGif,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final seconds = result.duration.inSeconds;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.videocam, color: Colors.white, size: 48),
          const SizedBox(height: 8),
          Text('录制完成  ${seconds}s',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _ActionButton(icon: Icons.save, label: '保存', onTap: onSave),
            const SizedBox(width: 12),
            _ActionButton(icon: Icons.share, label: '分享', onTap: onShare),
            const SizedBox(width: 12),
            _ActionButton(icon: Icons.gif, label: 'GIF', onTap: onGenerateGif),
            const SizedBox(width: 12),
            _ActionButton(icon: Icons.close, label: '取消', onTap: onDismiss),
          ]),
        ]),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ]),
    );
  }
}
