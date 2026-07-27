import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Splash screen shown while auth state is initializing.
/// GoRouter's redirect will navigate away once init completes.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: colors.primary),
      ),
    );
  }
}
