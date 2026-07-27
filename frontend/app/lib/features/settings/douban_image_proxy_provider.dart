import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/storage/secure_storage.dart';
import '../../shared/models/enums.dart';
import '../../shared/utils/image_utils.dart';

/// Sentinel for [DoubanImageProxyState.copyWith] nullable fields that need
/// to be cleared (set to null). Using `null` in copyWith would preserve the
/// old value due to the `?? this.field` pattern, so we use a sentinel object
/// to distinguish "not provided" from "explicitly set to null".
const _unset = Object();

class DoubanImageProxyState {
  final DoubanImageProxyMode mode;
  final String tempToken;
  final DateTime? tokenExpiresAt;

  const DoubanImageProxyState({
    this.mode = DoubanImageProxyMode.backend,
    this.tempToken = '',
    this.tokenExpiresAt,
  });

  DoubanImageProxyState copyWith({
    DoubanImageProxyMode? mode,
    String? tempToken,
    Object? tokenExpiresAt = _unset,
  }) =>
      DoubanImageProxyState(
        mode: mode ?? this.mode,
        tempToken: tempToken ?? this.tempToken,
        tokenExpiresAt: identical(tokenExpiresAt, _unset)
            ? this.tokenExpiresAt
            : tokenExpiresAt as DateTime?,
      );

  bool get shouldUseFrontendProxy => mode == DoubanImageProxyMode.frontend;

  /// 代理状态是否就绪，可用于决定是否渲染图片。
  ///
  /// - 前端代理模式：始终就绪（直接请求原始 URL + headers）
  /// - 后端代理模式：需要 tempToken 非空才算就绪
  bool get isReady {
    if (shouldUseFrontendProxy) return true;
    return tempToken.isNotEmpty;
  }

  /// 根据代理模式返回需要的 HTTP headers
  /// - 前端代理 + 豆瓣图片 → 返回 doubanHttpHeaders
  /// - 前端代理 + 资源站图片 → 返回 resourceHttpHeaders（设置 Referer 防盗链）
  /// - 后端代理 → 返回 null（由后端代理处理）
  /// - 非远程图片 → 返回 null
  Map<String, String>? httpHeadersForUrl(String url) {
    if (!shouldUseFrontendProxy) return null;
    if (!ImageUtils.isRemoteImageUrl(url)) return null;
    if (ImageUtils.isDoubanImageUrl(url)) return ImageUtils.doubanHttpHeaders;
    // 资源站图片：前端代理模式下设置 Referer 头绕过防盗链
    return ImageUtils.resourceHttpHeaders(url);
  }

  /// 根据代理模式构建正确的图片 URL。
  /// - 后端代理 + 豆瓣图片：返回豆瓣代理 URL（含 token）
  /// - 后端代理 + 资源站图片：返回资源站代理 URL `/api/resource/image/proxy?url=...`
  /// - 前端代理 + 任意图片：返回原始 URL，调用方应配合 [httpHeadersForUrl] 设置 headers
  /// - 非远程图片：返回原始 URL
  String buildImageUrl(String originalUrl, String baseUrl) {
    if (originalUrl.isEmpty) return '';
    if (!ImageUtils.isRemoteImageUrl(originalUrl)) return originalUrl;

    // 豆瓣图片处理
    if (ImageUtils.isDoubanImageUrl(originalUrl)) {
      if (shouldUseFrontendProxy) return originalUrl;
      return ImageUtils.buildDoubanImageUrl(
        originalUrl: originalUrl,
        tempToken: tempToken,
        baseUrl: baseUrl,
        proxyMode: DoubanImageProxyMode.backend,
      );
    }

    // 资源站图片处理
    if (shouldUseFrontendProxy) return originalUrl;
    // 后端代理模式：走资源站图片代理接口
    return ImageUtils.buildResourceImageProxyUrl(
      originalUrl: originalUrl,
      baseUrl: baseUrl,
    );
  }
}

/// 图片代理模式配置 — 代理模式选择仅保存在前端本地存储，不从后台查询。
/// 后端代理模式仍需通过 API 获取临时 tempToken 用于构建代理 URL。
class DoubanImageProxyNotifier extends StateNotifier<DoubanImageProxyState> {
  final SecureStorageService _storage;
  final ApiClient _api;

  /// 提前过期缓冲时间，与 Web 端 tempToken.ts 的 30s buffer 对齐，
  /// 避免 token 在服务端已失效但客户端仍认为有效的边界问题。
  static const _tokenBuffer = Duration(seconds: 30);

  /// 并发去重标志：防止多个页面同时调用 init/ensureTokenLoaded/getCachedToken
  /// 时发出重复的 token 刷新请求。
  bool _isRefreshing = false;

  DoubanImageProxyNotifier(this._storage, this._api)
      : super(const DoubanImageProxyState());

  /// 从持久化加载代理模式设置
  Future<void> loadMode() async {
    final saved = await _storage.getDoubanImageProxyMode();
    final mode = DoubanImageProxyMode.fromString(saved);
    state = state.copyWith(mode: mode);
  }

  /// 一次性初始化：加载代理模式 + 确保 token 就绪。
  ///
  /// 应在首页、收藏页等需要展示豆瓣图片的页面 initState 中调用，
  /// 替代单独调用 [loadMode] + [ensureTokenLoaded]，避免两者并行执行
  /// 导致的时序竞争（数据先于 token 就绪，buildImageUrl 回退到原始 URL）。
  Future<void> init() async {
    await loadMode();
    if (state.mode == DoubanImageProxyMode.backend) {
      await ensureTokenLoaded();
    }
  }

  /// 切换代理模式
  Future<void> setMode(DoubanImageProxyMode mode) async {
    await _storage.setDoubanImageProxyMode(mode.toStorageString());
    state = state.copyWith(mode: mode);
  }

  /// 确保后端代理模式下的 tempToken 已加载。
  /// 应在首页、收藏页等需要展示豆瓣图片的页面 initState 中调用。
  Future<void> ensureTokenLoaded() async {
    if (state.mode == DoubanImageProxyMode.backend &&
        (state.tempToken.isEmpty ||
            state.tokenExpiresAt == null ||
            _isTokenExpiringSoon)) {
      await _refreshToken();
    }
  }

  /// 获取缓存的 tempToken，如果过期或不存在则刷新。
  /// 仅在后端代理模式下使用。
  Future<String> getCachedToken() async {
    if (state.tempToken.isNotEmpty &&
        state.tokenExpiresAt != null &&
        !_isTokenExpiringSoon) {
      return state.tempToken;
    }
    return _refreshToken();
  }

  /// 检查 token 是否即将过期，如果是则异步刷新。
  /// 应在 UI build 中 ref.watch(doubanImageProxyProvider) 后调用，
  /// 刷新完成后 state 变化会自动触发 UI 重建。
  void checkAndRefresh() {
    if (state.mode == DoubanImageProxyMode.backend &&
        state.tempToken.isNotEmpty &&
        state.tokenExpiresAt != null &&
        _isTokenExpiringSoon) {
      _refreshToken(); // 异步，不 await — 刷新完成后 state 更新触发 UI 重建
    }
  }

  /// Token 是否即将过期（已过有效期的缓冲时间）。
  bool get _isTokenExpiringSoon =>
      state.tokenExpiresAt != null &&
      state.tokenExpiresAt!.subtract(_tokenBuffer).isBefore(DateTime.now());

  Future<String> _refreshToken() async {
    // 并发去重：已有刷新请求进行中，直接返回当前 token
    if (_isRefreshing) return state.tempToken;
    _isRefreshing = true;
    try {
      final resp = await _api.post<Map<String, dynamic>>(
        ApiConstants.tempToken,
      );
      final data = resp.data!;
      final inner = data['data'] as Map<String, dynamic>? ?? data;
      final token = inner['token'] as String? ?? '';
      final expiresIn = inner['expires_in'] as int? ?? 300;
      if (token.isNotEmpty) {
        state = state.copyWith(
          tempToken: token,
          // 提前 _tokenBuffer 视为过期，与 Web 端对齐
          tokenExpiresAt:
              DateTime.now().add(Duration(seconds: expiresIn) - _tokenBuffer),
        );
      }
      return token;
    } catch (_) {
      // 刷新失败：清空 token 并清除过期时间，确保下次 ensureTokenLoaded
      // 能正确检测到需要刷新（而非因 tokenExpiresAt 仍为旧值而跳过）
      state = state.copyWith(
        tempToken: '',
        tokenExpiresAt: null,
      );
      return '';
    } finally {
      _isRefreshing = false;
    }
  }
}

final doubanImageProxyProvider =
    StateNotifierProvider<DoubanImageProxyNotifier, DoubanImageProxyState>(
  (ref) {
    final storage = SecureStorageService.instance;
    final api = ref.read(apiClientProvider);
    return DoubanImageProxyNotifier(storage, api);
  },
);
