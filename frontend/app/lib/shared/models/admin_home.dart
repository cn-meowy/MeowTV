/// 首页区块标题配置模型 — 从 sys_config 的 home_section_titles 项解析
///
/// 对应后端 sys_config 表中 config_group = "home"、config_key = "home_section_titles" 的配置项。
/// value1 = 区块一标题（默认"最近添加"，对应电影列表）
/// value2 = 区块二标题（默认"可能喜欢"，对应剧集列表）
class HomeSectionConfig {
  final int? configId;
  final String sectionTitle1;
  final String sectionTitle2;

  const HomeSectionConfig({
    this.configId,
    this.sectionTitle1 = '最近添加',
    this.sectionTitle2 = '可能喜欢',
  });

  /// 从 sys_config 接口返回的 home_section_titles 项解析
  factory HomeSectionConfig.fromConfigItem(Map<String, dynamic> item) {
    return HomeSectionConfig(
      configId: item['id'] as int?,
      sectionTitle1: (item['value1'] as String?)?.isNotEmpty == true
          ? item['value1'] as String
          : '最近添加',
      sectionTitle2: (item['value2'] as String?)?.isNotEmpty == true
          ? item['value2'] as String
          : '可能喜欢',
    );
  }

  /// 转为更新配置接口的请求体
  Map<String, dynamic> toUpdateBody() => {
        'config_key': 'home_section_titles',
        'value1': sectionTitle1,
        'value2': sectionTitle2,
      };

  HomeSectionConfig copyWith({
    int? configId,
    String? sectionTitle1,
    String? sectionTitle2,
  }) =>
      HomeSectionConfig(
        configId: configId ?? this.configId,
        sectionTitle1: sectionTitle1 ?? this.sectionTitle1,
        sectionTitle2: sectionTitle2 ?? this.sectionTitle2,
      );
}
