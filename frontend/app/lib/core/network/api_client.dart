import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_constants.dart';
import '../storage/secure_storage.dart';
import '../logger/app_logger.dart';

/// Dio-based HTTP client with automatic token refresh.
class ApiClient {
  /// Callback invoked when token refresh fails, signalling the auth layer
  /// to force-logout the user and redirect to the login screen.
  Future<void> Function()? onAuthFailure;

  /// Callback invoked when a connection-level error occurs
  /// (server unreachable, timeout, etc.). The auth layer should notify
  /// the user before force-logout.
  Future<void> Function()? onConnectionError;

  ApiClient({this.onAuthFailure}) {
    _dio = Dio(BaseOptions(
      baseUrl: 'http://localhost:8080', // TODO: configurable
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(_authInterceptor());
    _dio.interceptors.add(LogInterceptor(
      request: true,
      requestBody: true,
      requestHeader: true,
      responseBody: true,
      responseHeader: true,
      error: true,
      logPrint: (o) => appLogger.d(o),
    ));
  }

  late final Dio _dio;
  bool _isRefreshing = false;
  bool _refreshFailed = false;
  bool _logoutNotified = false;
  int _refreshCount = 0;
  static const _maxRefreshCount = 2;
  final List<_RetryRequest> _pendingRequests = [];

  /// Global CancelToken used to cancel all in-flight requests when
  /// force-logout is triggered, preventing stale 401s from starting
  /// yet another refresh cycle.
  CancelToken? _globalCancelToken = CancelToken();

  // ---------- Public helpers ----------

  /// Current base URL.
  String get baseUrl => _dio.options.baseUrl;

  /// Change base URL at runtime (e.g. after settings change).
  void setBaseUrl(String url) {
    appLogger.i('ApiClient baseUrl set to: $url');
    _dio.options.baseUrl = url;
  }

  /// Reset the refresh-failure and logout-notified flags so that future
  /// 401s will attempt token refresh again. Must be called after a
  /// successful login.
  void resetRefreshState() {
    _refreshFailed = false;
    _logoutNotified = false;
    _refreshCount = 0;
    // Create a fresh CancelToken so new requests are not immediately cancelled.
    _globalCancelToken = CancelToken();
  }

  /// Cancel all in-flight Dio requests.
  ///
  /// Called during [_clearTokensAndNotify] to ensure that requests
  /// dispatched before the logout (e.g. HomeScreen.loadData()) are
  /// cancelled before they can return 401 and trigger another refresh.
  void cancelAllRequests() {
    _globalCancelToken?.cancel('force logout');
    _globalCancelToken = CancelToken();
  }

  // ---------- HTTP methods ----------

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParams}) =>
      _dio.get<T>(path, queryParameters: queryParams, cancelToken: _globalCancelToken);

  Future<Response<T>> post<T>(String path, {dynamic data}) =>
      _dio.post<T>(path, data: data, cancelToken: _globalCancelToken);

  Future<Response<T>> put<T>(String path, {dynamic data}) =>
      _dio.put<T>(path, data: data, cancelToken: _globalCancelToken);

  Future<Response<T>> delete<T>(String path, {dynamic data}) =>
      _dio.delete<T>(path, data: data, cancelToken: _globalCancelToken);

  /// Post without auth — skips Authorization header injection AND
  /// the [_refreshFailed]/[_logoutNotified] short-circuit check.
  /// Also does NOT use the global CancelToken, so the request survives
  /// a [cancelAllRequests] call during force-logout.
  ///
  /// Use for auth endpoints (login, qrcode) that must work even when
  /// the previous session's tokens are known to be invalid.
  Future<Response<T>> postNoAuth<T>(String path, {dynamic data}) =>
      _dio.post<T>(path, data: data, options: Options(extra: {_noAuthExtra: true}));

  /// Post with streaming response (for SSE).
  ///
  /// Uses a long receiveTimeout (5 minutes) because SSE connections are
  /// long-lived — the server sends events incrementally and the standard
  /// 30-second receiveTimeout would kill the stream prematurely.
  Future<Response<ResponseBody>> postStream(
    String path, {
    dynamic data,
    CancelToken? cancelToken,
  }) async {
    final token = await SecureStorageService.instance.getAccessToken();
    return _dio.post<ResponseBody>(
      path,
      data: data,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(minutes: 5),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ),
    );
  }

  // ---------- Auth interceptor ----------

  /// Extra key used to mark requests that should skip auth header injection
  /// AND the _refreshFailed/_logoutNotified short-circuit check
  /// (e.g. the refresh-token request itself, or the login request).
  static const _noAuthExtra = 'noAuth';

  Interceptor _authInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        // If the request is marked noAuth, skip ALL auth checks —
        // no Authorization header, no _refreshFailed/_logoutNotified
        // rejection.  This is essential for login/refresh/qrcode
        // requests which must work even when the previous session's
        // tokens are known to be invalid.
        if (options.extra[_noAuthExtra] == true) {
          options.headers.remove('Authorization');
          handler.next(options);
          return;
        }

        // If token is known to be invalid (refresh failed or logout already
        // notified), reject the request immediately instead of letting it
        // reach the server and trigger yet another 401 → refresh → fail loop.
        // NOTE: login/refresh/qrcode requests are excluded above via _noAuthExtra.
        if (_refreshFailed || _logoutNotified) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.unknown,
            error: 'Token expired, login required',
          ));
          return;
        }

        final token = await SecureStorageService.instance.getAccessToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // If a noAuth request (login/refresh/qrcode) returned 401, it
          // means the endpoint itself rejected the request (e.g. wrong
          // password), NOT that an existing token expired.  Skip the
          // refresh-retry logic and pass the error through directly —
          // otherwise the interceptor would incorrectly trigger token
          // refresh and force-logout on a simple login failure.
          if (error.requestOptions.extra[_noAuthExtra] == true) {
            handler.reject(error);
            return;
          }

          // If the refresh endpoint itself returned 401, the refresh token
          // is also invalid — directly trigger force-logout without trying
          // to refresh again (prevents infinite recursion).
          if (error.requestOptions.path == ApiConstants.refresh) {
            appLogger.w('Refresh token is invalid (401), forcing logout');
            _refreshFailed = true;
            await _clearTokensAndNotify();
            handler.reject(error);
            return;
          }

          // If a previous refresh already failed, short-circuit to avoid
          // infinite retry loops — just reject and trigger logout.
          if (_refreshFailed) {
            appLogger.w('Token refresh previously failed, short-circuiting 401');
            await _clearTokensAndNotify();
            handler.reject(error);
            return;
          }

          // Guard against refresh loops: if we've already refreshed more than
          // _maxRefreshCount times and the retried request still returns 401,
          // the new token is not being accepted — stop retrying and force logout.
          if (_refreshCount >= _maxRefreshCount) {
            appLogger.w('Max refresh count ($_refreshCount) exceeded, forcing logout');
            _refreshFailed = true;
            await _clearTokensAndNotify();
            handler.reject(error);
            return;
          }

          _refreshCount++;
          final newToken = await _refreshToken();
          if (newToken != null) {
            // Retry the failed request
            final opts = error.requestOptions;
            opts.headers['Authorization'] = 'Bearer $newToken';
            try {
              final response = await _dio.fetch(opts);
              _refreshCount = 0; // Reset on successful retry
              handler.resolve(response);
            } on DioException catch (e) {
              handler.reject(e);
            }
          } else {
            // Refresh failed — clear tokens and notify auth layer to force logout
            _refreshFailed = true;
            await _clearTokensAndNotify();
            handler.reject(error);
          }
        } else if (_isConnectionError(error)) {
          // Connection-level error: server unreachable, notify auth layer to show message then logout
          appLogger.e('Connection error: type=${error.type}, '
              'msg=${error.message}, baseUrl=${_dio.options.baseUrl}');
          appLogger.w('Server unreachable, triggering connection error handler');
          await onConnectionError?.call();
          handler.reject(error);
        } else {
          handler.reject(error);
        }
      },
    );
  }

  Future<String?> _refreshToken() async {
    if (_isRefreshing) {
      // Another refresh is in progress — wait for it
      final completer = Completer<String?>();
      _pendingRequests.add(_RetryRequest(completer));
      return completer.future;
    }
    _isRefreshing = true;

    try {
      final refreshToken = await SecureStorageService.instance.getRefreshToken();
      if (refreshToken == null) {
        appLogger.w('Refresh token is null, skipping refresh attempt');
        return null;
      }

      final response = await _dio.post<Map<String, dynamic>>(
        ApiConstants.refresh,
        data: {'refresh_token': refreshToken},
        options: Options(extra: {_noAuthExtra: true}),
      );

      final data = response.data;
      if (data != null && (data['code'] == 200 || data['code'] == 0)) {
        final newAccess = data['data']['access_token'] as String?;
        final newRefresh = data['data']['refresh_token'] as String?;
        if (newAccess != null) {
          await SecureStorageService.instance.setAccessToken(newAccess);
          if (newRefresh != null) {
            await SecureStorageService.instance.setRefreshToken(newRefresh);
          }
          // Resolve pending requests
          for (final p in _pendingRequests) {
            p.completer.complete(newAccess);
          }
          _pendingRequests.clear();
          return newAccess;
        }
      }
      // Refresh failed
      for (final p in _pendingRequests) {
        p.completer.complete(null);
      }
      _pendingRequests.clear();
      return null;
    } catch (e) {
      appLogger.e('Token refresh error', error: e);
      for (final p in _pendingRequests) {
        p.completer.complete(null);
      }
      _pendingRequests.clear();
      return null;
    } finally {
      _isRefreshing = false;
    }
  }

  /// Clear locally stored tokens and notify the auth layer to force logout.
  ///
  /// This is the single point where tokens are purged on refresh failure,
  /// ensuring that subsequent requests will NOT carry a stale token and
  /// therefore will NOT trigger another 401 → refresh → fail loop.
  ///
  /// Guarded by [_logoutNotified] to prevent multiple concurrent 401s from
  /// triggering redundant force-logout calls (which would cause GoRouter
  /// redirect loops).
  Future<void> _clearTokensAndNotify() async {
    if (_logoutNotified) return;
    _logoutNotified = true;

    // Cancel all in-flight requests so they don't return 401 after
    // we've already decided to force-logout, which would start a
    // new refresh cycle.
    cancelAllRequests();

    await SecureStorageService.instance.removeAccessToken();
    await SecureStorageService.instance.removeRefreshToken();
    await onAuthFailure?.call();
  }

  /// Determines whether [error] is a connection-level error
  /// (server unreachable, timeout, etc.).
  bool _isConnectionError(DioException error) {
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        (error.error is SocketException);
  }
}

class _RetryRequest {
  final Completer<String?> completer;
  _RetryRequest(this.completer);
}

// ---------- Riverpod provider ----------

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
