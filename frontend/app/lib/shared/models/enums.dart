/// Enums aligned with backend entity/enums.go and Web types/api.ts.
library;

/// User role.
enum UserRole { user, admin }

/// User status.
enum UserStatus { disabled, enabled }

/// Device type — values MUST match backend.
enum DeviceType { web, android, ios, appleTV }

/// Download status — 7 values matching backend.
enum DownloadStatus { queued, parsing, downloading, merging, completed, failed, cancelled }

/// App theme mode.
enum AppThemeMode { dark, light, system }

/// Douban image proxy mode.
enum DoubanImageProxyMode {
  backend,  // 后端代理 - 通过服务器转发
  frontend; // 前端代理 - 直接请求豆瓣 + 设置 Header

  /// 从存储值解析，默认 backend
  static DoubanImageProxyMode fromString(String? value) {
    switch (value) {
      case 'frontend': return DoubanImageProxyMode.frontend;
      default: return DoubanImageProxyMode.backend;
    }
  }

  /// 持久化用的字符串
  String toStorageString() => name;
}

/// 播放缓冲模式。
///
/// 方案A：HLS 标准缓冲 — 纯内存缓冲约 30s，退出后释放，无本地文件，适合临时观看。
/// 方案B：边播边下 — 缓存到磁盘 play_cache/，播放完成后保留，适合追剧/重复观看。
enum BufferMode {
  strategyA, // 方案A：HLS 标准缓冲
  strategyB; // 方案B：边播边下（默认）

  /// 从存储值解析，默认 strategyB（与文档规范一致）
  static BufferMode fromString(String? value) {
    switch (value) {
      case 'strategy_a':
        return BufferMode.strategyA;
      case 'strategy_b':
      default:
        return BufferMode.strategyB;
    }
  }

  /// 持久化用的字符串
  String toStorageString() {
    switch (this) {
      case BufferMode.strategyA:
        return 'strategy_a';
      case BufferMode.strategyB:
        return 'strategy_b';
    }
  }

  /// 显示标签
  String get label {
    switch (this) {
      case BufferMode.strategyA:
        return 'HLS 标准缓冲';
      case BufferMode.strategyB:
        return '边播边下';
    }
  }

  /// 描述说明
  String get description {
    switch (this) {
      case BufferMode.strategyA:
        return '纯内存缓冲约 30s，退出后释放，适合临时观看';
      case BufferMode.strategyB:
        return '边播边缓存到磁盘，播放完成后保留，适合追剧';
    }
  }
}

/// 缓冲清晰度偏好。
enum BufferQuality {
  auto,  // 自动
  p360,  // 360p
  p480,  // 480p
  p720,  // 720p
  p1080; // 1080p

  static BufferQuality fromString(String? value) {
    switch (value) {
      case '360p':
        return BufferQuality.p360;
      case '480p':
        return BufferQuality.p480;
      case '720p':
        return BufferQuality.p720;
      case '1080p':
        return BufferQuality.p1080;
      case 'auto':
      default:
        return BufferQuality.auto;
    }
  }

  String toStorageString() {
    switch (this) {
      case BufferQuality.auto:
        return 'auto';
      case BufferQuality.p360:
        return '360p';
      case BufferQuality.p480:
        return '480p';
      case BufferQuality.p720:
        return '720p';
      case BufferQuality.p1080:
        return '1080p';
    }
  }

  String get label {
    switch (this) {
      case BufferQuality.auto:
        return '自动';
      case BufferQuality.p360:
        return '360p';
      case BufferQuality.p480:
        return '480p';
      case BufferQuality.p720:
        return '720p';
      case BufferQuality.p1080:
        return '1080p';
    }
  }
}

/// 连播模式
enum PlayMode {
  autoNext,     // 自动连播（默认）
  pauseOnEnd,   // 播完暂停
  loopSingle;   // 单集循环

  static PlayMode fromString(String? value) {
    switch (value) {
      case 'pause_on_end':
        return PlayMode.pauseOnEnd;
      case 'loop_single':
        return PlayMode.loopSingle;
      case 'auto_next':
      default:
        return PlayMode.autoNext;
    }
  }

  String toStorageString() {
    switch (this) {
      case PlayMode.autoNext:
        return 'auto_next';
      case PlayMode.pauseOnEnd:
        return 'pause_on_end';
      case PlayMode.loopSingle:
        return 'loop_single';
    }
  }

  String get label {
    switch (this) {
      case PlayMode.autoNext:
        return '自动连播';
      case PlayMode.pauseOnEnd:
        return '播完暂停';
      case PlayMode.loopSingle:
        return '单集循环';
    }
  }
}
