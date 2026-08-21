import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_cast/dart_cast.dart';

import 'core/logger/app_logger.dart';
import 'core/storage/secure_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/auth/auth_provider.dart';
import 'features/player/cast/local_network_probe.dart';
import 'features/settings/theme_provider.dart';
import 'shared/models/enums.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Eagerly probe Keychain availability so subsequent reads/writes are synchronous
  await SecureStorageService.instance.init();

  // 启动期预热 iOS 14+ "本地网络"系统授权弹窗。
  // 投屏发现（DLNA / Chromecast / AirPlay）都依赖组播，iOS 14+ 在用户授权
  // 本地网络之前会拦截组播 send()。在 runApp 之前主动发一次无害的 mDNS
  // 探针，让系统弹窗在 app 启动 1-2 秒内自动出现。失败 / 异常一律吞掉，
  // 不影响 app 启动；用户授权后下次冷启动自愈。
  await LocalNetworkProbe.warmUpLocalNetwork();

  // 接通 dart_cast 日志：投屏 404 诊断。dart_cast 的 MediaProxy upstream 状态码、
  // DLNA proxy URL、HLS 二次重写内容等关键日志默认走 CastLogger 静态回调，
  // 不接则全部丢弃，无法定位投屏 404 发生在哪一跳。
  CastLogger.setCallback((level, message) {
    final msg = '[dart_cast] $message';
    switch (level) {
      case 'ERROR':
        appLogger.e(msg);
        break;
      case 'WARNING':
        appLogger.w(msg);
        break;
      case 'INFO':
        appLogger.i(msg);
        break;
      default: // DEBUG 及其它
        appLogger.d(msg);
    }
  });

  runApp(const ProviderScope(child: MeowTVApp()));
}

class MeowTVApp extends ConsumerStatefulWidget {
  const MeowTVApp({super.key});

  @override
  ConsumerState<MeowTVApp> createState() => _MeowTVAppState();
}

class _MeowTVAppState extends ConsumerState<MeowTVApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(authProvider.notifier).init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.read(goRouterProvider);
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == AppThemeMode.dark ||
        (themeMode == AppThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isDark
          ? AppTheme.tabBarBg
          : AppTheme.lightTabBarBg,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));

    return MaterialApp.router(
      title: 'PurrTV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode == AppThemeMode.light
          ? ThemeMode.light
          : themeMode == AppThemeMode.dark
              ? ThemeMode.dark
              : ThemeMode.system,
      routerConfig: router,
    );
  }
}
