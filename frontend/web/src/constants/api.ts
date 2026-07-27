// ── API 路径常量 ──────────────────────────────────────────────────────────────

export const API = {
  // Auth
  AUTH_LOGIN: '/api/auth/login',
  AUTH_REFRESH: '/api/auth/refresh',
  AUTH_LOGOUT: '/api/auth/logout',
  AUTH_QRCODE_REQUEST: '/api/auth/qrcode/request',
  AUTH_QRCODE_POLL: '/api/auth/qrcode/poll',
  AUTH_QRCODE_SCAN: '/api/auth/qrcode/scan',

  // User
  USER_PROFILE: '/api/user/profile',
  USER_UPDATE: '/api/user/update',
  USER_PASSWORD: '/api/user/password',
  USER_DEVICES: '/api/user/devices',
  USER_KICK_DEVICE: '/api/user/kick-device',

  // Admin
  ADMIN_USER_CREATE: '/api/admin/user/create',
  ADMIN_USER_UPDATE: '/api/admin/user/update',
  ADMIN_USER_RESET_PASSWORD: '/api/admin/user/reset-password',
  ADMIN_USER_LIST: '/api/admin/user/list',
  ADMIN_USER_DELETE: '/api/admin/user/delete',
  ADMIN_USER_KICK: '/api/admin/user/kick',

  // Admin - 用户组
  ADMIN_GROUP_LIST: '/api/admin/group/list',
  ADMIN_GROUP_CREATE: '/api/admin/group/create',
  ADMIN_GROUP_UPDATE: '/api/admin/group/update',
  ADMIN_GROUP_DELETE: '/api/admin/group/delete',
  ADMIN_GROUP_DETAIL: '/api/admin/group/detail',
  ADMIN_GROUP_SET_RESOURCES: '/api/admin/group/set-resources',
  ADMIN_GROUP_SET_USER: '/api/admin/group/set-user',

  // Admin - 系统配置
  ADMIN_CONFIG_LIST: '/api/admin/config/list',
  ADMIN_CONFIG_CREATE: '/api/admin/config/create',
  ADMIN_CONFIG_UPDATE: '/api/admin/config/update',
  ADMIN_CONFIG_DELETE: '/api/admin/config/delete',
  ADMIN_CONFIG_REFRESH_CACHE: '/api/admin/config/refresh-cache',

  // Admin - 资源订阅（特殊操作）
  ADMIN_RESOURCE_SUBSCRIBE_FETCH: '/api/admin/resource/subscribe/fetch',
  ADMIN_RESOURCE_PROXY_TEST: '/api/admin/resource/proxy/test',

  // Resource - 搜索 & 详情 & 分页 & 图片代理
  RESOURCE_SEARCH: '/api/resource/search',
  RESOURCE_DETAIL: '/api/resource/detail',
  RESOURCE_PAGINATE: '/api/resource/paginate',
  RESOURCE_IMAGE_PROXY: '/api/resource/image/proxy',
  RESOURCE_SITES: '/api/resource/sites',

  // Douban
  DOUBAN_SUBJECTS: '/api/douban/subjects',
  DOUBAN_TAGS: '/api/douban/tags',
  DOUBAN_IMAGE_PROXY: '/api/douban/image/proxy',

  // User Data - 搜索历史
  SEARCH_HISTORY_LIST: '/api/user/data/search-history/list',
  SEARCH_HISTORY_ADD: '/api/user/data/search-history/add',
  SEARCH_HISTORY_DELETE: '/api/user/data/search-history/delete',
  SEARCH_HISTORY_CLEAR: '/api/user/data/search-history/clear',

  // User Data - 播放历史
  PLAY_HISTORY_GET: '/api/user/data/play-history/get',
  PLAY_HISTORY_LIST: '/api/user/data/play-history/list',
  PLAY_HISTORY_UPSERT: '/api/user/data/play-history/upsert',
  PLAY_HISTORY_PROGRESS: '/api/user/data/play-history/progress',
  PLAY_HISTORY_DELETE: '/api/user/data/play-history/delete',
  PLAY_HISTORY_CLEAR: '/api/user/data/play-history/clear',

  // User Data - 收藏
  FAVORITES_LIST: '/api/user/data/favorites/list',
  FAVORITES_ADD: '/api/user/data/favorites/add',
  FAVORITES_REMOVE: '/api/user/data/favorites/remove',
  FAVORITES_TOGGLE: '/api/user/data/favorites/toggle',
  FAVORITES_CHECK: '/api/user/data/favorites/check',
  FAVORITES_CLEAR: '/api/user/data/favorites/clear',

  // Download - 用户端
  DOWNLOAD_CREATE: '/api/download/create',
  DOWNLOAD_LIST: '/api/download/list',
  DOWNLOAD_CANCEL: '/api/download/cancel',
  DOWNLOAD_DELETE: '/api/download/delete',
  DOWNLOAD_RETRY: '/api/download/retry',
  DOWNLOAD_CHECK: '/api/download/check',
  DOWNLOAD_FILE: '/api/download/file',

  // Download - 管理端
  ADMIN_DOWNLOAD_LIST: '/api/admin/download/list',
  ADMIN_DOWNLOAD_CONFIG: '/api/admin/download/config',
  ADMIN_DOWNLOAD_CONFIG_UPDATE: '/api/admin/download/config/update',

  // Token - 临时 Token（用于 URL 传参认证，替代 JWT 在 URL 中暴露）
  TOKEN_TEMP: '/api/token/temp',

  // Stream - 流代理（m3u8 和 ts 请求使用临时 token 认证）
  STREAM_PROXY_M3U8: '/api/stream/proxy/m3u8',
  STREAM_PROXY_TS: '/api/stream/proxy/ts',
  STREAM_CHECK: '/api/stream/check',
} as const;