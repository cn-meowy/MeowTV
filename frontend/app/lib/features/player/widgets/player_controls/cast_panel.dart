import 'dart:io' show Platform;
import 'package:dart_cast/dart_cast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/logger/app_logger.dart';
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
        appLogger.d('[Cast] cast_panel.initState 触发 startDiscovery');
        _cachedService?.startDiscovery();
      }
    });
  }

  @override
  void dispose() {
    // 使用缓存引用，避免在 dispose 后调用 ref（会抛出 StateError）
    appLogger.d('[Cast] cast_panel.dispose 触发 stopDiscovery');
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

    // AirPlay 设备计数 + 路由激活状态（仅 iOS/macOS 用于按钮显隐与配色）
    final allDevices = devicesAsync.valueOrNull ?? <CastDevice>[];
    final airPlayCount =
        allDevices.where((d) => d.protocol == CastProtocol.airplay).length;
    final airPlayActive = ref.watch(airPlayActiveProvider).valueOrNull ?? false;

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

        // AirPlay 入口（iOS/macOS 始终显示，不依赖 mDNS 扫描结果）
        // count > 0 时显示徽标计数，为 0 时隐藏徽标
        if (Platform.isIOS || Platform.isMacOS)
          _AirPlayEntry(
            scale: scale,
            count: airPlayCount,
            isActive: airPlayActive,
            onTap: (anchor) => _showAirPlayPicker(anchor),
          ),

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
              // 过滤掉 AirPlay 设备（仅用于按钮显隐/计数，不进入常规列表）
              // 和已连接的设备
              final list = devices
                  .where((d) => d.protocol != CastProtocol.airplay)
                  .where((d) => d.id != service.connectedDevice?.id)
                  .toList();
              if (list.isEmpty && currentState == CastState.discovering) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
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
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    vertical: PlayerControlsStyles.scaledPadding(28, scale),
                    horizontal: PlayerControlsStyles.scaledPadding(9, scale),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      '未发现设备',
                      style: TextStyle(color: PlayerControlsStyles.textSecondary, fontSize: PlayerControlsStyles.scaledFontSize(10, scale)),
                    ),
                    // iOS 14+ Local Network Privacy 提示：仅当 cast_service
                    // 报"本次发现完全失败"（所有 provider 都抛 SocketException，
                    // 无任何设备返回）时展示。授权后下次冷启动自愈。
                    if (Platform.isIOS && service.lastDiscoveryAllFailed) ...[
                      SizedBox(height: PlayerControlsStyles.scaledPadding(7, scale)),
                      Text(
                        '如未发现设备，请到 iOS 设置 → MeowTV → 本地网络 中允许',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: PlayerControlsStyles.textSecondary, fontSize: PlayerControlsStyles.scaledFontSize(9, scale)),
                      ),
                    ],
                    SizedBox(height: PlayerControlsStyles.scaledPadding(9, scale)),
                    GestureDetector(
                      onTap: () {
                        appLogger.i('[Cast] 用户点击重新搜索');
                        service.startDiscovery();
                      },
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
            loading: () => SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.symmetric(vertical: PlayerControlsStyles.scaledPadding(28, scale)),
              child: Center(child: Text(
                '正在搜索设备...',
                style: TextStyle(color: PlayerControlsStyles.textSecondary, fontSize: PlayerControlsStyles.scaledFontSize(10, scale)),
              )),
            ),
            error: (e, _) => SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                vertical: PlayerControlsStyles.scaledPadding(28, scale),
                horizontal: PlayerControlsStyles.scaledPadding(9, scale),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('搜索失败: $e', style: TextStyle(color: PlayerControlsStyles.speedInactive, fontSize: PlayerControlsStyles.scaledFontSize(10, scale))),
                SizedBox(height: PlayerControlsStyles.scaledPadding(9, scale)),
                GestureDetector(
                  onTap: () {
                    appLogger.i('[Cast] 用户点击搜索失败重试');
                    service.startDiscovery();
                  },
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
    appLogger.i('[Cast] 用户点击设备 ${_deviceTag(device)}');
    widget.onDeviceSelected(device);
    widget.onDismiss();
  }

  Future<void> _showAirPlayPicker(Offset anchor) async {
    appLogger.i('[Cast] 用户点击 AirPlay 入口，调用 showPicker anchor=$anchor');
    final service = ref.read(airPlayRouteServiceProvider);
    final ok = await service.showPicker(anchor: anchor);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开系统 AirPlay 面板')),
      );
    }
  }
}

/// 统一设备标签，与 `cast_service.dart` / `player_screen.dart` 保持相同格式。
String _deviceTag(CastDevice d) =>
    '[id=${d.id.isEmpty ? "<empty>" : d.id}, '
    'name=${d.name}, '
    'addr=${d.address.address}:${d.port}, '
    'proto=${d.protocol.name}]';

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

/// AirPlay 入口按钮（仅 iOS/macOS）。
///
/// 整行可点击，点击后通过 AirPlayRouteService.showPicker 调用原生
/// `AVRoutePickerView` 触发系统 AirPlay 选路面板（不再内嵌 PlatformView）。
///
/// AirPlay 路由状态由 AirPlayRouteService 监听，自动反映到 [isActive]。
/// 入口始终显示；[count] > 0 时显示设备徽标，为 0 时隐藏徽标。
class _AirPlayEntry extends StatelessWidget {
  final double scale;
  final int count;
  final bool isActive;
  /// 点击回调，参数为入口行中心的 Flutter 全局坐标（用于原生定位 picker）。
  final void Function(Offset anchor) onTap;

  const _AirPlayEntry({
    required this.scale,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? PlayerControlsStyles.speedActive
        : PlayerControlsStyles.speedInactive;

    // 行内文字/徽标/箭头
    final trailing = <Widget>[
      Expanded(
          child: Text('AirPlay 投屏',
              style: TextStyle(
        color: color,
        fontSize: PlayerControlsStyles.scaledFontSize(10, scale),
        fontWeight: FontWeight.w600,
      ))),
      if (count > 0)
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: PlayerControlsStyles.scaledPadding(5, scale),
            vertical: PlayerControlsStyles.scaledPadding(2, scale),
          ),
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$count',
              style: TextStyle(
            color: PlayerControlsStyles.textSecondary,
            fontSize: PlayerControlsStyles.scaledFontSize(9, scale),
          )),
        ),
      Icon(Icons.chevron_right,
          color: PlayerControlsStyles.textSecondary,
          size: PlayerControlsStyles.scaledFontSize(10, scale)),
    ];

    // 整行可点击（InkWell，行高 ~44pt）。点击走 Dart → MethodChannel →
    // 原生常驻 AVRoutePickerView 触发系统选路面板。
    // 在 onTap 内取行中心全局坐标作为锚点传给原生；macOS 26 (Tahoe) 上按钮
    // 必须在窗口可见区域内才弹 popover。
    return InkWell(
      onTap: () {
        final renderBox = context.findRenderObject();
        if (renderBox is RenderBox) {
          final anchor = renderBox.localToGlobal(renderBox.size.center(Offset.zero));
          onTap(anchor);
        } else {
          onTap(Offset.zero);
        }
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: PlayerControlsStyles.scaledPadding(9, scale),
          vertical: PlayerControlsStyles.scaledPadding(10, scale),
        ),
        child: Row(children: [
          Icon(Icons.airplay, color: color, size: PlayerControlsStyles.scaledFontSize(10, scale)),
          SizedBox(width: PlayerControlsStyles.scaledPadding(7, scale)),
          ...trailing,
        ]),
      ),
    );
  }
}
