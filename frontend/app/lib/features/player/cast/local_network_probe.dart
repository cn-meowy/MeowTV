import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

import '../../../core/logger/app_logger.dart';

/// 启动期预热 iOS 14+ "本地网络"授权弹窗。
///
/// iOS 14+ 的 Local Network Privacy 机制：
/// - 首次发送组播 / 广播包前必须先弹系统授权窗
/// - 用户授权之前，所有 `send()` 会被内核拦截并以 `EHOSTUNREACH` 失败
/// - 弹窗只在 app 第一次触发时出现，授权结果会被系统持久化
///
/// MeowTV 的投屏发现（DLNA / Chromecast / AirPlay）都依赖组播。在用户点
/// 开"投屏"面板时才首次发送组播，会出现"刚点开就报错"的体验。本类提供
/// [warmUpLocalNetwork]：在 app 启动时主动发起一次无害的 `_googlecast`
/// PTR 探针，触发系统弹窗；失败 / 异常一律吞掉，仅留日志便于诊断。
///
/// 不要使用 `_airplay._tcp.local` 做探针：iOS 14+ 对 `_airplay._tcp` 的
/// "AirPlay 接收方声明"有更严格的额外约束，单独查询可能触发额外授权
/// 提示或被 App Store 审核挑刺。`_googlecast._tcp.local` 命中 Info.plist
/// 已声明的 `NSBonjourServices`，足够触发 Local Network 弹窗。
class LocalNetworkProbe {
  LocalNetworkProbe._();

  /// 是否已经触发过预热。多次冷启动会刷新"用户是否在系统设置里改了授权"。
  static bool _hasWarmedUp = false;

  /// 启动期预热 iOS "本地网络"系统授权弹窗。
  ///
  /// 必须 `await`（在 `runApp` 之前）。异常一律吞掉，不影响 app 启动。
  /// 失败时通常意味着系统弹窗还没被点授权或用户拒绝；下次冷启动会重试。
  static Future<void> warmUpLocalNetwork() async {
    if (_hasWarmedUp) return;
    _hasWarmedUp = true;

    appLogger.i('[Cast] LocalNetworkProbe: 预热 iOS 本地网络授权弹窗');

    MDnsClient? client;
    try {
      client = MDnsClient();
      await client.start();

      // 命中 Info.plist 已声明的 NSBonjourServices，触发系统弹窗。
      // 2 秒超时即可：弹窗触发是同步事件，发送完成即返回。
      try {
        await for (final PtrResourceRecord ptr in client
            .lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer('_googlecast._tcp.local'),
            )
            .timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
          // 不消费真实设备列表，仅做"触发弹窗"用途。
          // 引入 ptr 仅为满足 lint（未使用的 for-each 变量名不能是 `_`）。
          assert(ptr.domainName.isNotEmpty);
          break;
        }
        appLogger.i('[Cast] LocalNetworkProbe: 预热探针完成（系统已记录首次组播）');
      } on TimeoutException {
        // 静默超时：2 秒内没收到响应也属正常（探测纯发包，不一定有人应答）。
      } catch (e) {
        // SocketException (EHOSTUNREACH errno=65) 等都吞掉：用户尚未授权
        // 时 iOS 必然抛错，授权后会自愈。
        appLogger.w(
          '[Cast] LocalNetworkProbe: 预热探针失败（很可能是用户尚未授予本地网络）: $e',
        );
      }
    } catch (e, st) {
      appLogger.w(
        '[Cast] LocalNetworkProbe: mDNS client 启动失败',
        error: e,
        stackTrace: st,
      );
    } finally {
      try {
        client?.stop();
      } catch (_) {
        // ignore
      }
    }
  }
}