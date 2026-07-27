/// URL normalization utilities for server address handling.
class UrlUtils {
  UrlUtils._();

  /// Normalize a server URL:
  /// - Trim whitespace
  /// - Remove trailing slashes
  /// - Ensure protocol prefix (default: https://)
  static String normalize(String url) {
    if (url.isEmpty) return url;

    var normalized = url.trim();

    // Remove trailing slashes
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    // Ensure protocol prefix
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }

    return normalized;
  }
}
