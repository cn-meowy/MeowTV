import 'package:dart_cast/dart_cast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../cast/cast_provider.dart';
import '../../cast/cast_service.dart';
import 'styles.dart';

/// 投屏设备选择面板
class CastPanel extends ConsumerStatefulWidget {
  final VoidCallback onDismiss;

  /// 用户选择设备后的回调，由 PlayerScreen 处理投屏启动逻辑
  final void Function(CastDevice device) onDeviceSelected;

  /// 用户主动断开投屏的回调
  final VoidCallback? onDisconnect;

  final double scale;
  final double maxHeight;
  final double playerWidth;

  const CastPanel({
    super.key,
    required this.onDismiss,
    required this.onDeviceSelected,
    this.onDisconnect,
    required this.scale,
    required this.maxHeight,
    required this.playerWidth,
  });

  @override
  ConsumerState<CastPanel> createState() => _CastPanelState();
}

class _CastPanelState extends ConsumerState<CastPanel> {
  MeowCastService? _cachedService;

  @override
  void initState() {
    super.initState();
    // 打开面板时自动开始发现设备
    Future.microtask(() {
      if (mounted) {
        _cachedService = ref.read(castServiceProvider);
        _cachedService?.startDiscovery();
      }
    });
  }

  @override
  void dispose() {
    // 使用缓存引用，避免在 dispose 后调用 ref（会抛出 StateError）
    _cachedService?.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final castState = ref.watch(castStateProvider);
    final devicesAsync = ref.watch(castDevicesProvider);
    final service = ref.read(castServiceProvider);
    final currentState = castState.valueOrNull ?? CastState.disconnected;
    final scale = widget.scale;

    return Container(
      width: PlayerControlsStyles.scaledWidth(280, widget.playerWidth),
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      decoration: BoxDecoration(
        color: PlayerControlsStyles.panelBg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(PlayerControlsStyles.scaledPadding(9, scale)),
          bottomLeft: Radius.circular(PlayerControlsStyles.scaledPadding(9, scale)),
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 标题栏
        Padding(
          padding: EdgeInsets.fromLTRB(
            PlayerControlsStyles.scaledPadding(9, scale),
            PlayerControlsStyles.scaledPadding(9, scale),
            PlayerControlsStyles.scaledPadding(7, scale),
            PlayerControlsStyles.scaledPadding(7, scale),
          ),
          child: Row(children: [
            Text('投屏设备', style: TextStyle(
              color: PlayerControlsStyles.textColor,
              fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
              fontWeight: FontWeight.w600,
            )),
            const Spacer(),
            if (currentState == CastState.discovering)
              const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: PlayerControlsStyles.speedActive,
                ),
              ),
            IconButton(
              icon: Icon(Icons.close, color: PlayerControlsStyles.iconColor, size: PlayerControlsStyles.scaledFontSize(10, scale)),
              onPressed: widget.onDismiss,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(minWidth: PlayerControlsStyles.scaledPadding(28, scale), minHeight: PlayerControlsStyles.scaledPadding(28, scale)),
            ),
          ]),
        ),
        const Divider(color: Colors.white12, height: 1),

        // 已连接设备
        if (service.connectedDevice != null)
          _ConnectedDeviceItem(
            device: service.connectedDevice!,
            state: currentState,
            onDisconnect: () {
              widget.onDisconnect?.call();
              service.disconnect();
            },
            scale: scale,
          ),

        // 设备列表
        Flexible(
          child: devicesAsync.when(
            data: (devices) {
              // 过滤掉已连接的设备
              final list = devices.where((d) => d.id != service.connectedDevice?.id).toList();
              if (list.isEmpty && currentState == CastState.discovering) {
                return Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: PlayerControlsStyles.scaledPadding(28, scale),
                    horizontal: PlayerControlsStyles.scaledPadding(9, scale),
                  ),
                  child: Center(child: Text(
                    '正在搜索设备...',
                    style: TextStyle(color: PlayerControlsStyles.textSecondary, fontSize: PlayerControlsStyles.scaledFontSize(10, scale)),
                  )),
                );
              }
              if (list.isEmpty) {
                return Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: PlayerControlsStyles.scaledPadding(28, scale),
                    horizontal: PlayerControlsStyles.scaledPadding(9, scale),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      '未发现设备',
                      style: TextStyle(color: PlayerControlsStyles.textSecondary, fontSize: PlayerControlsStyles.scaledFontSize(10, scale)),
                    ),
                    SizedBox(height: PlayerControlsStyles.scaledPadding(9, scale)),
                    GestureDetector(
                      onTap: () => service.startDiscovery(),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: PlayerControlsStyles.scaledPadding(9, scale),
                          vertical: PlayerControlsStyles.scaledPadding(7, scale),
                        ),
                        decoration: BoxDecoration(
                          color: PlayerControlsStyles.speedActive,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('重新搜索', style: TextStyle(color: Colors.white, fontSize: PlayerControlsStyles.scaledFontSize(10, scale))),
                      ),
                    ),
                  ]),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(vertical: PlayerControlsStyles.scaledPadding(4, scale)),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(color: Colors.white12, height: 1),
                itemBuilder: (_, index) => _DeviceItem(
                  device: list[index],
                  onTap: () => _onDeviceTap(list[index]),
                  scale: scale,
                ),
              );
            },
            loading: () => Padding(
              padding: EdgeInsets.symmetric(vertical: PlayerControlsStyles.scaledPadding(28, scale)),
              child: Center(child: Text(
                '正在搜索设备...',
                style: TextStyle(color: PlayerControlsStyles.textSecondary, fontSize: PlayerControlsStyles.scaledFontSize(10, scale)),
              )),
            ),
            error: (e, _) => Padding(
              padding: EdgeInsets.symmetric(
                vertical: PlayerControlsStyles.scaledPadding(28, scale),
                horizontal: PlayerControlsStyles.scaledPadding(9, scale),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('搜索失败: $e', style: TextStyle(color: PlayerControlsStyles.speedInactive, fontSize: PlayerControlsStyles.scaledFontSize(10, scale))),
                SizedBox(height: PlayerControlsStyles.scaledPadding(9, scale)),
                GestureDetector(
                  onTap: () => service.startDiscovery(),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: PlayerControlsStyles.scaledPadding(9, scale),
                      vertical: PlayerControlsStyles.scaledPadding(7, scale),
                    ),
                    decoration: BoxDecoration(
                      color: PlayerControlsStyles.speedActive,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('重试', style: TextStyle(color: Colors.white, fontSize: PlayerControlsStyles.scaledFontSize(10, scale))),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  void _onDeviceTap(CastDevice device) {
    widget.onDeviceSelected(device);
    widget.onDismiss();
  }
}

class _ConnectedDeviceItem extends StatelessWidget {
  final CastDevice device;
  final CastState state;
  final VoidCallback onDisconnect;
  final double scale;

  const _ConnectedDeviceItem({
    required this.device,
    required this.state,
    required this.onDisconnect,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: PlayerControlsStyles.scaledPadding(9, scale),
        vertical: PlayerControlsStyles.scaledPadding(9, scale),
      ),
      child: Row(children: [
        Icon(_protocolIcon(device.protocol), color: PlayerControlsStyles.speedActive, size: PlayerControlsStyles.scaledFontSize(10, scale)),
        SizedBox(width: PlayerControlsStyles.scaledPadding(7, scale)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(device.name, style: TextStyle(
            color: PlayerControlsStyles.speedActive,
            fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
            fontWeight: FontWeight.w600,
          )),
          Text(_stateLabel(state), style: TextStyle(
            color: PlayerControlsStyles.textSecondary,
            fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
          )),
        ])),
        GestureDetector(
          onTap: onDisconnect,
          child: Text('断开', style: TextStyle(
            color: PlayerControlsStyles.speedInactive,
            fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
          )),
        ),
      ]),
    );
  }
}

class _DeviceItem extends StatelessWidget {
  final CastDevice device;
  final VoidCallback onTap;
  final double scale;

  const _DeviceItem({required this.device, required this.onTap, required this.scale});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: PlayerControlsStyles.scaledPadding(9, scale),
          vertical: PlayerControlsStyles.scaledPadding(9, scale),
        ),
        child: Row(children: [
          Icon(_protocolIcon(device.protocol), color: PlayerControlsStyles.iconColor, size: PlayerControlsStyles.scaledFontSize(10, scale)),
          SizedBox(width: PlayerControlsStyles.scaledPadding(7, scale)),
          Expanded(child: Text(device.name, style: TextStyle(
            color: PlayerControlsStyles.speedInactive,
            fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
          ))),
          Text(_protocolLabel(device.protocol), style: TextStyle(
            color: PlayerControlsStyles.textSecondary,
            fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
          )),
        ]),
      ),
    );
  }
}

IconData _protocolIcon(CastProtocol protocol) {
  switch (protocol) {
    case CastProtocol.dlna:
      return Icons.cast;
    case CastProtocol.airplay:
      return Icons.airplay;
    case CastProtocol.chromecast:
      return Icons.cast_connected;
  }
}

String _protocolLabel(CastProtocol protocol) {
  switch (protocol) {
    case CastProtocol.dlna:
      return 'DLNA';
    case CastProtocol.airplay:
      return 'AirPlay';
    case CastProtocol.chromecast:
      return 'Chromecast';
  }
}

String _stateLabel(CastState state) {
  switch (state) {
    case CastState.disconnected:
      return '未连接';
    case CastState.discovering:
      return '搜索中';
    case CastState.connecting:
      return '连接中';
    case CastState.connected:
      return '已连接';
    case CastState.loading:
      return '加载中';
    case CastState.playing:
      return '播放中';
    case CastState.paused:
      return '已暂停';
    case CastState.buffering:
      return '缓冲中';
  }
}
