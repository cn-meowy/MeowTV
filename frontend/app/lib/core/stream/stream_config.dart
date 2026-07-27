import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;

/// 流代理配置 — 对应后端 StreamConfig
class StreamConfig {
  /// 前瞻缓冲分片数（调度器为用户预下载的分片数）
  final int bufferSize;

  /// 通用 Worker 数量
  final int generalWorkers;

  /// 最大 Worker 数量
  final int maxWorkers;

  /// 是否自动保存为下载任务
  final bool autoSave;

  /// 是否启用流代理
  final bool isEnable;

  /// 磁盘缓存上限（MB），0 表示不限制
  final int maxDiskCacheMB;

  const StreamConfig({
    this.bufferSize = 20,
    this.generalWorkers = 5,
    this.maxWorkers = 8,
    this.autoSave = false,
    this.isEnable = true,
    this.maxDiskCacheMB = 10240,
  });

  static StreamConfig get defaults => const StreamConfig();
}

/// AES-128 加密信息 — 对应后端 EncryptionInfo
class EncryptionInfo {
  final String method; // AES-128
  String keyURI; // 可变：解析时可能为相对路径，后续回填为绝对 URL
  final Uint8List? iv;
  Uint8List? key; // 解密后的 key（可变，解析后填入）

  EncryptionInfo({
    required this.method,
    required this.keyURI,
    this.iv,
    this.key,
  });
}

/// TS 分片信息 — 对应后端 SegmentInfo
class SegmentInfo {
  final String url;
  final double duration;
  final int index;
  final EncryptionInfo? encryption; // 该分片专属的加密信息
  final bool isDiscontinuity; // 此分片前是否有 #EXT-X-DISCONTINUITY 标记

  const SegmentInfo({
    required this.url,
    required this.duration,
    required this.index,
    this.encryption,
    this.isDiscontinuity = false,
  });
}

/// Master playlist 码率变体 — 对应后端 VariantInfo
class VariantInfo {
  final int bandwidth;
  final String resolution;
  final String uri;
  final int? width;
  final int? height;
  final double? frameRate;
  final String? codec;
  final String? name;

  const VariantInfo({
    required this.bandwidth,
    required this.resolution,
    required this.uri,
    this.width,
    this.height,
    this.frameRate,
    this.codec,
    this.name,
  });
}

/// m3u8 解析结果 — 对应后端 M3u8Info
class M3u8Info {
  final bool isMaster;
  final bool isVOD; // 是否有 EXT-X-ENDLIST
  final List<VariantInfo> variants; // master playlist 多码率
  final List<SegmentInfo> segments; // media playlist 分片列表
  final EncryptionInfo? encryption; // 全局加密信息
  final double duration; // 总时长秒
  final String mediaURL; // 如果是 master，选择的最优 media playlist URL
  final String rawContent; // media playlist 原始文本（用于 rewriteM3U8 行级替换）

  const M3u8Info({
    this.isMaster = false,
    this.isVOD = false,
    this.variants = const [],
    this.segments = const [],
    this.encryption,
    this.duration = 0,
    this.mediaURL = '',
    this.rawContent = '',
  });
}

/// 分片下载状态 — 对应后端 SegmentStatus
enum SegmentStatus {
  pending,
  downloading,
  done,
  failed;

  static SegmentStatus fromIndex(int index) {
    switch (index) {
      case 0:
        return SegmentStatus.pending;
      case 1:
        return SegmentStatus.downloading;
      case 2:
        return SegmentStatus.done;
      case 3:
        return SegmentStatus.failed;
      default:
        return SegmentStatus.pending;
    }
  }
}

/// 会话状态 — 对应后端 SessionState
enum SessionState {
  created,
  active,
  idle,
  saving,
  completed,
  expired,
  error;

  @override
  String toString() => name;
}

/// Worker 类型 — 对应后端 WorkerType
enum WorkerType {
  dedicated, // 专属协程
  general; // 通用协程

  @override
  String toString() => name;
}

/// 下载任务 — 对应后端 Task
class DownloadTask {
  final int segmentIndex;
  final int priority; // 数值越小优先级越高
  final bool urgent;
  final int? userId; // 专属协程关联的用户 ID

  const DownloadTask({
    required this.segmentIndex,
    this.priority = 0,
    this.urgent = false,
    this.userId,
  });
}

/// AES-128 辅助：PKCS7 unpad
Uint8List pkcs7Unpad(Uint8List data) {
  if (data.isEmpty) {
    throw ArgumentError('data is empty');
  }
  final padding = data.last;
  if (padding == 0 || padding > data.length || padding > 16) {
    throw ArgumentError(
        'invalid padding value $padding (data length ${data.length})');
  }
  for (var i = data.length - padding; i < data.length; i++) {
    if (data[i] != padding) {
      throw ArgumentError(
          'padding mismatch at index $i: expected $padding, got ${data[i]}');
    }
  }
  return Uint8List.sublistView(data, 0, data.length - padding);
}

/// AES-128-CBC 解密 TS 分片 — 对应后端 DecryptSegment
Uint8List decryptSegment(Uint8List data, Uint8List key, Uint8List iv) {
  // 验证 Key 长度
  if (key.length != 16) {
    throw ArgumentError('key length ${key.length} is not 16 bytes');
  }

  // 验证数据长度
  if (data.isEmpty) {
    throw ArgumentError('input data is empty');
  }
  if (data.length < 16) {
    throw ArgumentError(
        'input length ${data.length} is less than block size 16');
  }
  if (data.length % 16 != 0) {
    throw ArgumentError(
        'input length ${data.length} is not a multiple of block size 16');
  }

  // 验证 IV 长度
  if (iv.length != 16) {
    throw ArgumentError('IV length ${iv.length} is not 16 bytes');
  }

  // AES-128-CBC 解密
  final encrypter = encrypt.Encrypter(
    encrypt.AES(
      encrypt.Key(key),
      mode: encrypt.AESMode.cbc,
      padding: null, // 我们手动处理 PKCS7 unpad
    ),
  );
  final encrypted = encrypt.Encrypted(data);
  final decrypted = encrypter.decryptBytes(encrypted, iv: encrypt.IV(iv));

  // PKCS7 unpad
  return pkcs7Unpad(Uint8List.fromList(decrypted));
}

/// 检测数据是否以 MPEG-TS 同步字节 0x47 开头 — 对应后端 IsTSPacketData
bool isTSPacketData(Uint8List data) {
  if (data.length < 4) return false;
  if (data[0] != 0x47) return false;
  // 如果数据足够长，验证第二个 TS 包的同步字节
  if (data.length >= 189 && data[188] != 0x47) return false;
  return true;
}

/// 合并所有 TS 分片数据 — 对应后端 MergeSegments
Uint8List mergeSegments(List<Uint8List> segments) {
  final merged = BytesBuilder();
  for (final seg in segments) {
    merged.add(seg);
  }
  return merged.toBytes();
}

/// 解析 HLS 属性字符串 — 对应后端 parseAttributes
///
/// 共享工具方法，供 M3u8Parser 和 StreamSession 使用，避免重复实现。
/// 例如: METHOD=AES-128,URI="https://key.example.com",IV=0x1234
Map<String, String> parseHlsAttributes(String raw) {
  final attrs = <String, String>{};
  var i = 0;

  while (i < raw.length) {
    final eqIdx = raw.indexOf('=', i);
    if (eqIdx < 0) break;
    final key = raw.substring(i, eqIdx);
    i = eqIdx + 1;

    if (i >= raw.length) break;

    String value;
    if (raw[i] == '"') {
      final endIdx = raw.indexOf('"', i + 1);
      if (endIdx < 0) break;
      value = raw.substring(i + 1, endIdx);
      i = endIdx + 2;
    } else {
      final commaIdx = raw.indexOf(',', i);
      if (commaIdx < 0) {
        value = raw.substring(i);
        i = raw.length;
      } else {
        value = raw.substring(i, commaIdx);
        i = commaIdx + 1;
      }
    }

    attrs[key] = value;

    if (i < raw.length && raw[i] == ',') {
      i++;
    }
  }
  return attrs;
}

/// 十六进制解码辅助 — 对应后端 hex.DecodeString
/// 支持奇数长度输入（自动前面补 '0'）
List<int> hexDecode(String hex) {
  var str = hex;
  if (str.length % 2 != 0) {
    str = '0$str';
  }
  final result = <int>[];
  for (var i = 0; i < str.length; i += 2) {
    final byte = int.parse(str.substring(i, i + 2), radix: 16);
    result.add(byte);
  }
  return result;
}
