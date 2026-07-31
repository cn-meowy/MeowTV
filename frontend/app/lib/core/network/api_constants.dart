/// API path constants — aligned with backend router.go and Web constants/api.ts.
class ApiConstants {
  ApiConstants._();

  // ---------- Auth ----------
  static const login = '/api/auth/login';
  static const refresh = '/api/auth/refresh';
  static const logout = '/api/auth/logout';
  static const qrcodeRequest = '/api/auth/qrcode/request';
  static const qrcodePoll = '/api/auth/qrcode/poll';
  static const qrcodeScan = '/api/auth/qrcode/scan';

  // ---------- User ----------
  static const userProfile = '/api/user/profile';
  static const userUpdate = '/api/user/update';
  static const userPassword = '/api/user/password';
  static const userDevices = '/api/user/devices';
  static const userKickDevice = '/api/user/kick-device';
  // 普通用户只读系统配置（复用 AdminConfig.List handler，router.go 注册于 /api/user/config/list）
  static const userConfigList = '/api/user/config/list';

  // ---------- Resource ----------
  static const resourceSites = '/api/resource/sites';
  static const resourceSearch = '/api/resource/search'; // SSE POST
  static const resourceDetail = '/api/resource/detail';
  static const resourcePaginate = '/api/resource/paginate';
  static const resourceImageProxy = '/api/resource/image/proxy'; // GET

  // ---------- Douban ----------
  static const doubanSubjects = '/api/douban/subjects';
  static const doubanTags = '/api/douban/tags';
  static const doubanImageProxy = '/api/douban/image/proxy'; // GET

  // ---------- Temp Token ----------
  // 通用临时 Token（用于图片代理、流代理等 URL 传参认证，替代 JWT 在 URL 中暴露）
  // 与 Web 端 API.TOKEN_TEMP 对齐，后端端点 POST /api/token/temp（需 JWT 认证）
  static const tempToken = '/api/token/temp';

  // ---------- User Data — Search History ----------
  static const searchHistoryList = '/api/user/data/search-history/list';
  static const searchHistoryAdd = '/api/user/data/search-history/add';
  static const searchHistoryDelete = '/api/user/data/search-history/delete';
  static const searchHistoryClear = '/api/user/data/search-history/clear';

  // ---------- User Data — Play History ----------
  static const playHistoryList = '/api/user/data/play-history/list';
  static const playHistoryGet = '/api/user/data/play-history/get';
  static const playHistoryUpsert = '/api/user/data/play-history/upsert';
  static const playHistoryProgress = '/api/user/data/play-history/progress';
  static const playHistoryDelete = '/api/user/data/play-history/delete';
  static const playHistoryClear = '/api/user/data/play-history/clear';

  // ---------- User Data — Favorites ----------
  static const favoritesList = '/api/user/data/favorites/list';
  static const favoritesAdd = '/api/user/data/favorites/add';
  static const favoritesRemove = '/api/user/data/favorites/remove';
  static const favoritesToggle = '/api/user/data/favorites/toggle';
  static const favoritesCheck = '/api/user/data/favorites/check';
  static const favoritesClear = '/api/user/data/favorites/clear';

  // ---------- Download — User ----------
  static const downloadCreate = '/api/download/create';
  static const downloadList = '/api/download/list';
  static const downloadCancel = '/api/download/cancel';
  static const downloadDelete = '/api/download/delete';
  static const downloadRetry = '/api/download/retry';
  static const downloadCheck = '/api/download/check';
  static const downloadFile = '/api/download/file'; // GET  /file/:id

  // ---------- Admin — User ----------
  static const adminUserCreate = '/api/admin/user/create';
  static const adminUserUpdate = '/api/admin/user/update';
  static const adminUserResetPassword = '/api/admin/user/reset-password';
  static const adminUserList = '/api/admin/user/list';
  static const adminUserDelete = '/api/admin/user/delete';
  static const adminUserKick = '/api/admin/user/kick';

  // ---------- Admin — Config ----------
  static const adminConfigList = '/api/admin/config/list';
  static const adminConfigCreate = '/api/admin/config/create';
  static const adminConfigUpdate = '/api/admin/config/update';
  static const adminConfigDelete = '/api/admin/config/delete';
  static const adminConfigRefreshCache = '/api/admin/config/refresh-cache';

  // ---------- Admin — Group ----------
  static const adminGroupCreate = '/api/admin/group/create';
  static const adminGroupUpdate = '/api/admin/group/update';
  static const adminGroupDelete = '/api/admin/group/delete';
  static const adminGroupList = '/api/admin/group/list';
  static const adminGroupDetail = '/api/admin/group/detail';
  static const adminGroupSetResources = '/api/admin/group/set-resources';
  static const adminGroupSetUser = '/api/admin/group/set-user';

  // ---------- Admin — Resource Subscribe ----------
  static const adminResourceSubscribeConfig = '/api/admin/resource/subscribe/config';
  static const adminResourceSubscribeUpdate = '/api/admin/resource/subscribe/update';
  static const adminResourceSubscribeFetch = '/api/admin/resource/subscribe/fetch';
  static const adminResourceProxyTest = '/api/admin/resource/proxy/test';

  // ---------- Admin — Download ----------
  static const adminDownloadList = '/api/admin/download/list';
  static const adminDownloadConfig = '/api/admin/download/config';
  static const adminDownloadConfigUpdate = '/api/admin/download/config/update';

  // ---------- Stream ----------
  static const streamCheck = '/api/stream/check'; // POST 批量检测 m3u8 链接可用性
}
