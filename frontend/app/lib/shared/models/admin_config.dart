/// 系统配置模型 — mirrors Web SysConfigItem.
class SysConfigItem {
  final int id;
  final String configKey;
  final String configGroup;
  final String title;
  final String title1;
  final String title2;
  final String title3;
  final String title4;
  final String title5;
  final String title6;
  final String value1;
  final String value2;
  final String value3;
  final String value4;
  final String value5;
  final String value6;
  final bool isEnabled;

  const SysConfigItem({
    required this.id,
    required this.configKey,
    required this.configGroup,
    required this.title,
    required this.title1,
    required this.title2,
    required this.title3,
    this.title4 = '',
    this.title5 = '',
    this.title6 = '',
    required this.value1,
    required this.value2,
    required this.value3,
    required this.value4,
    required this.value5,
    required this.value6,
    required this.isEnabled,
  });

  factory SysConfigItem.fromJson(Map<String, dynamic> j) => SysConfigItem(
    id: j['id'] as int? ?? 0,
    configKey: j['config_key'] as String? ?? '',
    configGroup: j['config_group'] as String? ?? '',
    title: j['title'] as String? ?? '',
    title1: j['title1'] as String? ?? '',
    title2: j['title2'] as String? ?? '',
    title3: j['title3'] as String? ?? '',
    title4: j['title4'] as String? ?? '',
    title5: j['title5'] as String? ?? '',
    title6: j['title6'] as String? ?? '',
    value1: j['value1'] as String? ?? '',
    value2: j['value2'] as String? ?? '',
    value3: j['value3'] as String? ?? '',
    value4: j['value4'] as String? ?? '',
    value5: j['value5'] as String? ?? '',
    value6: j['value6'] as String? ?? '',
    isEnabled: j['is_enabled'] as bool? ?? true,
  );
}
