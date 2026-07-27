import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/logger/app_logger.dart';
import '../../core/utils/platform_util.dart';
import '../../shared/models/auth.dart';
import '../../shared/models/user_profile.dart';

export '../../core/storage/secure_storage.dart' show RememberedCredentials;

/// Sentinel value for [copyWith] nullable fields that need to be cleared.
///
/// Usage: `copyWith(username: _unset)` clears username to null,
/// while `copyWith()` (no argument) preserves the existing value.
const _unset = Object();

/// Auth state.
class AuthState {
  final bool isInitializing;
  final bool isLoggedIn;
  final bool hasSeenDisclaimer;
  final String? username;
  final UserProfile? profile;
  final String? baseUrl;

  const AuthState({
    this.isInitializing = true,
    this.isLoggedIn = false,
    this.hasSeenDisclaimer = false,
    this.username,
    this.profile,
    this.baseUrl,
  });

  /// Factory for the logged-out state, ensuring username/profile/baseUrl are
  /// explicitly cleared to null (unlike copyWith which cannot clear nullable fields).
  const AuthState.loggedOut({this.hasSeenDisclaimer = true})
      : isInitializing = false,
        isLoggedIn = false,
        username = null,
        profile = null,
        baseUrl = null;

  AuthState copyWith({
    bool? isInitializing,
    bool? isLoggedIn,
    bool? hasSeenDisclaimer,
    Object? username = _unset,
    Object? profile = _unset,
    Object? baseUrl = _unset,
  }) =>
      AuthState(
        isInitializing: isInitializing ?? this.isInitializing,
        isLoggedIn: isLoggedIn ?? this.isLoggedIn,
        hasSeenDisclaimer: hasSeenDisclaimer ?? this.hasSeenDisclaimer,
        username: identical(username, _unset)
            ? this.username
            : username as String?,
        profile: identical(profile, _unset)
            ? this.profile
            : profile as UserProfile?,
        baseUrl: identical(baseUrl, _unset)
            ? this.baseUrl
            : baseUrl as String?,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _apiClient;
  final SecureStorageService _storage;

  /// Guard against re-entrant [forceLogout] calls — multiple concurrent
  /// 401s can each trigger `_clearTokensAndNotify` → `forceLogout`, but
  /// only the first should actually execute the logout and set state.
  bool _isForceLoggingOut = false;

  AuthNotifier(this._apiClient, this._storage) : super(const AuthState());

  /// Initialise from persisted state.
  ///
  /// Validates the stored token **before** setting [AuthState.isLoggedIn].
  /// This prevents a cascade where GoRouter redirects to /home, triggering
  /// HomeScreen.loadData() → multiple concurrent API calls with an expired
  /// token → each 401 starts a refresh cycle → refresh/profile loop.
  Future<void> init() async {
    final token = await _storage.getAccessToken();
    final username = await _storage.read(key: 'username');
    final baseUrl = await _storage.read(key: 'server_base_url');
    final accepted = await _storage.hasSeenDisclaimer();

    if (!mounted) return;

    if (token != null && token.isNotEmpty && baseUrl != null && baseUrl.isNotEmpty) {
      _apiClient.setBaseUrl(baseUrl);

      // ── Validate token first ──────────────────────────────────────
      // Call fetchProfile() to verify the token is still valid.  Only
      // set isLoggedIn = true after successful validation, so GoRouter
      // never redirects to /home with an invalid token.
      bool tokenValid = false;
      try {
        await fetchProfile();
        tokenValid = true;
      } on DioException catch (e) {
        if (_isConnectionError(e)) {
          appLogger.w('Server unreachable during init');
          // Clear tokens so the next cold-start doesn't repeat this path
          await _storage.removeAccessToken();
          await _storage.removeRefreshToken();
          state = AuthState(
            isInitializing: false,
            hasSeenDisclaimer: accepted,
          );
          // Show snackbar
          final ctx = rootNavigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                content: Text('服务器连接失败，请检查网络或服务器地址'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        // 401 or other error: token is invalid.
        // The interceptor may have already called forceLogout() which
        // cleared tokens — we explicitly clear here as a safety net.
        appLogger.w('Token validation failed during init, clearing state');
        await _storage.removeAccessToken();
        await _storage.removeRefreshToken();
        state = AuthState(
          isInitializing: false,
          hasSeenDisclaimer: accepted,
        );
        return;
      }

      // ── Token is valid — safe to log in ───────────────────────────
      // fetchProfile() already set state with the profile via copyWith.
      // Now complete the state transition: isInitializing → false,
      // isLoggedIn → true, plus the stored username/baseUrl.
      if (tokenValid && mounted) {
        state = state.copyWith(
          isInitializing: false,
          isLoggedIn: true,
          hasSeenDisclaimer: accepted,
          username: username,
          baseUrl: baseUrl,
        );
      }
    } else {
      state = AuthState(
        isInitializing: false,
        hasSeenDisclaimer: accepted,
      );
    }
  }

  /// Mark disclaimer as seen (called from DisclaimerScreen).
  void setHasSeenDisclaimer() {
    state = state.copyWith(hasSeenDisclaimer: true);
  }

  /// Login.
  /// If [rememberMe] is true, the credentials (username, password, server, protocol)
  /// are AES-encrypted and saved to SecureStorage.
  Future<void> login(
    String serverUrl,
    String username,
    String password, {
    bool rememberMe = false,
    String protocol = 'https://',
  }) async {
    _apiClient.setBaseUrl(serverUrl);

    // 获取设备信息
    final deviceId = await PlatformUtil.getDeviceId();
    final deviceName = await PlatformUtil.getDeviceName();
    final deviceType = PlatformUtil.deviceType;

    // Use postNoAuth so the login request bypasses the _refreshFailed /
    // _logoutNotified short-circuit and is not cancelled by
    // cancelAllRequests() during force-logout.
    Response<Map<String, dynamic>> resp;
    try {
      resp = await _apiClient.postNoAuth<Map<String, dynamic>>(
        ApiConstants.login,
        data: LoginRequest(
          username: username,
          password: password,
          deviceType: deviceType,
          deviceId: deviceId,
          deviceName: deviceName,
        ).toJson(),
      );
    } on DioException catch (e) {
      // When the server returns HTTP 4xx (e.g. 400 for wrong password),
      // Dio throws a DioException. Extract the business error message
      // from the response body so the UI shows "用户名或密码错误"
      // instead of a raw DioException stack trace.
      final msg = _extractErrorMessage(e);
      throw Exception(msg);
    }

    final body = resp.data!;
    if (body['code'] != 200 && body['code'] != 0) {
      throw Exception(body['msg'] ?? 'Login failed');
    }

    final loginResp = LoginResponse.fromJson(body['data'] as Map<String, dynamic>);
    await _storage.setAccessToken(loginResp.accessToken);
    await _storage.setRefreshToken(loginResp.refreshToken);
    // Reset refresh-failure flag so future 401s will attempt token refresh
    _apiClient.resetRefreshState();
    await _storage.setLoggedIn(true);
    await _storage.write(key: 'username', value: username);
    await _storage.write(key: 'server_base_url', value: serverUrl);

    // Handle remember-me credentials
    if (rememberMe) {
      // Strip protocol prefix from serverUrl to get server address
      final serverAddress = serverUrl.replaceFirst(RegExp(r'^https?://'), '');
      await _storage.saveRememberedCredentials(
        username: username,
        password: password,
        server: serverAddress,
        protocol: protocol,
      );
    } else {
      // User unchecked remember-me — clear any previously saved credentials
      await _storage.clearRememberedCredentials();
    }

    if (!mounted) return;
    state = state.copyWith(isLoggedIn: true, username: username, baseUrl: serverUrl);
    try {
      await fetchProfile();
    } catch (_) {}
  }

  /// Logout (user-initiated).
  /// Clears login state but preserves remembered credentials so the user
  /// can log back in without re-entering credentials.
  Future<void> logout() async {
    try {
      await _apiClient.post(ApiConstants.logout);
    } catch (_) {}
    // Clear only login state — keep remembered credentials, disclaimer, theme, etc.
    await _storage.removeAccessToken();
    await _storage.removeRefreshToken();
    await _storage.delete(key: 'is_logged_in');
    await _storage.delete(key: 'username');
    await _storage.delete(key: 'server_base_url');
    state = AuthState.loggedOut();
  }

  /// Force logout triggered by token refresh failure.
  /// Clears local state but skips the server logout call (token is already invalid).
  /// Preserves remembered credentials like [logout].
  Future<void> forceLogout() async {
    if (_isForceLoggingOut) return;
    _isForceLoggingOut = true;
    try {
      await _storage.removeAccessToken();
      await _storage.removeRefreshToken();
      await _storage.delete(key: 'is_logged_in');
      await _storage.delete(key: 'username');
      await _storage.delete(key: 'server_base_url');
      if (mounted) {
        state = AuthState.loggedOut();
      }
    } finally {
      _isForceLoggingOut = false;
    }
  }

  /// QR 码扫码登录成功回调（由 QRCodeDisplayNotifier 调用）。
  /// Token 已由调用方保存到 SecureStorage，此处只需更新 state。
  void onQRCodeLoginSuccess(String accessToken, String refreshToken) {
    if (!mounted) return;
    // Reset refresh-failure flag so future 401s will attempt token refresh
    _apiClient.resetRefreshState();
    // 获取当前 baseUrl（TV 端在请求码之前已设置）
    final baseUrl = _apiClient.baseUrl;
    state = state.copyWith(
      isLoggedIn: true,
      baseUrl: baseUrl,
    );
    // 异步获取 profile
    fetchProfile();
  }

  /// Returns remembered credentials if "Remember Me" was checked on the last
  /// successful login. Returns null if no credentials are stored.
  Future<RememberedCredentials?> getRememberedCredentials() =>
      _storage.getRememberedCredentials();

  /// Fetch user profile.
  Future<void> fetchProfile() async {
    try {
      final resp = await _apiClient.post<Map<String, dynamic>>(ApiConstants.userProfile);
      if (!mounted) return;
      final body = resp.data!;
      if (body['data'] != null) {
        final profile = UserProfile.fromJson(body['data'] as Map<String, dynamic>);
        state = state.copyWith(profile: profile);
      }
    } catch (e) {
      appLogger.e('Fetch profile error', error: e);
    }
  }

  /// Extract a human-readable error message from a [DioException].
  ///
  /// The backend returns errors as `{"code": 4xx, "msg": "错误描述"}`.
  /// When the HTTP status is 4xx, Dio throws a [DioException] and the
  /// response body is available via `e.response?.data`.  This helper
  /// parses the body to extract the `msg` field so the UI can display
  /// "用户名或密码错误" instead of a raw stack trace.
  String _extractErrorMessage(DioException e) {
    try {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        final msg = data['msg'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
      // Fallback: data might be a JSON string
      if (data is String && data.isNotEmpty) {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final msg = json['msg'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    // Final fallback: connection errors, timeout, etc.
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return '服务器连接失败，请检查网络或服务器地址';
    }
    return '请求失败 (${e.response?.statusCode ?? '未知错误'})';
  }

  /// Determines whether [e] is a connection-level error
  /// (server unreachable, timeout, etc.).
  bool _isConnectionError(DioException e) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        (e.error is SocketException);
  }
}

// ---------- Riverpod providers ----------

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  // Use ref.read — ApiClient is a stable singleton Provider.
  // Using ref.watch here would cause AuthNotifier to be disposed &
  // recreated whenever the dependency graph is re-evaluated, which
  // triggers AuthNotifierListenable → GoRouter refreshListenable →
  // navigation redirect → HomeScreen rebuild → loadData() again →
  // infinite loop.
  final apiClient = ref.read(apiClientProvider);
  final storage = SecureStorageService.instance;
  final notifier = AuthNotifier(apiClient, storage);
  // Wire up the auth-failure callback so that ApiClient can trigger
  // a force-logout when token refresh fails.
  apiClient.onAuthFailure = notifier.forceLogout;
  // Wire up connection error callback: show snackbar then force logout
  apiClient.onConnectionError = () async {
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('服务器连接失败，请检查网络或服务器地址'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    // Delay logout slightly to let user see the snackbar
    await Future.delayed(const Duration(milliseconds: 500));
    await notifier.forceLogout();
  };
  return notifier;
});
