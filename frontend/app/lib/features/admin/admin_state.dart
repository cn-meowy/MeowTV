import '../../shared/models/admin_config.dart';
import '../../shared/models/admin_user.dart';
import '../../shared/models/admin_group.dart';
import '../../shared/models/admin_download.dart';
import '../../shared/models/admin_home.dart';
import '../../shared/models/admin_subscribe.dart';
import '../../shared/models/admin_stream.dart';

/// 管理后台整体状态
class AdminState {
  final bool loading;
  final SubscribeConfig? subscribeConfig;
  final ProxyConfig? proxyConfig;
  final List<SysConfigItem> configItems;
  final List<DoubanConfigItem> doubanConfigs;
  final PaginatedData<UserListItem>? userPage;
  final List<UserGroupItem> groups;
  final DownloadConfig? downloadConfig;
  final StreamConfig? streamConfig;
  final HomeSectionConfig? homeConfig;
  final String? error;

  const AdminState({
    this.loading = false,
    this.subscribeConfig,
    this.proxyConfig,
    this.configItems = const [],
    this.doubanConfigs = const [],
    this.userPage,
    this.groups = const [],
    this.downloadConfig,
    this.streamConfig,
    this.homeConfig,
    this.error,
  });

  AdminState copyWith({
    bool? loading,
    SubscribeConfig? subscribeConfig,
    ProxyConfig? proxyConfig,
    List<SysConfigItem>? configItems,
    List<DoubanConfigItem>? doubanConfigs,
    PaginatedData<UserListItem>? userPage,
    List<UserGroupItem>? groups,
    DownloadConfig? downloadConfig,
    StreamConfig? streamConfig,
    HomeSectionConfig? homeConfig,
    String? error,
  }) =>
      AdminState(
        loading: loading ?? this.loading,
        subscribeConfig: subscribeConfig ?? this.subscribeConfig,
        proxyConfig: proxyConfig ?? this.proxyConfig,
        configItems: configItems ?? this.configItems,
        doubanConfigs: doubanConfigs ?? this.doubanConfigs,
        userPage: userPage ?? this.userPage,
        groups: groups ?? this.groups,
        downloadConfig: downloadConfig ?? this.downloadConfig,
        streamConfig: streamConfig ?? this.streamConfig,
        homeConfig: homeConfig ?? this.homeConfig,
        error: error,
      );
}
