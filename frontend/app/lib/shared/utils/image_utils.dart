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

  /// 基础判定：是否为本地文件路径（非 http/https scheme）。
  ///
  /// 这是 [isAbsolutePath] 与 [isRelativePath] 的共同前置条件。只要字符串非空
  /// 且不以 `http://` / `https://` 开头即视为本地文件路径——包括绝对路径
  /// （如 `/app/videos/我的吉他.jpg`）、相对路径（如 `videos/cover.jpg`）等。
  ///
  /// 后端 `ResourceImageService.isLocalFilePath` 使用 `os.Stat(imageURL)` 检查
  /// 文件存在性：绝对路径基于文件系统根解析，相对路径基于后端进程 CWD 解析，
  /// 因此两类路径均可由后端代理直读，前端只需原样透传。
  ///
  /// 注意：`data:` URI 也不以 http(s) 开头，会在此返回 `true`，故作为独立
  /// 判定使用时，应优先使用 [isAbsolutePath] / [isRelativePath]（后者已排除
  /// `data:` 前缀）。
  static bool isLocalFilePath(String url) {
    if (url.isEmpty) return false;
    if (url.startsWith('http://') || url.startsWith('https://')) return false;
    return true;
  }

  /// 是否为本地**绝对**路径：非 http(s) 且以 `/` 开头。
  ///
  /// 例如 `/app/videos/我的吉他.jpg`。后端基于文件系统根解析。
  static bool isAbsolutePath(String url) {
    return isLocalFilePath(url) && url.startsWith('/');
  }

  /// 是否为本地**相对**路径：非 http(s)、不以 `/` 开头、且非 `data:` URI。
  ///
  /// 例如 `videos/我的吉他.jpg`、`./cover.png`、`../assets/img.jpg`。
  /// 相对路径能否成功解析取决于后端进程的工作目录（CWD）与文件实际位置的
  /// 匹配关系——若后端 CWD 与数据目录不一致，相对路径会 404。
  static bool isRelativePath(String url) {
    return isLocalFilePath(url) &&
        !url.startsWith('/') &&
        !url.startsWith('data:');
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

  /// 构建演示模式本地封面图片的代理 URL。
  ///
  /// 支持本地**绝对路径**（如 `/app/videos/我的吉他.jpg`）与**相对路径**
  /// （如 `videos/我的吉他.jpg`），两者均通过同一代理接口
  /// `/api/resource/image/proxy?url=...&token=...` 透传给后端，由后端
  /// `ResourceImageService.ProxyImage` 调用 `os.Stat`/`os.ReadFile` 解析
  /// （绝对路径基于文件系统根，相对路径基于后端进程 CWD）。
  ///
  /// 返回 `{baseUrl}/api/resource/image/proxy?url=<encoded>&token=<tempToken>`。
  /// 当 `localPath` 为空时返回 `null`（调用方按"无法显示"处理）。
  /// 当 `tempToken` 为空时仍返回不带 token 的 URL（后端会返回 401），
  /// 以便从日志中看到请求确实发出，而非完全静默。
  static String? buildDemoImageProxyUrl({
    required String localPath,
    required String tempToken,
    required String baseUrl,
  }) {
    if (localPath.isEmpty) return null;
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = '$cleanBase/api/resource/image/proxy?url='
        '${Uri.encodeComponent(localPath)}';
    if (tempToken.isEmpty) {
      appLogger.w('buildDemoImageProxyUrl: tempToken is empty, '
          'returning URL without token (backend will return 401): $url');
      return url;
    }
    return '$url&token=$tempToken';
  }
}
