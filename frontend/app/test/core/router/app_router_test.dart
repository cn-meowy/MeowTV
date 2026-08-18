import 'package:flutter_test/flutter_test.dart';
import 'package:meowtv_mobile/core/router/app_router.dart';
import 'package:meowtv_mobile/features/auth/auth_provider.dart';
import 'package:meowtv_mobile/shared/models/user_profile.dart';

void main() {
  // Build an AuthState for the scenarios under test. role is only
  // relevant for the logged-in admin-settings branch.
  AuthState state({
    bool isInitializing = false,
    bool isLoggedIn = false,
    bool hasAcceptedAgreements = false,
    int? role,
  }) {
    return AuthState(
      isInitializing: isInitializing,
      isLoggedIn: isLoggedIn,
      hasAcceptedAgreements: hasAcceptedAgreements,
      profile: role == null
          ? null
          : UserProfile(
              id: 1,
              username: 'u',
              nickname: 'n',
              avatar: '',
              role: role,
              status: 1,
            ),
    );
  }

  group('routeRedirect — agreement detail pages during onboarding', () {
    // Regression for: tapping 用户协议 / 隐私政策 on the agreements screen
    // (before accepting) redirected back to /start instead of opening the
    // detail page.
    test('unaccepted: /user-agreement is allowed (no redirect)', () {
      final s = state(hasAcceptedAgreements: false);
      expect(routeRedirect(s, '/user-agreement'), isNull);
    });

    test('unaccepted: /privacy-policy is allowed (no redirect)', () {
      final s = state(hasAcceptedAgreements: false);
      expect(routeRedirect(s, '/privacy-policy'), isNull);
    });
  });

  group('routeRedirect — onboarding flow preserved', () {
    test('unaccepted: splash redirects to /start', () {
      expect(routeRedirect(state(), '/'), '/start');
    });

    test('unaccepted: /start stays', () {
      expect(routeRedirect(state(), '/start'), isNull);
    });

    test('unaccepted: /agreements stays', () {
      expect(routeRedirect(state(), '/agreements'), isNull);
    });

    test('unaccepted: /login redirects to /start', () {
      expect(routeRedirect(state(), '/login'), '/start');
    });

    test('unaccepted: protected page redirects to /start', () {
      expect(routeRedirect(state(), '/home'), '/start');
    });
  });

  group('routeRedirect — initializing', () {
    test('any non-root path redirects to /', () {
      expect(
        routeRedirect(state(isInitializing: true), '/user-agreement'),
        '/',
      );
      expect(routeRedirect(state(isInitializing: true), '/home'), '/');
    });

    test('root stays', () {
      expect(routeRedirect(state(isInitializing: true), '/'), isNull);
    });
  });

  group('routeRedirect — agreements accepted, not logged in', () {
    final s = state(hasAcceptedAgreements: true);

    test('splash/start/agreements redirect to /login', () {
      expect(routeRedirect(s, '/'), '/login');
      expect(routeRedirect(s, '/start'), '/login');
      expect(routeRedirect(s, '/agreements'), '/login');
    });

    test('/login stays', () {
      expect(routeRedirect(s, '/login'), isNull);
    });

    test('agreement detail pages stay (can be reviewed from login)', () {
      expect(routeRedirect(s, '/user-agreement'), isNull);
      expect(routeRedirect(s, '/privacy-policy'), isNull);
    });

    test('protected page redirects to /login', () {
      expect(routeRedirect(s, '/home'), '/login');
    });

    test('public page (about) stays', () {
      expect(routeRedirect(s, '/about'), isNull);
    });
  });

  group('routeRedirect — logged in', () {
    final s = state(isLoggedIn: true, hasAcceptedAgreements: true);

    test('splash/start/agreements/login redirect to /home', () {
      expect(routeRedirect(s, '/'), '/home');
      expect(routeRedirect(s, '/start'), '/home');
      expect(routeRedirect(s, '/agreements'), '/home');
      expect(routeRedirect(s, '/login'), '/home');
    });

    test('protected page stays', () {
      expect(routeRedirect(s, '/home'), isNull);
      expect(routeRedirect(s, '/profile'), isNull);
    });

    test('agreement detail pages stay (viewable from profile)', () {
      expect(routeRedirect(s, '/user-agreement'), isNull);
      expect(routeRedirect(s, '/privacy-policy'), isNull);
    });

    test('non-admin user accessing /admin-settings redirects to /home', () {
      final nonAdmin = state(
        isLoggedIn: true,
        hasAcceptedAgreements: true,
        role: 0,
      );
      expect(routeRedirect(nonAdmin, '/admin-settings'), '/home');
    });

    test('admin user accessing /admin-settings stays', () {
      final admin = state(
        isLoggedIn: true,
        hasAcceptedAgreements: true,
        role: 1,
      );
      expect(routeRedirect(admin, '/admin-settings'), isNull);
    });
  });
}
