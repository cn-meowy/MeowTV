/// 内嵌音轨数据模型
class AudioTrack {
  final String id;
  final String label;
  final String? language;
  final int? channelCount;
  final String? codec;
  final bool isActive;

  const AudioTrack({
    required this.id,
    required this.label,
    this.language,
    this.channelCount,
    this.codec,
    this.isActive = false,
  });

  /// 显示副标题（如 "AAC 2ch"）
  String get subtitle {
    final parts = <String>[];
    if (codec != null && codec!.isNotEmpty) parts.add(codec!.toUpperCase());
    if (channelCount != null) parts.add('${channelCount}ch');
    return parts.join(' ');
  }

  AudioTrack copyWith({bool? isActive}) {
    return AudioTrack(
      id: id,
      label: label,
      language: language,
      channelCount: channelCount,
      codec: codec,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioTrack && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
