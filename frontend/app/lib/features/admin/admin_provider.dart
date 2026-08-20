import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/logger/app_logger.dart';
import '../../shared/models/admin_config.dart';
import '../../shared/models/admin_user.dart';
import '../../shared/models/admin_group.dart';
import '../../shared/models/admin_download.dart';
import '../../shared/models/admin_subscribe.dart';
import '../../shared/models/admin_stream.dart';
import '../../shared/models/admin_home.dart';
import 'admin_state.dart';

class AdminNotifier extends StateNotifier<AdminState> {
  final ApiClient _api;
  AdminNotifier(this._api) : super(const AdminState());

  dynamic _extractData(Map<String, dynamic> body) {
    final code = body['code'];
    if (code != null && code != 200 && code != 0) {
      throw Exception(body['msg'] ?? '请求失败');
    }
    return body['data'];
  }

  Map<String, dynamic> _configToMap(SysConfigItem i) => {
        'config_key': i.configKey, 'config_group': i.configGroup,
        'title': i.title, 'title1': i.title1, 'title2': i.title2,
        'title3': i.title3, 'value1': i.value1, 'value2': i.value2,
        'value3': i.value3, 'value4': i.value4, 'value5': i.value5,
        'value6': i.value6, 'is_enabled': i.isEnabled,
      };

  // ── Subscribe (via config API) ─────────────────────────────────────────

  /// 使用 config 通用接口拉取订阅相关配置（参照 Web 端 SettingsPage）
  Future<void> fetchSubscribeConfig() async {
    if (!mounted) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final resp = await _api.post<Map<String, dynamic>>(
          ApiConstants.adminConfigList, data: {'group': 'resource_subscribe'});
      if (!mounted) return;
      final data = _extractData(resp.data!);
      if (data is List) {
        for (final e in data) {
          final item = e as Map<String, dynamic>;
          final key = item['config_key'] as String? ?? '';
          if (key == 'resource_subscribe') {
            state = state.copyWith(subscribeConfig: SubscribeConfig(
              configId: item['id'] as int?,
              subscribeUrl: item['value1'] as String? ?? '',
              autoSubscribe: item['value2'] == 'true',
              cronExpr: item['value3'] as String? ?? '',
              isEnabled: item['is_enabled'] as bool? ?? true,
            ));
          } else if (key == 'resource_proxy') {
            state = state.copyWith(proxyConfig: ProxyConfig(
              protocol: item['value1'] as String? ?? 'http',
              host: item['value2'] as String? ?? '',
              port: item['value3'] as String? ?? '',
              username: item['value4'] as String? ?? '',
              password: (item['value5'] as String?) ?? '',
              enabled: item['value6'] == 'true',
              passwordMasked: (item['value5'] as String?) != null && (item['value5'] as String).isNotEmpty,
            ));
          } else if (key == 'resource_proxy_test_url') {
            // 保存测试 URL 到 state（后续可在 UI 中使用）
          }
        }
      }
    } catch (e) {
      appLogger.e('获取订阅配置失败', error: e);
      if (!mounted) return;
      state = state.copyWith(error: '获取订阅配置失败: $e');
    } finally {
      if (mounted) state = state.copyWith(loading: false);
    }
  }

  /// 使用 config 通用接口保存订阅配置
  Future<bool> saveSubscribeConfig(SubscribeConfig c) async {
    try {
      await _api.post(ApiConstants.adminConfigUpdate, data: {
        'config_key': 'resource_subscribe',
        'value1': c.subscribeUrl,
        'value2': c.autoSubscribe.toString(),
        'value3': c.cronExpr,
        'is_enabled': c.isEnabled,
      });
      if (!mounted) return true;
      state = state.copyWith(subscribeConfig: c);
      return true;
    } catch (e) { appLogger.e('保存订阅配置失败', error: e); return false; }
  }

  /// 使用 config 通用接口保存代理配置
  Future<bool> saveProxyConfig(ProxyConfig c) async {
    try {
      final data = <String, dynamic>{
        'config_key': 'resource_proxy',
        'value1': c.protocol,
        'value2': c.host,
        'value3': c.port,
        'value4': c.username,
        'value6': c.enabled.toString(),
      };
      // 仅当用户实际修改了密码才提交，掩码值不提交
      if (!c.passwordMasked) {
        data['value5'] = c.password;
      }
      await _api.post(ApiConstants.adminConfigUpdate, data: data);
      if (!mounted) return true;
      state = state.copyWith(proxyConfig: c);
      return true;
    } catch (e) { appLogger.e('保存代理配置失败', error: e); return false; }
  }

  Future<SubscribeFetchResponse?> fetchSubscribe() async {
    try {
      final resp = await _api.post<Map<String, dynamic>>(ApiConstants.adminResourceSubscribeFetch);
      final data = _extractData(resp.data!);
      if (data == null) return null;
      return SubscribeFetchResponse.fromJson(data as Map<String, dynamic>);
    } catch (e) { appLogger.e('手动拉取订阅失败', error: e); return null; }
  }

  Future<String?> testProxy() async {
    try {
      final resp = await _api.post<Map<String, dynamic>>(ApiConstants.adminResourceProxyTest);
      return _extractData(resp.data!)?.toString();
    } catch (e) { appLogger.e('测试代理失败', error: e); return null; }
  }

  // ── Config ─────────────────────────────────────────────────────────────

  Future<void> fetchConfigList({String group = 'resource_site'}) async {
    if (!mounted) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final resp = await _api.post<Map<String, dynamic>>(ApiConstants.adminConfigList, data: {'group': group});
      if (!mounted) return;
      final data = _extractData(resp.data!);
      if (data is List) {
        state = state.copyWith(configItems: data.map((e) => SysConfigItem.fromJson(e as Map<String, dynamic>)).toList());
      }
    } catch (e) { appLogger.e('获取配置列表失败', error: e); if (!mounted) return; state = state.copyWith(error: '获取配置列表失败: $e'); }
    finally { if (mounted) state = state.copyWith(loading: false); }
  }

  Future<bool> createConfig(SysConfigItem item) async {
    try { await _api.post(ApiConstants.adminConfigCreate, data: _configToMap(item)); await fetchConfigList(group: item.configGroup); return true; }
    catch (e) { appLogger.e('创建配置项失败', error: e); return false; }
  }

  Future<bool> updateConfig(SysConfigItem item) async {
    try { await _api.post(ApiConstants.adminConfigUpdate, data: _configToMap(item)); await fetchConfigList(group: item.configGroup); return true; }
    catch (e) { appLogger.e('更新配置项失败', error: e); return false; }
  }

  Future<bool> toggleConfigEnabled(SysConfigItem item) async {
    try { await _api.post(ApiConstants.adminConfigUpdate, data: {'config_key': item.configKey, 'is_enabled': !item.isEnabled}); await fetchConfigList(group: item.configGroup); return true; }
    catch (e) { appLogger.e('切换配置状态失败', error: e); return false; }
  }

  Future<bool> deleteConfig(int id, String group) async {
    try { await _api.post(ApiConstants.adminConfigDelete, data: {'id': id}); await fetchConfigList(group: group); return true; }
    catch (e) { appLogger.e('删除配置项失败', error: e); return false; }
  }

  Future<bool> refreshConfigCache() async {
    try { await _api.post(ApiConstants.adminConfigRefreshCache); return true; }
    catch (e) { appLogger.e('刷新缓存失败', error: e); return false; }
  }

  // ── User Management ────────────────────────────────────────────────────

  Future<void> fetchUserList({int page = 1, int size = 20}) async {
    if (!mounted) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final resp = await _api.post<Map<String, dynamic>>(
          ApiConstants.adminUserList, data: {'page': page, 'size': size});
      if (!mounted) return;
      final data = _extractData(resp.data!);
      if (data != null) {
        final d = data as Map<String, dynamic>;
        final list = (d['items'] as List<dynamic>? ?? []).map((e) => UserListItem.fromJson(e as Map<String, dynamic>)).toList();
        state = state.copyWith(userPage: PaginatedData<UserListItem>(items: list, total: d['total'] as int? ?? 0));
      }
    } catch (e) { appLogger.e('获取用户列表失败', error: e); if (!mounted) return; state = state.copyWith(error: '获取用户列表失败: $e'); }
    finally { if (mounted) state = state.copyWith(loading: false); }
  }

  Future<bool> createUser({required String username, required String password, required String nickname, required int role, int? groupId}) async {
    try { await _api.post(ApiConstants.adminUserCreate, data: {'username': username, 'password': password, 'nickname': nickname, 'role': role, if (groupId != null) 'group_id': groupId}); await fetchUserList(); return true; } // ignore: use_null_aware_elements
    catch (e) { appLogger.e('创建用户失败', error: e); return false; }
  }

  Future<bool> updateUser({required int id, String? nickname, int? role, int? status}) async {
    try { await _api.post(ApiConstants.adminUserUpdate, data: {'id': id, if (nickname != null) 'nickname': nickname, if (role != null) 'role': role, if (status != null) 'status': status}); await fetchUserList(); return true; } // ignore: use_null_aware_elements
    catch (e) { appLogger.e('更新用户失败', error: e); return false; }
  }

  Future<bool> resetUserPassword(int id, String newPassword) async {
    try { await _api.post(ApiConstants.adminUserResetPassword, data: {'id': id, 'new_password': newPassword}); return true; }
    catch (e) { appLogger.e('重置密码失败', error: e); return false; }
  }

  Future<bool> deleteUser(int id) async {
    try { await _api.post(ApiConstants.adminUserDelete, data: {'id': id}); await fetchUserList(); return true; }
    catch (e) { appLogger.e('删除用户失败', error: e); return false; }
  }

  Future<bool> kickUser(int id) async {
    try { await _api.post(ApiConstants.adminUserKick, data: {'id': id}); return true; }
    catch (e) { appLogger.e('踢用户下线失败', error: e); return false; }
  }

  // ── User Group ─────────────────────────────────────────────────────────

  Future<void> fetchGroupList({int page = 1, int size = 20}) async {
    if (!mounted) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final resp = await _api.post<Map<String, dynamic>>(
          ApiConstants.adminGroupList, data: {'page': page, 'size': size});
      if (!mounted) return;
      final data = _extractData(resp.data!);
      if (data is List) {
        state = state.copyWith(groups: data.map((e) => UserGroupItem.fromJson(e as Map<String, dynamic>)).toList());
      } else if (data is Map) {
        final d = data as Map<String, dynamic>;
        final list = (d['items'] as List<dynamic>? ?? []).map((e) => UserGroupItem.fromJson(e as Map<String, dynamic>)).toList();
        state = state.copyWith(groups: list);
      }
    } catch (e) { appLogger.e('获取用户组列表失败', error: e); if (!mounted) return; state = state.copyWith(error: '获取用户组列表失败: $e'); }
    finally { if (mounted) state = state.copyWith(loading: false); }
  }

  Future<bool> createGroup({required String name, String? remark}) async {
    try { await _api.post(ApiConstants.adminGroupCreate, data: {'name': name, if (remark != null) 'remark': remark}); await fetchGroupList(); return true; } // ignore: use_null_aware_elements
    catch (e) { appLogger.e('创建用户组失败', error: e); return false; }
  }

  Future<bool> updateGroup({required int id, required String name, String? remark}) async {
    try { await _api.post(ApiConstants.adminGroupUpdate, data: {'id': id, 'name': name, if (remark != null) 'remark': remark}); await fetchGroupList(); return true; } // ignore: use_null_aware_elements
    catch (e) { appLogger.e('更新用户组失败', error: e); return false; }
  }

  Future<bool> deleteGroup(int id) async {
    try { await _api.post(ApiConstants.adminGroupDelete, data: {'id': id}); await fetchGroupList(); return true; }
    catch (e) { appLogger.e('删除用户组失败', error: e); return false; }
  }

  Future<GroupDetailResponse?> fetchGroupDetail(int id) async {
    try {
      final resp = await _api.post<Map<String, dynamic>>(ApiConstants.adminGroupDetail, data: {'id': id});
      final data = _extractData(resp.data!);
      if (data == null) return null;
      return GroupDetailResponse.fromJson(data as Map<String, dynamic>);
    } catch (e) { appLogger.e('获取用户组详情失败', error: e); return null; }
  }

  Future<bool> setGroupResources({required int groupId, required List<String> configKeys}) async {
    try { await _api.post(ApiConstants.adminGroupSetResources, data: {'group_id': groupId, 'config_keys': configKeys}); await fetchGroupList(); return true; }
    catch (e) { appLogger.e('设置用户组资源失败', error: e); return false; }
  }

  Future<bool> setUserGroup({required int userId, required int groupId}) async {
    try { await _api.post(ApiConstants.adminGroupSetUser, data: {'user_id': userId, 'group_id': groupId}); return true; }
    catch (e) { appLogger.e('设置用户组失败', error: e); return false; }
  }

  // ── Douban Config ──────────────────────────────────────────────────────

  Future<void> fetchDoubanRankConfig() async {
    if (!mounted) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final resp = await _api.post<Map<String, dynamic>>(
          ApiConstants.adminConfigList, data: {'group': 'douban'});
      if (!mounted) return;
      final data = _extractData(resp.data!);
      if (data is List) {
        final items = data
            .map((e) => DoubanConfigItem.fromSysConfig(
                SysConfigItem.fromJson(e as Map<String, dynamic>)))
            .toList();
        state = state.copyWith(doubanConfigs: items);
      }
    } catch (e) {
      appLogger.e('获取豆瓣配置失败', error: e);
      if (!mounted) return;
      state = state.copyWith(error: '获取豆瓣配置失败: $e');
    } finally {
      if (mounted) state = state.copyWith(loading: false);
    }
  }

  Future<bool> saveDoubanConfigItem(DoubanConfigItem item) async {
    try {
      await _api.post(ApiConstants.adminConfigUpdate, data: {
        'config_key': item.configKey,
        'value1': item.value1,
        'value2': item.value2,
        'value3': item.value3,
        'value4': item.value4,
        'value5': item.value5,
        'is_enabled': item.isEnabled,
      });
      if (!mounted) return true;
      await fetchDoubanRankConfig();
      return true;
    } catch (e) {
      appLogger.e('保存豆瓣配置失败', error: e);
      return false;
    }
  }

  // ── Download Config ────────────────────────────────────────────────────

  Future<void> fetchDownloadConfig() async {
    if (!mounted) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final resp = await _api.post<Map<String, dynamic>>(ApiConstants.adminDownloadConfig);
      if (!mounted) return;
      final data = _extractData(resp.data!);
      if (data != null) {
        state = state.copyWith(downloadConfig: DownloadConfig.fromJson(data as Map<String, dynamic>));
      }
    } catch (e) { appLogger.e('获取下载配置失败', error: e); if (!mounted) return; state = state.copyWith(error: '获取下载配置失败: $e'); }
    finally { if (mounted) state = state.copyWith(loading: false); }
  }

  Future<bool> saveDownloadConfig(DownloadConfig c) async {
    try { await _api.post(ApiConstants.adminDownloadConfigUpdate, data: {'download_dir': c.downloadDir, 'max_concurrent': c.maxConcurrent, 'segment_concurrency': c.segmentConcurrency}); if (!mounted) return true; state = state.copyWith(downloadConfig: c); return true; }
    catch (e) { appLogger.e('保存下载配置失败', error: e); return false; }
  }

  // ── Stream Config ──────────────────────────────────────────────────────

  /// 使用 config 通用接口拉取流代理配置
  Future<void> fetchStreamConfig() async {
    if (!mounted) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final resp = await _api.post<Map<String, dynamic>>(
          ApiConstants.adminConfigList, data: {'group': 'stream'});
      if (!mounted) return;
      final data = _extractData(resp.data!);
      if (data is List) {
        for (final e in data) {
          final item = e as Map<String, dynamic>;
          final key = item['config_key'] as String? ?? '';
          if (key == 'stream_config') {
            state = state.copyWith(
                streamConfig: StreamConfig.fromConfigItem(item));
            break;
          }
        }
      }
    } catch (e) {
      appLogger.e('获取流代理配置失败', error: e);
      if (!mounted) return;
      state = state.copyWith(error: '获取流代理配置失败: $e');
    } finally {
      if (mounted) state = state.copyWith(loading: false);
    }
  }

  /// 使用 config 通用接口保存流代理配置
  Future<bool> saveStreamConfig(StreamConfig c) async {
    try {
      await _api.post(ApiConstants.adminConfigUpdate, data: c.toUpdateBody());
      if (!mounted) return true;
      state = state.copyWith(streamConfig: c);
      return true;
    } catch (e) {
      appLogger.e('保存流代理配置失败', error: e);
      return false;
    }
  }

  // ── Home Section Config ───────────────────────────────────────────────

  /// 拉取首页区块标题配置（config_group = "home"）
  Future<void> fetchHomeConfig() async {
    if (!mounted) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final resp = await _api.post<Map<String, dynamic>>(
          ApiConstants.adminConfigList, data: {'group': 'home'});
      if (!mounted) return;
      final data = _extractData(resp.data!);
      if (data is List) {
        for (final e in data) {
          final item = e as Map<String, dynamic>;
          final key = item['config_key'] as String? ?? '';
          if (key == 'home_section_titles') {
            state = state.copyWith(
                homeConfig: HomeSectionConfig.fromConfigItem(item));
            break;
          }
        }
      }
    } catch (e) {
      appLogger.e('获取首页区块标题配置失败', error: e);
      if (!mounted) return;
      state = state.copyWith(error: '获取首页区块标题配置失败: $e');
    } finally {
      if (mounted) state = state.copyWith(loading: false);
    }
  }

  /// 保存首页区块标题配置
  Future<bool> saveHomeConfig(HomeSectionConfig c) async {
    try {
      await _api.post(ApiConstants.adminConfigUpdate, data: c.toUpdateBody());
      if (!mounted) return true;
      state = state.copyWith(homeConfig: c);
      return true;
    } catch (e) {
      appLogger.e('保存首页区块标题配置失败', error: e);
      return false;
    }
  }
}

// ── Riverpod Provider ────────────────────────────────────────────────────

final adminProvider = StateNotifierProvider<AdminNotifier, AdminState>((ref) {
  final api = ref.read(apiClientProvider);
  return AdminNotifier(api);
});
