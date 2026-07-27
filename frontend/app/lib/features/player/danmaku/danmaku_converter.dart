import 'package:xml/xml.dart';
import 'danmaku_item.dart';

/// 弹幕转换器接口
abstract class DanmakuConverter<T> {
  /// 将源数据转为内部格式
  List<DanmakuItem> convert(T rawData);
}

/// B站 XML 格式转换器
/// 解析格式: `<d p="time,mode,fontsize,color,timestamp,pool,mid,weight">text</d>`
class BilibiliXmlConverter implements DanmakuConverter<String> {
  @override
  List<DanmakuItem> convert(String xmlContent) {
    final items = <DanmakuItem>[];
    try {
      final document = XmlDocument.parse(xmlContent);
      final elements = document.findAllElements('d');
      var index = 0;

      for (final element in elements) {
        try {
          final p = element.getAttribute('p') ?? '';
          final text = element.innerText.trim();
          if (text.isEmpty || p.isEmpty) continue;

          final parts = p.split(',');
          if (parts.length < 4) continue;

          final time = double.tryParse(parts[0]) ?? 0.0;
          final modeInt = int.tryParse(parts[1]) ?? 1;
          final fontSize = int.tryParse(parts[2]) ?? 25;
          final color = int.tryParse(parts[3]) ?? 0xFFFFFF;

          // 映射 mode: 1=scroll, 4=topFixed, 5=bottomFixed, 其他忽略
          final mode = switch (modeInt) {
            1 => DanmakuMode.scroll,
            4 => DanmakuMode.topFixed,
            5 => DanmakuMode.bottomFixed,
            _ => null,
          };
          if (mode == null) continue;

          items.add(DanmakuItem(
            id: 'bxml_$index',
            mode: mode,
            startTime: Duration(milliseconds: (time * 1000).round()),
            content: text,
            style: DanmakuStyle(
              fontSize: fontSize,
              color: 0xFF000000 | color,
            ),
          ));
          index++;
        } catch (_) {
          continue;
        }
      }
    } catch (_) {
      // XML 解析失败，返回空列表
    }

    items.sort((a, b) => a.startTime.compareTo(b.startTime));
    return items;
  }
}

/// DanDanPlay JSON 格式转换器
class DandanplayConverter implements DanmakuConverter<Map<String, dynamic>> {
  @override
  List<DanmakuItem> convert(Map<String, dynamic> jsonData) {
    final items = <DanmakuItem>[];
    try {
      final comments = jsonData['comments'] as List<dynamic>? ?? [];
      for (var i = 0; i < comments.length; i++) {
        try {
          final comment = comments[i] as Map<String, dynamic>;
          final time = (comment['time'] as num?)?.toDouble() ?? 0.0;
          final text = (comment['text'] as String?) ?? '';
          if (text.isEmpty) continue;

          items.add(DanmakuItem(
            id: 'ddp_$i',
            mode: DanmakuMode.scroll,
            startTime: Duration(milliseconds: (time * 1000).round()),
            content: text,
          ));
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}

    items.sort((a, b) => a.startTime.compareTo(b.startTime));
    return items;
  }
}

/// 转换器工厂
class DanmakuConverterFactory {
  final Map<String, DanmakuConverter> _converters = {};

  void register(String format, DanmakuConverter converter) {
    _converters[format] = converter;
  }

  DanmakuConverter? get(String format) {
    return _converters[format];
  }

  /// 注册内置转换器
  void registerDefaults() {
    register('bilibili-xml', BilibiliXmlConverter());
    register('dandanplay-json', DandanplayConverter());
  }
}
