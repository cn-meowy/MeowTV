import 'admin_config.dart';

/// 订阅配置模型 — 从 admin/resource/subscribe/config 响应中解析.
class SubscribeConfig {
  final int? configId;
  final String subscribeUrl;
  final bool autoSubscribe;
  final String cronExpr;
  final bool isEnabled;

  const SubscribeConfig({
    this.configId,
    required this.subscribeUrl,
    required this.autoSubscribe,
    required this.cronExpr,
    required this.isEnabled,
  });
}

/// 代理配置模型
class ProxyConfig {
  final String protocol;
  final String host;
  final String port;
  final String username;
  final String password;
  final bool enabled;
  final bool passwordMasked;

  const ProxyConfig({
    required this.protocol,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.enabled,
    this.passwordMasked = false,
  });
}

/// 手动拉取订阅响应
class SubscribeFetchResponse {
  final int total;
  final int added;
  final int updated;

  const SubscribeFetchResponse({required this.total, required this.added, required this.updated});

  factory SubscribeFetchResponse.fromJson(Map<String, dynamic> j) => SubscribeFetchResponse(
    total: j['total'] as int? ?? 0,
    added: j['added'] as int? ?? 0,
    updated: j['updated'] as int? ?? 0,
  );
}

/// 豆瓣配置项 — 映射单条 SysConfigItem 的 title1~title5 + value1~value5
class DoubanConfigItem {
  final String configKey;
  final String title;
  final String title1; final String value1;
  final String title2; final String value2;
  final String title3; final String value3;
  final String title4; final String value4;
  final String title5; final String value5;
  final bool isEnabled;

  const DoubanConfigItem({
    required this.configKey,
    required this.title,
    required this.title1, required this.value1,
    required this.title2, required this.value2,
    required this.title3, required this.value3,
    required this.title4, required this.value4,
    required this.title5, required this.value5,
    required this.isEnabled,
  });

  factory DoubanConfigItem.fromSysConfig(SysConfigItem item) => DoubanConfigItem(
    configKey: item.configKey,
    title: item.title,
    title1: item.title1, value1: item.value1,
    title2: item.title2, value2: item.value2,
    title3: item.title3, value3: item.value3,
    title4: item.title4, value4: item.value4,
    title5: item.title5, value5: item.value5,
    isEnabled: item.isEnabled,
  );

  DoubanConfigItem copyWith({
    String? value1, String? value2, String? value3,
    String? value4, String? value5, bool? isEnabled,
  }) => DoubanConfigItem(
    configKey: configKey, title: title,
    title1: title1, value1: value1 ?? this.value1,
    title2: title2, value2: value2 ?? this.value2,
    title3: title3, value3: value3 ?? this.value3,
    title4: title4, value4: value4 ?? this.value4,
    title5: title5, value5: value5 ?? this.value5,
    isEnabled: isEnabled ?? this.isEnabled,
  );
}
