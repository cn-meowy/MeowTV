import '../../core/logger/app_logger.dart';
import '../models/enums.dart';

/// Image URL building utilities.
class ImageUtils {
  ImageUtils._();

  /// 将豆瓣封面 URL 中的尺寸标识替换为原图路径
  /// s_ratio_poster / m_ratio_poster / l_ratio_poster → raw
  static String replaceToOriginal(String coverUrl) {
    if (coverUrl.isEmpty) return '';
    // const sizePatterns = ['s_ratio_poster', 'm_ratio_poster', 'l_ratio_poster'];
    const sizePatterns = ['s_ratio_poster', 'm_ratio_poster'];
    for (final pattern in sizePatterns) {
      final old = '/view/photo/$pattern/';
      if (coverUrl.contains(old)) {
        return coverUrl.replaceAll(old, '/view/photo/l_ratio_poster/');
      }
    }
    return coverUrl;
  }

  /// Whether the URL is a Douban image.
  static bool isDoubanImageUrl(String url) {
    return url.contains('douban.com') ||
        RegExp(r'img\d*\.douban', caseSensitive: false).hasMatch(url);
  }

  /// Whether the URL is a remote image that may need proxying
  /// (i.e. not a local asset, not a data URI, not already proxied).
  static bool isRemoteImageUrl(String url) {
    if (url.isEmpty) return false;
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /// HTTP headers for frontend proxy mode — bypass Douban hotlink protection.
  static const Map<String, String> doubanHttpHeaders = {
    'Referer': 'https://movie.douban.com/',
    "Accept": "application/json, text/plain, */*",
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  /// HTTP headers for frontend proxy mode — bypass resource site hotlink protection.
  static Map<String, String> resourceHttpHeaders(String originalUrl) {
    return {
      'Referer': originalUrl,
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
  }

  /// Build image URL based on proxy mode.
  ///
  /// - Backend proxy: returns full URL like `{baseUrl}/api/douban/image/proxy?url=...&token=...`
  /// - Frontend proxy: returns original URL; caller should set [doubanHttpHeaders]
  static String buildDoubanImageUrl({
    required String originalUrl,
    required String tempToken,
    required String baseUrl,
    DoubanImageProxyMode proxyMode = DoubanImageProxyMode.backend,
  }) {
    if (originalUrl.isEmpty) return '';
    if (!isDoubanImageUrl(originalUrl)) return originalUrl;

    if (proxyMode == DoubanImageProxyMode.frontend) {
      return originalUrl;
    }

    // Backend proxy mode
    if (tempToken.isEmpty) {
      appLogger.w('buildDoubanImageUrl: tempToken is empty, '
          'falling back to original URL (backend proxy will NOT be used). '
          'Ensure init() is awaited before rendering images.');
      return originalUrl;
    }
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$cleanBase/api/douban/image/proxy?url='
        '${Uri.encodeComponent(originalUrl)}&token=$tempToken';
  }

  /// Build resource site image proxy URL (backend proxy mode).
  ///
  /// Returns `{baseUrl}/api/resource/image/proxy?url=...`
  static String buildResourceImageProxyUrl({
    required String originalUrl,
    required String baseUrl,
  }) {
    if (originalUrl.isEmpty) return '';
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$cleanBase/api/resource/image/proxy?url='
        '${Uri.encodeComponent(originalUrl)}';
  }
}
