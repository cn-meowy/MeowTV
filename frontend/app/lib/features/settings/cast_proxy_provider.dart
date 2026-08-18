import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/logger/app_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 投屏代理模式配置
// ─────────────────────────────────────────────────────────────────────────────

/// IPv4 接口候选条目。
class LanCandidate {
  /// 接口名（如 `en0`、`wlan0`、`utun0`、`ppp0`、`pdp_ip0`）。
  final String interfaceName;

  /// IPv4 地址。
  final String address;

  const LanCandidate(this.interfaceName, this.address);

  @override
  String toString() => '$interfaceName=$address';
}

/// 判断是否为 RFC1918 私有 IPv4 段。
bool _isRfc1918(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null) return false;
  if (a == 10) return true; // 10.0.0.0/8
  if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
  if (a == 192 && b == 168) return true; // 192.168.0.0/16
  return false;
}

/// 判断是否为 169.254.0.0/16 链路本地（应排除）。
bool _isLinkLocal(String ip) {
  return ip.startsWith('169.254.');
}

/// 判断是否为 127.0.0.0/8 loopback（应排除）。
bool _isLoopbackIp(String ip) {
  return ip.startsWith('127.');
}

/// 判断接口名是否属于 iOS/macOS 的 en*（WiFi/以太网/雷电桥）。
bool _isAppleEnInterface(String name) {
  return name.startsWith('en');
}

/// 判断接口名是否属于 VPN/移动网络（`utun*`/`tun*`/`ppp*`/`pdp_ip*`）。
bool _isVpnOrTunnelInterface(String name) {
  if (name.startsWith('utun')) return true;
  if (name.startsWith('tun')) return true;
  if (name.startsWith('ppp')) return true;
  if (name.startsWith('pdp_ip')) return true;
  return false;
}

/// 纯静态排序函数：从一组接口候选中按优先级挑出 LAN IP。
///
/// **优先级**：
/// 1. 接口名以 `en` 开头（iOS/macOS WiFi/以太网）的 RFC1918 IPv4；
/// 2. 其他接口（Android `wlan0` 等）的 RFC1918 IPv4；
/// 3. 前两级都为空 → 退回全部 IPv4 非 loopback、非链路本地（保持兼容
///    LAN 用公网段的极少数环境）。
///
/// **排除**：`169.254.*` 链路本地。
/// VPN/隧道接口（`utun*`/`tun*`/`ppp*`/`pdp_ip*`）在无其他候选时才出现在
/// 回退列表中。
///
/// 该函数为纯函数，便于单测。
String? rankLanIp(List<LanCandidate> candidates) {
  if (candidates.isEmpty) return null;

  // 排除链路本地 + loopback
  final filtered = candidates.where((c) =>
      !_isLinkLocal(c.address) && !_isLoopbackIp(c.address)).toList(growable: false);
  if (filtered.isEmpty) return null;

  // 第 1 级：en* + RFC1918
  for (final c in filtered) {
    if (_isAppleEnInterface(c.interfaceName) && _isRfc1918(c.address)) {
      return c.address;
    }
  }

  // 第 2 级：非 en* 但 RFC1918（Android wlan 等）
  for (final c in filtered) {
    if (!_isAppleEnInterface(c.interfaceName) &&
        !_isVpnOrTunnelInterface(c.interfaceName) &&
        _isRfc1918(c.address)) {
      return c.address;
    }
  }

  // 第 3 级：回退全部非 VPN 隧道、非链路本地的 IPv4
  for (final c in filtered) {
    if (!_isVpnOrTunnelInterface(c.interfaceName)) {
      return c.address;
    }
  }

  // 第 4 级（最后退路）：含 VPN 隧道在内（极少环境：仅 VPN 存活）
  for (final c in filtered) {
    return c.address;
  }

  return null;
}

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

  Future<void>? _loadSettingsFuture;

  CastProxyNotifier(this._storage) : super(const CastProxyState()) {
    _loadSettingsFuture = _loadSettings();
  }

  /// 确保设置已加载完成（防重入）。
  /// 投屏前必须 await，避免 _loadSettings 异步未完成时 availableIps 为空
  /// 导致自动启用代理条件不满足。
  Future<void> ensureLoaded() {
    return _loadSettingsFuture ??= _loadSettings();
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

  /// 检测本机 LAN IP 地址（按 rankLanIp 优先级排序后的列表）。
  Future<List<String>> _detectLanIps() async {
    final candidates = <LanCandidate>[];
    try {
      for (final interface in await NetworkInterface.list()) {
        for (final addr in interface.addresses) {
          // 只取 IPv4 地址，排除 loopback
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              addr.address.isNotEmpty) {
            candidates.add(LanCandidate(interface.name, addr.address));
          }
        }
      }
    } catch (e) {
      appLogger.e('[CastProxy] 检测 LAN IP 失败', error: e);
      return const [];
    }

    // 先按 rankLanIp 选最佳，再把剩余的非链路本地/loopback IPv4 追加，便于用户手动切换。
    final ordered = <String>[];
    final best = rankLanIp(candidates);
    if (best != null) ordered.add(best);
    for (final c in candidates) {
      if (!_isLinkLocal(c.address) &&
          !_isLoopbackIp(c.address) &&
          c.address != best &&
          !ordered.contains(c.address)) {
        ordered.add(c.address);
      }
    }
    appLogger.i('[CastProxy] _detectLanIps 候选=$candidates, 排序结果=$ordered');
    return ordered;
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
