// ── 枚举（与后端 entity/enums.go 对齐） ─────────────────────────────────────

/** 用户角色 */
export enum UserRole {
  User = 0,   // 普通用户
  Admin = 1,  // 管理员
}

/** 用户状态 */
export enum UserStatus {
  Disabled = 0, // 禁用
  Enabled = 1,  // 启用
}

/** 设备类型 */
export enum DeviceType {
  Web = 0,      // Web 浏览器
  Android = 1,  // Android
  IOS = 2,      // iOS
  AppleTV = 3,  // Apple TV
}

// ── 统一响应 ────────────────────────────────────────────────────────────────

/** 后端统一响应格式 */
export interface ApiResponse<T = unknown> {
  code: number;
  msg: string;
  data: T;
}

/** 分页响应 */
export interface PaginatedData<T> {
  items: T[];
  total: number;
  page: number;
  size: number;
  total_pages: number;
}

// ── Auth 相关 ───────────────────────────────────────────────────────────────

/** 登录请求 */
export interface LoginReq {
  username: string;
  password: string;
  device_type: number;
  device_id: string;
  device_name: string;
}

/** 登录响应 */
export interface LoginResp {
  access_token: string;
  refresh_token: string;
  expires_in: number;
}

/** 刷新 Token 请求 */
export interface RefreshReq {
  refresh_token: string;
}

/** 刷新 Token 响应（同 LoginResp） */
export type RefreshResp = LoginResp;

// ── User 相关 ───────────────────────────────────────────────────────────────

/** 用户个人信息 */
export interface ProfileResp {
  id: number;
  username: string;
  nickname: string;
  avatar: string;
  role: number;
  status: number;
}

/** 修改个人信息请求 */
export interface UpdateProfileReq {
  nickname?: string;
  avatar?: string;
}

/** 修改密码请求 */
export interface ChangePasswordReq {
  old_password: string;
  new_password: string;
}

/** 设备信息 */
export interface DeviceInfo {
  device_id: string;
  device_name: string;
  device_type: number;
  last_active_at: number;
  online: boolean;
}

/** 在线设备列表响应 */
export interface DeviceListResp {
  devices: DeviceInfo[];
}

/** 踢掉设备请求 */
export interface KickDeviceReq {
  device_type: number;
}

// ── Admin 相关 ──────────────────────────────────────────────────────────────

/** 创建用户请求 */
export interface CreateUserReq {
  username: string;
  password: string;
  nickname?: string;
  role?: number;
}

/** 创建用户响应 */
export interface CreateUserResp {
  id: number;
  username: string;
  nickname: string;
  role: number;
}

/** 编辑用户请求 */
export interface UpdateUserReq {
  id: number;
  nickname?: string;
  avatar?: string;
  role?: number;
  status?: number;
}

/** 重置密码请求 */
export interface ResetPasswordReq {
  id: number;
  new_password: string;
}

/** 用户列表请求 */
export interface UserListReq {
  page: number;
  size: number;
  keyword?: string;
  role?: number;
  status?: number;
}

/** 用户列表项 */
export interface UserListItem {
  id: number;
  username: string;
  nickname: string;
  avatar: string;
  role: number;
  status: number;
  last_login_at: string | null;
  created_at: string;
}

/** 删除用户请求 */
export interface DeleteUserReq {
  id: number;
}

/** 踢用户下线请求 */
export interface KickUserReq {
  user_id: number;
  device_type?: number;
}

// ── QRCode 相关 ─────────────────────────────────────────────────────────────

/** 请求登录码请求 */
export interface QRCodeRequestReq {
  device_id: string;
  device_name: string;
  device_type: number;
}

/** 请求登录码响应 */
export interface QRCodeRequestResp {
  code: string;
  qr_url: string;
  expires_in: number;
}

/** 扫码确认请求 */
export interface QRCodeScanReq {
  code: string;
}

/** 轮询登录结果请求 */
export interface QRCodePollReq {
  code: string;
  device_id: string;
  device_name: string;
  device_type: number;
}

/** 轮询登录结果响应 */
export interface QRCodePollResp {
  status: 'waiting' | 'confirmed' | 'expired';
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
}

// ── Douban 相关 ──────────────────────────────────────────────────────────

/** 豆瓣分类列表请求参数 */
export interface DoubanSubjectsReq {
  type?: 'movie' | 'tv';
  tag?: string;
  sort?: 'recommend' | 'time' | 'rank';
  page_limit?: number;
  page_start?: number;
}

/** 豆瓣影视条目 - 原始豆瓣返回结构 */
export interface DoubanSubject {
  id: string;
  title: string;
  cover: string;
  rate: string;
  url: string;
  card_subtitle?: string;
  type?: string;
  tags?: string[];
}

/** 豆瓣分类列表响应 */
export interface DoubanSubjectsResp {
  subjects: DoubanSubject[];
  total: number;
  has_more: boolean;
}

/** 通用临时 Token 响应 */
export interface TempTokenResp {
  token: string;
  expires_in: number;
}

/** 豆瓣标签请求参数 */
export interface DoubanTagsReq {
  type: 'movie' | 'tv';
}

/** 豆瓣标签项 */
export interface DoubanTag {
  id: string;
  name: string;
  category?: string;
}

/** 豆瓣标签响应 */
export interface DoubanTagsResp {
  tags: string[];
}

// ── 用户组相关 ────────────────────────────────────────────────────────────

/** 用户组列表请求 */
export interface UserGroupListReq {
  page?: number;
  size?: number;
  keyword?: string;
}

/** 用户组列表项 */
export interface UserGroupItem {
  id: number;
  name: string;
  remark: string;
  user_count: number;
  resource_count: number;
  created_at: string;
}

/** 用户组列表响应 */
export interface UserGroupListResp {
  items: UserGroupItem[];
  total: number;
}

/** 创建用户组请求 */
export interface CreateUserGroupReq {
  name: string;
  remark?: string;
}

/** 更新用户组请求 */
export interface UpdateUserGroupReq {
  id: number;
  name?: string;
  remark?: string;
}

/** 删除用户组请求 */
export interface DeleteUserGroupReq {
  id: number;
}

/** 用户组详情响应 */
export interface GroupDetailResp {
  id: number;
  name: string;
  remark: string;
  config_keys: string[];
  resource_count: number;
  user_count: number;
  created_at: string;
  updated_at: string;
}

/** 设置用户组关联资源请求 */
export interface SetGroupResourcesReq {
  group_id: number;
  config_keys: string[];
}

/** 设置用户所属用户组请求 */
export interface SetUserGroupReq {
  user_id: number;
  group_id: number | null;
}

// ── 系统配置相关 ────────────────────────────────────────────────────────

/** 系统配置项 */
export interface SysConfigItem {
  id: number;
  config_key: string;
  config_group: string;
  title: string;
  title1: string;
  title2: string;
  title3: string;
  title4: string;
  title5: string;
  title6: string;
  value1: string;
  value2: string;
  value3: string;
  value4: string;
  value5: string;
  value6: string;
  sort_order: number;
  is_enabled: boolean;
  remark: string;
  created_at: string;
  updated_at: string;
}

/** 配置列表请求 */
export interface ConfigListReq {
  group: string;
}

/** 配置列表响应 */
export type ConfigListResp = SysConfigItem[];

/** 创建配置请求 */
export interface ConfigCreateReq {
  config_key: string;
  config_group: string;
  title?: string;
  title1?: string;
  title2?: string;
  title3?: string;
  title4?: string;
  title5?: string;
  title6?: string;
  value1?: string;
  value2?: string;
  value3?: string;
  value4?: string;
  value5?: string;
  value6?: string;
  sort_order?: number;
  is_enabled?: boolean;
  remark?: string;
}

/** 更新配置请求 */
export interface ConfigUpdateReq {
  config_key: string;
  title?: string;
  title1?: string;
  title2?: string;
  title3?: string;
  title4?: string;
  title5?: string;
  title6?: string;
  value1?: string;
  value2?: string;
  value3?: string;
  value4?: string;
  value5?: string;
  value6?: string;
  sort_order?: number;
  is_enabled?: boolean;
  remark?: string;
}

/** 删除配置请求 */
export interface ConfigDeleteReq {
  id: number;
}

/** 订阅拉取结果 */
export interface SubscribeFetchResp {
  total: number;
  added: number;
  updated: number;
  domains: string[];
}

// ── 搜索相关 ──────────────────────────────────────────────────────────────

/** 搜索请求 */
export interface SearchReq {
  q: string;
  douban_id?: string;
  resources: string[];
}

/** 搜索结果项 */
export interface SearchResultItem {
  vod_id?: number;
  resource_domain: string;
  resource_name: string;
  title: string;
  subtitle?: string;
  douban_id?: string;
  douban_score?: string;
  year?: string;
  type?: string;
  type_id_1?: number;
  genre?: string;
  cover?: string;
  actors?: string;
  director?: string;
  description?: string;
  remarks?: string;
  area?: string;
  lang?: string;
  score?: string;
  play_from?: string;
  play_url?: string;
}

/** 单个资源站搜索完成事件 */
export interface SearchDoneData {
  resource_domain: string;
  count: number;
}

/** 全部搜索完成事件 */
export interface SearchCompleteData {
  total: number;
}

/** 搜索错误事件 */
export interface SearchErrorData {
  resource_domain: string;
  message: string;
}

/** SSE 搜索事件类型 */
export type SearchEventType = 'result' | 'done' | 'complete' | 'error';

/** SSE 搜索事件 */
export interface SearchSSEEvent {
  type: SearchEventType;
  data: SearchResultItem | SearchDoneData | SearchCompleteData | SearchErrorData;
}

/** 资源站点（搜索下拉用） */
export interface ResourceSiteItem {
  domain: string;
  name: string;
  api: string;
  detail: string;
  comment?: string;
  cache_time?: number;
  is_enabled: boolean;
  is_adult: boolean;      // Value5=1 表示18禁
  searchable: boolean;    // Value6=0 表示不允许搜索
}

// ── 资源分页查询相关 ──────────────────────────────────────────────────────

/** 资源分页查询请求 */
export interface ResourcePageReq {
  page: number;
  page_size: number;
  keyword?: string;
  resource: string;
}

/** 资源分页查询响应 */
export interface ResourcePageResp {
  items: SearchResultItem[];
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
}

// ── 资源详情相关 ──────────────────────────────────────────────────────

/** 资源详情请求 */
export interface ResourceDetailReq {
  site: string;
  vod_id: number;
}

/** 资源详情响应 */
export interface ResourceDetailResp {
  vod_id: number;
  vod_name: string;
  vod_sub?: string;
  vod_pic?: string;
  vod_actor?: string;
  vod_director?: string;
  vod_blurb?: string;
  vod_content?: string;
  vod_remarks?: string;
  vod_area?: string;
  vod_lang?: string;
  vod_year?: string;
  vod_score?: string;
  vod_douban_id?: number;
  vod_douban_score?: string;
  vod_class?: string;
  vod_play_url?: string;
  vod_play_from?: string;
  type_name?: string;
  type_id_1?: number;
  resource_domain: string;
  resource_name: string;
}

/** 播放剧集 */
export interface PlayEpisode {
  name: string;
  url: string;
}

/** 播放源（一个资源站可能提供多个播放源，如"播放线路1"、"播放线路2"） */
export interface PlaySource {
  name: string;           // 播放源名称，如 "bfzym3u8"、"ffm3u8"
  episodes: PlayEpisode[];
}

// ── 用户数据（搜索历史 + 播放历史 + 收藏） ──────────────────────────────────

/** 搜索历史项 */
export interface SearchHistoryItem {
  id: number;
  keyword: string;
  updated_at: number; // unix ms
}

/** 播放历史项 */
export interface PlayHistoryItem {
  id: number;
  vod_id: number;
  vod_name: string;
  vod_pic: string;
  resource_domain: string;
  resource_name: string;
  group_key: string;
  source_index: number;
  ep_index: number;
  ep_name: string;
  progress: number;
  current_time: number;
  duration: number;
  created_at: number; // unix ms
  updated_at: number; // unix ms
}

/** 查询单条播放记录请求 */
export interface PlayHistoryGetReq {
  vod_id: number;
  resource_domain: string;
  ep_index: number;
}

/** 播放历史列表响应 */
export interface PlayHistoryListResp {
  total: number;
  items: PlayHistoryItem[];
}

/** 收藏项 */
export interface FavoriteItem {
  id: number;
  vod_id: number;
  vod_name: string;
  vod_pic: string;
  douban_id: string;
  group_key: string;
  site: string;
  resource_domain: string;
  resource_name: string;
  created_at: number; // unix ms
}

/** 收藏列表响应 */
export interface FavoriteListResp {
  total: number;
  items: FavoriteItem[];
}

/** 收藏检查响应 */
export interface FavoriteCheckResp {
  is_favorite: boolean;
}

// ── 下载模块 ────────────────────────────────────────────────────────────────

/** 下载状态枚举 */
export enum DownloadStatus {
  Queued = 0,
  Parsing = 1,
  Downloading = 2,
  Merging = 3,
  Completed = 4,
  Failed = 5,
  Cancelled = 6,
}

/** 下载任务项 */
export interface DownloadTaskItem {
  id: number;
  vod_id: number;
  vod_name: string;
  vod_pic: string;
  ep_name: string;
  resource_domain: string;
  resource_name: string;
  group_key: string;
  source_index: number;
  ep_index: number;
  status: DownloadStatus;
  progress: number;
  total_segments: number;
  downloaded_segments: number;
  file_size: number;
  error_msg: string;
  created_at: number; // unix ms
  updated_at: number; // unix ms
}

/** 下载任务列表响应 */
export interface DownloadListResp {
  total: number;
  items: DownloadTaskItem[];
}

/** 创建下载项 */
export interface DownloadItem {
  source_index: number;
  ep_index: number;
  ep_name: string;
  m3u8_url: string;
}

/** 创建下载任务请求 */
export interface DownloadCreateReq {
  vod_id: number;
  vod_name: string;
  vod_pic: string;
  resource_domain: string;
  resource_name: string;
  group_key: string;
  items: DownloadItem[];
}

/** 创建下载任务响应 */
export interface DownloadCreateResp {
  task_ids: number[];
  queued: number;
  skipped: number;
}

/** 检查本地下载文件请求 */
export interface DownloadCheckReq {
  resource_domain: string;
  vod_id: number;
  source_index: number;
  ep_index: number;
}

/** 检查本地下载文件响应 */
export interface DownloadCheckResp {
  found: boolean;
  task_id: number;
  file_url: string;
  file_format: string; // "mp4" 或 "ts"
}

/** 下载配置响应 */
export interface DownloadConfigResp {
  download_dir: string;
  max_concurrent: number;
  segment_concurrency: number;
}

/** 更新下载配置请求 */
export interface DownloadConfigUpdateReq {
  download_dir: string;
  max_concurrent: number;
  segment_concurrency: number;
}

// ── 流代理相关 ────────────────────────────────────────────────────────────────

/** 流代理配置（从 sys_config 的 stream_config 项解析） */
export interface StreamConfig {
  /** 是否启用远程流代理（对应 value5，"1"/"true" 为启用） */
  enabled: boolean;
  /** 前瞻窗口大小（value1，默认 20） */
  bufferSize: number;
  /** 通用协程数（value2，默认 5） */
  generalWorkers: number;
  /** 总协程上限（value3，默认 8） */
  maxWorkers: number;
  /** 自动保存（value4，默认 false） */
  autoSave: boolean;
  /** 磁盘缓存上限 MB（value6，默认 10240 即 10GB，0 表示不限制） */
  maxDiskCacheMB: number;
}