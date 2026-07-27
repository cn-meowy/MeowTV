/// 流代理配置模型 — 从 sys_config 的 stream_config 项解析
class StreamConfig {
  final int? configId;
  final bool enabled;
  final int bufferSize;
  final int generalWorkers;
  final int maxWorkers;
  final bool autoSave;
  final int maxDiskCacheMB;

  const StreamConfig({
    this.configId,
    this.enabled = false,
    this.bufferSize = 20,
    this.generalWorkers = 5,
    this.maxWorkers = 8,
    this.autoSave = false,
    this.maxDiskCacheMB = 10240,
  });

  /// 从 sys_config 接口返回的 stream_config 项解析
  factory StreamConfig.fromConfigItem(Map<String, dynamic> item) {
    return StreamConfig(
      configId: item['id'] as int?,
      enabled: item['value5'] == '1' || item['value5'] == 'true',
      bufferSize: int.tryParse(item['value1']?.toString() ?? '') ?? 20,
      generalWorkers: int.tryParse(item['value2']?.toString() ?? '') ?? 5,
      maxWorkers: int.tryParse(item['value3']?.toString() ?? '') ?? 8,
      autoSave: item['value4'] == '1' || item['value4'] == 'true',
      maxDiskCacheMB: int.tryParse(item['value6']?.toString() ?? '') ?? 10240,
    );
  }

  /// 转为更新配置接口的请求体
  Map<String, dynamic> toUpdateBody() => {
        'config_key': 'stream_config',
        'value1': bufferSize.toString(),
        'value2': generalWorkers.toString(),
        'value3': maxWorkers.toString(),
        'value4': autoSave ? 'true' : 'false',
        'value5': enabled ? 'true' : 'false',
        'value6': maxDiskCacheMB.toString(),
      };

  StreamConfig copyWith({
    int? configId,
    bool? enabled,
    int? bufferSize,
    int? generalWorkers,
    int? maxWorkers,
    bool? autoSave,
    int? maxDiskCacheMB,
  }) =>
      StreamConfig(
        configId: configId ?? this.configId,
        enabled: enabled ?? this.enabled,
        bufferSize: bufferSize ?? this.bufferSize,
        generalWorkers: generalWorkers ?? this.generalWorkers,
        maxWorkers: maxWorkers ?? this.maxWorkers,
        autoSave: autoSave ?? this.autoSave,
        maxDiskCacheMB: maxDiskCacheMB ?? this.maxDiskCacheMB,
      );
}
