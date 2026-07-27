import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/logger/app_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 投屏代理模式配置
// ─────────────────────────────────────────────────────────────────────────────

/// 投屏代理模式状态
class CastProxyState {
  /// 是否启用投屏代理模式（绑定 0.0.0.0 + 使用 LAN IP）
  final bool enabled;

  /// 选中的 LAN IP 地址（用户手动选择或输入）
  final String selectedIp;

  /// 可用的 LAN IP 列表（自动检测）
  final List<String> availableIps;

  const CastProxyState({
    this.enabled = false,
    this.selectedIp = '',
    this.availableIps = const [],
  });

  CastProxyState copyWith({
    bool? enabled,
    String? selectedIp,
    List<String>? availableIps,
  }) {
    return CastProxyState(
      enabled: enabled ?? this.enabled,
      selectedIp: selectedIp ?? this.selectedIp,
      availableIps: availableIps ?? this.availableIps,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CastProxyNotifier
// ─────────────────────────────────────────────────────────────────────────────

class CastProxyNotifier extends StateNotifier<CastProxyState> {
  final SecureStorageService _storage;

  static const _keyEnabled = 'cast_proxy_enabled';
  static const _keySelectedIp = 'cast_proxy_selected_ip';

  CastProxyNotifier(this._storage) : super(const CastProxyState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabledStr = await _storage.read(key: _keyEnabled);
    final savedIp = await _storage.read(key: _keySelectedIp);
    final ips = await _detectLanIps();

    final enabled = enabledStr == 'true';
    // 如果有保存的 IP 且仍可用，使用保存的；否则选第一个
    String selectedIp = '';
    if (savedIp != null && savedIp.isNotEmpty && ips.contains(savedIp)) {
      selectedIp = savedIp;
    } else if (ips.isNotEmpty) {
      selectedIp = ips.first;
    }

    state = CastProxyState(
      enabled: enabled,
      selectedIp: selectedIp,
      availableIps: ips,
    );
    appLogger.i('[CastProxy] 配置加载: enabled=$enabled, selectedIp=$selectedIp, ips=$ips');
  }

  /// 设置是否启用投屏代理模式
  Future<void> setEnabled(bool value) async {
    await _storage.write(key: _keyEnabled, value: value.toString());
    state = state.copyWith(enabled: value);
    appLogger.i('[CastProxy] 代理模式: ${value ? "已启用" : "已关闭"}');
  }

  /// 选择 LAN IP
  Future<void> selectIp(String ip) async {
    await _storage.write(key: _keySelectedIp, value: ip);
    state = state.copyWith(selectedIp: ip);
    appLogger.i('[CastProxy] 选择 IP: $ip');
  }

  /// 手动输入 LAN IP
  Future<void> setManualIp(String ip) async {
    final trimmed = ip.trim();
    if (trimmed.isEmpty) return;
    await _storage.write(key: _keySelectedIp, value: trimmed);
    // 如果不在自动检测列表中，添加进去
    final ips = List<String>.from(state.availableIps);
    if (!ips.contains(trimmed)) {
      ips.add(trimmed);
    }
    state = state.copyWith(selectedIp: trimmed, availableIps: ips);
    appLogger.i('[CastProxy] 手动输入 IP: $trimmed');
  }

  /// 刷新 LAN IP 列表
  Future<void> refreshIps() async {
    final ips = await _detectLanIps();
    String selectedIp = state.selectedIp;
    // 如果当前选中的 IP 不在列表中且列表不为空，切换到第一个
    if (!ips.contains(selectedIp) && ips.isNotEmpty) {
      selectedIp = ips.first;
    }
    state = state.copyWith(availableIps: ips, selectedIp: selectedIp);
    appLogger.i('[CastProxy] IP 刷新: $ips');
  }

  /// 检测本机 LAN IP 地址
  Future<List<String>> _detectLanIps() async {
    final ips = <String>[];
    try {
      for (final interface in await NetworkInterface.list()) {
        for (final addr in interface.addresses) {
          // 只取 IPv4 地址，排除 loopback
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              addr.address.isNotEmpty) {
            ips.add(addr.address);
          }
        }
      }
    } catch (e) {
      appLogger.e('[CastProxy] 检测 LAN IP 失败', error: e);
    }
    return ips;
  }

  /// 获取投屏使用的代理 URL 基础地址
  ///
  /// 启用代理模式时返回 `http://{selectedIp}:{port}`，
  /// 未启用时返回空字符串（表示使用远程原始 URL）。
  String proxyBaseUrl(int port) {
    if (!state.enabled || state.selectedIp.isEmpty || port == 0) {
      return '';
    }
    return 'http://${state.selectedIp}:$port';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final castProxyProvider = StateNotifierProvider<CastProxyNotifier, CastProxyState>((ref) {
  return CastProxyNotifier(SecureStorageService.instance);
});
