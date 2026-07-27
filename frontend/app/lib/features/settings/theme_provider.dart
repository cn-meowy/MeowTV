import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/secure_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/enums.dart';

/// Theme state notifier.
class ThemeNotifier extends StateNotifier<AppThemeMode> {
  final SecureStorageService _storage;
  ThemeNotifier(this._storage) : super(AppThemeMode.dark) {
    _load();
  }

  Future<void> _load() async {
    final mode = await _storage.getThemeMode();
    if (mode != null) {
      for (final m in AppThemeMode.values) {
        if (m.name == mode) {
          state = m;
          return;
        }
      }
    }
  }

  Future<void> setTheme(AppThemeMode mode) async {
    state = mode;
    await _storage.setThemeMode(mode.name);
  }

  ThemeData currentTheme([Brightness? platformBrightness]) {
    switch (state) {
      case AppThemeMode.dark:
        return AppTheme.darkTheme;
      case AppThemeMode.light:
        return AppTheme.lightTheme;
      case AppThemeMode.system:
        final isDark = platformBrightness ?? Brightness.dark;
        return isDark == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme;
    }
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, AppThemeMode>((ref) {
  return ThemeNotifier(SecureStorageService.instance);
});
