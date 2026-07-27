/// 下载配置模型 — mirrors Web DownloadConfigResp.
class DownloadConfig {
  final String downloadDir;
  final int maxConcurrent;
  final int segmentConcurrency;

  const DownloadConfig({
    required this.downloadDir,
    required this.maxConcurrent,
    required this.segmentConcurrency,
  });

  factory DownloadConfig.fromJson(Map<String, dynamic> j) => DownloadConfig(
    downloadDir: j['download_dir'] as String? ?? 'data/downloads',
    maxConcurrent: j['max_concurrent'] as int? ?? 2,
    segmentConcurrency: j['segment_concurrency'] as int? ?? 10,
  );
}
