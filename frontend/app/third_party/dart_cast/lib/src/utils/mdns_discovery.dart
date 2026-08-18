import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import '../core/cast_device.dart';
import '../protocols/airplay/airplay_features.dart';
import 'logger.dart';

/// Represents a discovered mDNS service with its TXT records.
///
/// Shared infrastructure for both Chromecast and AirPlay device discovery.
class MdnsServiceInfo {
  /// The mDNS service name.
  final String name;

  /// The resolved host address.
  final String host;

  /// The service port.
  final int port;

  /// TXT record key-value pairs from the mDNS advertisement.
  final Map<String, String> txtRecords;

  const MdnsServiceInfo({
    required this.name,
    required this.host,
    required this.port,
    required this.txtRecords,
  });

  /// Human-readable device name.
  ///
  /// Uses the Chromecast `fn` TXT field if present, otherwise falls back
  /// to the mDNS service [name].
  String get friendlyName {
    if (txtRecords.containsKey('fn')) return txtRecords['fn']!;
    // Strip mDNS service suffix from name (e.g., "My TV._airplay._tcp.local" → "My TV")
    final dotIndex = name.indexOf('._');
    return dotIndex > 0 ? name.substring(0, dotIndex) : name;
  }

  /// Unique device identifier.
  ///
  /// Uses Chromecast `id` or AirPlay `deviceid` TXT field.
  String get deviceId => txtRecords['id'] ?? txtRecords['deviceid'] ?? '';

  /// Device model string.
  ///
  /// Uses Chromecast `md` or AirPlay `model` TXT field.
  String get model => txtRecords['md'] ?? txtRecords['model'] ?? '';

  /// Whether the given AirPlay features bitmask indicates video support.
  ///
  /// The [features] string can be single-part (`"0x5A7FFFF7"`) or
  /// two-part (`"0x5A7FFFF7,0x1E"`) where the first part is the lower
  /// 32 bits and the second is the upper 32 bits.
  ///
  /// Video support is bit 0 (`SupportsAirPlayVideoV1`) **or** bit 49
  /// (`SupportsAirPlayVideoV2`). Checking only bit 0 misreads every
  /// AirPlay 2–only receiver as incapable of video — which is exactly the
  /// wrong call for the Roku and Google TV devices that set bit 49 and leave
  /// bit 0 clear.
  static bool supportsVideo(String features) =>
      AirPlayFeatures.parse(features).supportsVideo;

  /// Creates a [CastDevice] configured for the Chromecast protocol.
  CastDevice toChromecastDevice() {
    return CastDevice(
      id: deviceId,
      name: friendlyName,
      protocol: CastProtocol.chromecast,
      address: InternetAddress(host),
      port: port,
      metadata: Map<String, String>.from(txtRecords),
    );
  }

  /// Creates a [CastDevice] configured for the AirPlay protocol.
  CastDevice toAirplayDevice() {
    return CastDevice(
      id: deviceId,
      name: friendlyName,
      protocol: CastProtocol.airplay,
      address: InternetAddress(host),
      port: port,
      metadata: Map<String, String>.from(txtRecords),
    );
  }
}

/// Function type for performing mDNS service discovery.
///
/// Returns a stream of [MdnsServiceInfo] entries found on the network.
typedef MdnsLookup = Stream<MdnsServiceInfo> Function(String serviceType);

/// Constants and utilities for mDNS-based device discovery.
class MdnsDiscovery {
  MdnsDiscovery._();

  /// mDNS service type for Chromecast devices.
  static const String chromecastServiceType = '_googlecast._tcp.local';

  /// mDNS service type for AirPlay devices.
  static const String airplayServiceType = '_airplay._tcp.local';

  /// Discover mDNS services of the given [serviceType] using the
  /// `multicast_dns` package.
  ///
  /// Yields [MdnsServiceInfo] entries as they are found on the local network.
  /// The stream completes after all discovered PTR records have been resolved.
  static Stream<MdnsServiceInfo> discover(String serviceType) async* {
    CastLogger.info('mDNS: starting discovery for $serviceType');
    final client = MDnsClient();
    try {
      await client.start();
    } catch (e) {
      CastLogger.error('mDNS discovery failed to start: $e');
      return;
    }

    // iOS 14+ Local Network Privacy pre-warm：start() 之后立刻吞掉一次
    // 同步的小型 PTR 探针。`multicast_dns` 内部在 wildcard socket 上裸调
    // send()，未授权时抛 `SocketException(EHOSTUNREACH)` 一路冒到
    // dart_vm_initializer 的 unhandled exception 通道。在这里包一层
    // try/catch 既吞掉首次 send 的异常，也把弹窗触发时机提前到
    // `client.start()` 之后、正常 discover 循环之前；后续真实查询若
    // 授权已被授予，仍按原路径正常返回结果。
    try {
      CastLogger.debug('mDNS: pre-warm probe for Local Network permission');
      await for (final PtrResourceRecord ptr in client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(serviceType),
          )
          .timeout(
            const Duration(seconds: 2),
            onTimeout: (sink) => sink.close(),
          )) {
        // 不消费预热结果，立即退出让真正的 discover 循环接管。
        // 引入 ptr 仅为满足 lint（未使用的 for-each 变量名不能是 `_`）。
        assert(ptr.domainName.isNotEmpty);
        break;
      }
    } catch (e) {
      CastLogger.warning(
        'mDNS: pre-warm probe failed (likely Local Network not yet granted): $e',
      );
    }

    try {
      const nestedTimeout = Duration(seconds: 3);
      final seenServices = <String>{};

      // Send multiple mDNS queries to catch slow-responding devices.
      // Each lookup() sends one query — devices may not respond to the first.
      for (int round = 0; round < 3; round++) {
        if (round > 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
          CastLogger.debug(
            'mDNS: re-querying PTR records (round ${round + 1})',
          );
        }

        // Query for PTR records (service instances).
        // 外层 try/catch 兜底：iOS 14+ 在未授权本地网络时，multicast_dns
        // 内部 send() 会抛 `SocketException: No route to host (errno=65)`，
        // 此前会一路冒到 dart_vm_initializer 的 unhandled exception 通道。
        // 这里把每个 round 的同步 lookup 包起来吞掉；授权后正常查询仍照常。
        try {
          await for (final PtrResourceRecord ptr in client
              .lookup<PtrResourceRecord>(
                ResourceRecordQuery.serverPointer(serviceType),
              )) {
            // Skip already-discovered services
            if (seenServices.contains(ptr.domainName)) continue;
            seenServices.add(ptr.domainName);
            try {
              // For each PTR result, look up SRV record (host + port).
              await for (final SrvResourceRecord srv in client
                  .lookup<SrvResourceRecord>(
                    ResourceRecordQuery.service(ptr.domainName),
                  )
                  .timeout(nestedTimeout, onTimeout: (sink) => sink.close())) {
                try {
                  // Look up A record (IPv4 address).
                  await for (final IPAddressResourceRecord ip in client
                      .lookup<IPAddressResourceRecord>(
                        ResourceRecordQuery.addressIPv4(srv.target),
                      )
                      .timeout(
                        nestedTimeout,
                        onTimeout: (sink) => sink.close(),
                      )) {
                    // Look up TXT records (metadata key=value pairs).
                    final txtRecords = <String, String>{};
                    try {
                      await for (final TxtResourceRecord txt in client
                          .lookup<TxtResourceRecord>(
                            ResourceRecordQuery.text(ptr.domainName),
                          )
                          .timeout(
                            nestedTimeout,
                            onTimeout: (sink) => sink.close(),
                          )) {
                        // The multicast_dns package joins TXT strings with writeln(),
                        // producing newline-separated key=value pairs.
                        for (final line in txt.text.split('\n')) {
                          final trimmed = line.trim();
                          if (trimmed.isEmpty) continue;
                          final eqIndex = trimmed.indexOf('=');
                          if (eqIndex > 0) {
                            txtRecords[trimmed.substring(0, eqIndex)] = trimmed
                                .substring(eqIndex + 1);
                          }
                        }
                      }
                    } catch (_) {
                      // TXT lookup timed out — proceed with empty TXT records
                    }

                    CastLogger.info(
                      'mDNS: found service "${ptr.domainName}" at ${ip.address.address}:${srv.port}',
                    );
                    yield MdnsServiceInfo(
                      name: ptr.domainName,
                      host: ip.address.address,
                      port: srv.port,
                      txtRecords: txtRecords,
                    );
                  }
                } catch (_) {
                  // A record lookup timed out — skip this device
                }
              }
            } catch (_) {
              // SRV lookup timed out — skip this device
            }
          }
        } catch (e) {
          // PTR 探针在 iOS 未授权本地网络时抛 SocketException；
          // 已经过预热探针弹过系统弹窗，这里仅记录日志、不中断整轮发现。
          CastLogger.warning(
            'mDNS: PTR lookup failed (likely Local Network not yet granted): $e',
          );
        }
      } // end for round
    } finally {
      client.stop();
    }
  }
}
