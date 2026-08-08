import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/home/home_screen.dart';
import '../../features/resource/resource_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/favorites/favorites_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/about_screen.dart';
import '../../features/admin/admin_settings_screen.dart';
import '../../features/detail/detail_screen.dart';
import '../../features/player/player_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/download/download_screen.dart';
import '../../features/qrcode/qrcode_scan_screen.dart';
import '../../features/qrcode/qrcode_display_screen.dart';
import '../../screens/splash_screen.dart';
import '../../screens/start_screen.dart';
import '../../screens/agreements_screen.dart';
import '../../screens/user_agreement_screen.dart';
import '../../screens/privacy_policy_screen.dart';
import '../../screens/login_screen.dart';
import '../../screens/main_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// A [ChangeNotifier] that signals GoRouter to re-run redirect
/// only when route-relevant auth fields change.
///
/// The redirect logic only depends on: `isInitializing`, `isLoggedIn`,
/// `hasAcceptedAgreements`, and `profile.role`.  Other state changes
/// (e.g. `profile` update, `baseUrl` change) must NOT trigger a
/// GoRouter refresh — otherwise every `fetchProfile()` call causes
/// the entire route tree to rebuild, which disposes & recreates
/// `HomeScreen`, calling `initState` → `loadData()` again → infinite loop.
class AuthNotifierListenable extends ChangeNotifier {
  AuthNotifierListenable(AuthNotifier authNotifier) {
    AuthState? prev;
    authNotifier.addListener((state) {
      // Only notify GoRouter when route-relevant fields actually change
      final p = prev;
      final shouldNotify =
          p == null ||
          p.isInitializing != state.isInitializing ||
          p.isLoggedIn != state.isLoggedIn ||
          p.hasAcceptedAgreements != state.hasAcceptedAgreements ||
          p.profile?.role != state.profile?.role;
      prev = state;
      if (shouldNotify) {
        notifyListeners();
      }
    });
  }
}

final authListenableProvider = Provider<AuthNotifierListenable>((ref) {
  final authNotifier = ref.watch(authProvider.notifier);
  return AuthNotifierListenable(authNotifier);
});

/// Pure redirect decision extracted from the GoRouter `redirect` callback.
///
/// Returns the location to redirect to, or `null` to stay on [loc].
/// Keeping this logic in a side-effect-free function makes the onboarding
/// state machine unit-testable without spinning up GoRouter/Riverpod.
///
/// The user-agreement and privacy-policy pages are reachable from the
/// agreements screen *before* the user has accepted the agreements, so
/// they must be whitelisted in the "not logged in, agreements NOT
/// accepted" branch — otherwise tapping them bounces back to /start.
String? routeRedirect(AuthState authState, String loc) {
  // While initializing, stay on splash (/)
  if (authState.isInitializing) {
    return loc == '/' ? null : '/';
  }

  // After initialization, route based on auth state
  final accepted = authState.hasAcceptedAgreements;
  final loggedIn = authState.isLoggedIn;

  final isSplash = loc == '/';
  final isStart = loc == '/start';
  final isAgreements = loc == '/agreements';
  final isLogin = loc == '/login';
  // Agreement detail pages are read-only legal docs reachable from both
  // the onboarding agreements screen and the profile screen.
  final isAgreementDetail =
      loc == '/user-agreement' || loc == '/privacy-policy';
  // Pages accessible only when logged in
  final isProtected =
      loc == '/home' ||
      loc == '/resource' ||
      loc == '/search' ||
      loc == '/favorites' ||
      loc == '/profile' ||
      loc == '/detail' ||
      loc == '/play' ||
      loc == '/history' ||
      loc == '/downloads' ||
      loc == '/admin-settings' ||
      loc == '/qrcode-scan';

  // Admin-only pages: redirect non-admin users
  if (loggedIn && loc == '/admin-settings') {
    final isAdmin = authState.profile?.role == 1;
    if (!isAdmin) return '/home';
  }

  // ── Logged in ──────────────────────────────────────────
  if (loggedIn) {
    // From splash/start/agreements/login → home
    if (isSplash || isStart || isAgreements || isLogin) return '/home';
    // Already on a protected page, stay
    return null;
  }

  // ── Not logged in, agreements NOT accepted ─────────────
  if (!accepted) {
    // Splash → start
    if (isSplash) return '/start';
    // Already on start/agreements, or reviewing the agreement detail
    // pages linked from the agreements screen — stay.
    if (isStart || isAgreements || isAgreementDetail) return null;
    // Any other page (including /login) → start
    return '/start';
  }

  // ── Agreements accepted, not logged in ─────────────────
  // Splash/start/agreements → login
  if (isSplash || isStart || isAgreements) return '/login';
  // Already on login, stay
  if (isLogin) return null;
  // Trying to access protected page → login
  if (isProtected) return '/login';
  // Fallback: stay on current page (about, agreement detail, etc.)
  return null;
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final listenable = ref.watch(authListenableProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: listenable,
    redirect: (context, state) =>
        routeRedirect(ref.read(authProvider), state.matchedLocation),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/start', builder: (context, state) => const StartScreen()),
      GoRoute(
        path: '/agreements',
        builder: (context, state) => const AgreementsScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/resource',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ResourceScreen()),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) {
              final doubanId = state.uri.queryParameters['douban_id'];
              final q = state.uri.queryParameters['q'];
              return NoTransitionPage(
                key: ValueKey('search-${q ?? ''}-${doubanId ?? ''}'),
                child: SearchScreen(initialDoubanId: doubanId, initialQuery: q),
              );
            },
          ),
          GoRoute(
            path: '/favorites',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: FavoritesScreen()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ProfileScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/detail',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return DetailScreen(
            resourceDomain: extra['resource_domain'] as String? ?? '',
            vodId: extra['vod_id'] as int? ?? 0,
            groupKey: extra['group_key'] as String?,
            groupName: extra['name'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/play',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return PlayerScreen(
            resourceDomain: extra['resource_domain'] as String? ?? '',
            vodId: extra['vod_id'] as int? ?? 0,
            sourceIndex: extra['source_index'] as int? ?? 0,
            epIndex: extra['ep_index'] as int? ?? 0,
          );
        },
      ),
      GoRoute(path: '/about', builder: (context, state) => const AboutScreen()),
      GoRoute(
        path: '/admin-settings',
        builder: (context, state) => const AdminSettingsScreen(),
      ),
      GoRoute(
        path: '/qrcode-scan',
        builder: (context, state) => const QRCodeScanScreen(),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/downloads',
        builder: (context, state) => const DownloadScreen(),
      ),
      GoRoute(
        path: '/qrcode-display',
        builder: (context, state) => const QRCodeDisplayScreen(),
      ),
      GoRoute(
        path: '/user-agreement',
        builder: (context, state) => const UserAgreementScreen(),
      ),
      GoRoute(
        path: '/privacy-policy',
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
    ],
  );
});
