import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/storage/secure_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/auth/auth_provider.dart';
import 'features/settings/theme_provider.dart';
import 'shared/models/enums.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Eagerly probe Keychain availability so subsequent reads/writes are synchronous
  await SecureStorageService.instance.init();
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
      title: 'MeowTV',
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
