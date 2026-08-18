import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// 平台相关工具类，提供运行环境检测和设备信息获取能力。
class PlatformUtil {
  PlatformUtil._();

  /// 缓存模拟器检测结果，避免重复计算。
  static bool? _isEmulatorCache;

  /// 缓存设备 ID，避免重复获取。
  static String? _deviceIdCache;

  /// 缓存设备名称，避免重复获取。
  static String? _deviceNameCache;

  /// 缓存设备身份，避免重复获取。
  static DeviceIdentity? _identityCache;

  /// Apple TV 标志，由 app 启动时根据构建配置设置。
  /// 在 Apple TV 构建中，通过 --dart-define=IS_APPLE_TV=true 传入。
  static bool _isAppleTV = const bool.fromEnvironment('IS_APPLE_TV', defaultValue: false);

  /// 运行时设置 Apple TV 标志（用于无法通过 dart-define 传入的场景）。
  static void setAppleTV(bool value) {
    _isAppleTV = value;
  }

  // ── 设备 ID ──────────────────────────────────────────────────────────────

  /// 获取设备唯一标识。
  ///
  /// - Android: `android.id`（系统级唯一 ID，恢复出厂会重置）
  /// - iOS: `identifierForVendor`（同开发者的应用共享，重装会变）
  /// - macOS / Apple TV: 硬件 UUID
  /// - 其他: 降级为主机名
  static Future<String> getDeviceId() async {
    if (_deviceIdCache != null) return _deviceIdCache!;

    final deviceInfo = DeviceInfoPlugin();
    String id;

    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      // android.id 在 API 26+ 可用，是系统级唯一标识
      id = android.id;
    } else if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      // identifierForVendor 对同一开发者的所有应用相同
      id = ios.identifierForVendor ?? '';
    } else if (Platform.isMacOS) {
      final mac = await deviceInfo.macOsInfo;
      // macOS 硬件 UUID（Apple TV 也走此分支）
      id = mac.systemGUID ?? '';
    } else {
      // 降级：使用主机名
      id = Platform.localHostname;
    }

    // 如果获取不到有效 ID，生成一个随机值并缓存
    if (id.isEmpty) {
      id = 'unknown-${DateTime.now().millisecondsSinceEpoch}';
    }

    _deviceIdCache = id;
    return id;
  }

  // ── 设备名称 ─────────────────────────────────────────────────────────────

  /// 获取设备显示名称，格式为 "品牌 型号 / 系统版本"。
  ///
  /// - Android: "Samsung Galaxy S24 / Android 14"
  /// - iOS: "Apple iPhone15,2 / iOS 17.5"
  /// - macOS: "Apple MacBookPro / macOS 14.5"
  /// - Apple TV: "Apple AppleTV / tvOS 17.5"
  static Future<String> getDeviceName() async {
    if (_deviceNameCache != null) return _deviceNameCache!;

    final deviceInfo = DeviceInfoPlugin();
    String name;

    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      // brand 首字母大写 + model + Android 版本
      final brand = _capitalize(android.brand);
      name = '$brand ${android.model} / Android ${android.version.release}';
    } else if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      // iOS 设备: Apple + model name + iOS 版本
      final model = ios.utsname.machine;
      final osVersion = ios.systemVersion;
      name = 'Apple $model / iOS $osVersion';
    } else if (Platform.isMacOS) {
      final mac = await deviceInfo.macOsInfo;
      final osVersion = '${mac.majorVersion}.${mac.minorVersion}${mac.patchVersion != 0 ? '.${mac.patchVersion}' : ''}';
      if (_isAppleTV) {
        // Apple TV 走 macOS 分支，但显示为 tvOS
        name = 'Apple AppleTV / tvOS $osVersion';
      } else {
        name = 'Apple ${mac.model} / macOS $osVersion';
      }
    } else {
      name = 'Unknown Device';
    }

    _deviceNameCache = name;
    return name;
  }

  // ── 设备身份 ──────────────────────────────────────────────────────────────

  /// 获取真实设备身份，用于 AirPlay 2 RTSP SETUP body 与 `/play` V2 body。
  ///
  /// 真实 Apple TV 会校验 SETUP body 里的 `deviceID` / `macAddress` /
  /// `model` 等字段；之前 dart_cast 在 SETUP body 硬编码 `AA:BB:CC:DD:EE:FF`
  /// / `iPhone14,3` 等 IEEE 未分配的假身份，导致真实 Apple TV 拒绝 SETUP
  /// 返回 500，进而 RECORD 455、`/play` 出现 "false 200"。本方法返回真实
  /// 平台身份（iOS / macOS / Android 各自的 model + 真实 MAC 派生），喂给
  /// dart_cast 的 `CastMedia.senderIdentity`。
  ///
  /// Android 10+ (API 29+) WifiManager.getConnectionInfo().macAddress 返回
  /// 固定的 `02:00:00:00:00:00`；device_info_plus 也无法读取真实 MAC。这里
  /// 使用 android.id 作为稳定 ID，按 SHA-1 派生一个 Apple 段 OUI
  /// (`00:1F:F3`) 的合法 MAC——同一台 Android 设备每次启动派生结果一致，
  /// Apple TV 用 deviceID 做会话去重时不会因为 MAC 漂移而拒绝 SETUP。
  static Future<DeviceIdentity> getDeviceIdentity({String? appVersion}) async {
    if (_identityCache != null) return _identityCache!;

    final deviceInfo = DeviceInfoPlugin();
    DeviceIdentity identity;

    if (Platform.isAndroid) {
      final a = await deviceInfo.androidInfo;
      identity = DeviceIdentity(
        macAddress: _macFromId(a.id),
        model: a.model,
        osName: 'Android',
        osVersion: a.version.release,
        osBuildVersion:
            '${a.version.baseOS ?? ''}/${a.version.incremental}',
        deviceName: '${_capitalize(a.brand)} ${a.model}',
        appVersion: appVersion ?? '0.0.0',
        bundleId: 'tv.meow.app',
      );
    } else if (Platform.isIOS) {
      final i = await deviceInfo.iosInfo;
      identity = DeviceIdentity(
        macAddress: _macFromId(i.identifierForVendor ?? ''),
        model: i.utsname.machine,
        osName: 'iPhone OS',
        osVersion: i.systemVersion,
        osBuildVersion: i.utsname.version,
        deviceName: 'Apple ${i.utsname.machine}',
        appVersion: appVersion ?? '0.0.0',
        bundleId: 'tv.meow.app',
      );
    } else if (Platform.isMacOS) {
      final m = await deviceInfo.macOsInfo;
      identity = DeviceIdentity(
        macAddress: _macFromId(m.systemGUID ?? ''),
        model: m.model,
        osName: _isAppleTV ? 'tvOS' : 'macOS',
        osVersion: '${m.majorVersion}.${m.minorVersion}.${m.patchVersion}',
        osBuildVersion: '',
        deviceName: _isAppleTV ? 'Apple AppleTV' : 'Apple ${m.model}',
        appVersion: appVersion ?? '0.0.0',
        bundleId: 'tv.meow.app',
      );
    } else {
      identity = DeviceIdentity(
        macAddress: _macFromId(Platform.localHostname),
        model: 'Unknown',
        osName: Platform.operatingSystem,
        osVersion: Platform.operatingSystemVersion,
        osBuildVersion: '',
        deviceName: Platform.localHostname,
        appVersion: appVersion ?? '0.0.0',
        bundleId: 'tv.meow.app',
      );
    }

    _identityCache = identity;
    return identity;
  }

  /// 把任意字符串稳定地映射成合法 MAC 格式（XX:XX:XX:XX:XX:XX，OUI 用
  /// Apple 段 `00:1F:F3`）。
  static String _macFromId(String id) {
    final hash = sha1.convert(utf8.encode(id)).bytes;
    return '00:1F:F3:${_hex(hash[0])}:${_hex(hash[1])}:${_hex(hash[2])}';
  }

  static String _hex(int b) =>
      b.toRadixString(16).padLeft(2, '0').toUpperCase();

  // ── 设备类型 ─────────────────────────────────────────────────────────────

  /// 获取当前设备类型值（与后端 DeviceType 枚举对齐）。
  ///
  /// - Web = 0
  /// - Android = 1
  /// - iOS = 2
  /// - AppleTV = 3
  static int get deviceType {
    if (_isAppleTV) return 3;
    if (Platform.isAndroid) return 1;
    if (Platform.isIOS) return 2;
    // macOS 等其他平台暂归为 Web
    return 0;
  }

  /// 判断当前是否为 Apple TV 平台。
  static bool get isAppleTV => _isAppleTV;

  // ── 模拟器检测 ──────────────────────────────────────────────────────────

  /// 当前是否运行在 Android 模拟器上。
  static Future<bool> isAndroidEmulator() async {
    if (!Platform.isAndroid) return false;
    if (_isEmulatorCache != null) return _isEmulatorCache!;

    final deviceInfo = DeviceInfoPlugin();
    final android = await deviceInfo.androidInfo;

    // 最直接的检测：Android 原生 API 已判断是否为物理设备
    if (!android.isPhysicalDevice) {
      _isEmulatorCache = true;
      return true;
    }

    // 以下为冗余检测，防止 isPhysicalDevice 在某些模拟器上误报
    final hardware = android.hardware.toLowerCase();
    final product = android.product.toLowerCase();
    final fingerprint = android.fingerprint.toLowerCase();
    final model = android.model.toLowerCase();
    final brand = android.brand.toLowerCase();
    final abis = android.supportedAbis;

    const emulatorHardware = ['goldfish', 'ranchu', 'vbox86'];
    if (emulatorHardware.any((h) => hardware.contains(h))) {
      _isEmulatorCache = true;
      return true;
    }

    const emulatorProducts = ['sdk', 'sdk_gphone', 'sdk_x86', 'sdk_x86_64'];
    if (emulatorProducts.any((p) => product.contains(p))) {
      _isEmulatorCache = true;
      return true;
    }

    if (fingerprint.contains('generic') || fingerprint.contains('emulator')) {
      _isEmulatorCache = true;
      return true;
    }

    if (model.contains('sdk') || model.contains('emulator')) {
      _isEmulatorCache = true;
      return true;
    }

    if (brand == 'generic') {
      _isEmulatorCache = true;
      return true;
    }

    final hasArm = abis.any((a) => a.startsWith('arm'));
    final hasX86 = abis.any((a) => a.contains('x86'));
    if (hasX86 && !hasArm) {
      _isEmulatorCache = true;
      return true;
    }

    _isEmulatorCache = false;
    return false;
  }

  // ── 缓存管理 ────────────────────────────────────────────────────────────

  /// 清除所有缓存（用于测试）。
  static void clearCache() {
    _isEmulatorCache = null;
    _deviceIdCache = null;
    _deviceNameCache = null;
    _identityCache = null;
  }

  /// 将字符串首字母大写（用于 Android brand 如 "samsung" → "Samsung"）。
  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

/// 设备身份，用于 AirPlay 2 RTSP SETUP body 与 `/play` V2 body。
///
/// Apple TV 会校验这些字段——之前 dart_cast 硬编码 IEEE 未分配的假身份
///（`AA:BB:CC:DD:EE:FF` / `iPhone14,3` 等）会被真实 Apple TV 拒绝。
class DeviceIdentity {
  /// MAC 地址（XX:XX:XX:XX:XX:XX）。
  final String macAddress;

  /// 设备型号（Android: `model`；iOS/macOS: `utsname.machine`）。
  final String model;

  /// 操作系统名（`Android` / `iPhone OS` / `tvOS` / `macOS`）。
  final String osName;

  /// 操作系统版本。
  final String osVersion;

  /// 系统构建版本（`Build.DISPLAY` / `utsname.version`）。
  final String osBuildVersion;

  /// 设备显示名（`"Samsung Galaxy S24"` / `"Apple iPhone15,2"`）。
  final String deviceName;

  /// app 版本（用于 AirPlay SETUP body 的 `sourceVersion`）。
  final String appVersion;

  /// app bundle ID（用于 `/play` V2 body 的 `clientBundleID`）。
  final String bundleId;

  const DeviceIdentity({
    required this.macAddress,
    required this.model,
    required this.osName,
    required this.osVersion,
    required this.osBuildVersion,
    required this.deviceName,
    required this.appVersion,
    required this.bundleId,
  });
}
