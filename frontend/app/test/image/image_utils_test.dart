// 单元测试：ImageUtils 的图片 URL 构建工具
//
// 覆盖：
//   - isLocalFilePath / isAbsolutePath / isRelativePath：本地路径判定
//   - buildDemoImageProxyUrl：tempToken 非空 → 返回正确代理 URL（含 token=）
//   - buildDemoImageProxyUrl：tempToken 空 → 返回不带 token 的 URL
//   - buildDemoImageProxyUrl：localPath 空 → 返回 null

import 'package:flutter_test/flutter_test.dart';
import 'package:meowtv_mobile/shared/utils/image_utils.dart';

void main() {
  group('ImageUtils.isLocalFilePath', () {
    test('绝对路径返回 true', () {
      expect(ImageUtils.isLocalFilePath('/app/videos/我的吉他.jpg'), isTrue);
      expect(ImageUtils.isLocalFilePath('/data/media/cover.png'), isTrue);
    });

    test('相对路径返回 true', () {
      expect(ImageUtils.isLocalFilePath('videos/cover.jpg'), isTrue);
      expect(ImageUtils.isLocalFilePath('cover.png'), isTrue);
    });

    test('http(s) URL 返回 false', () {
      expect(ImageUtils.isLocalFilePath('http://example.com/cover.jpg'), isFalse);
      expect(ImageUtils.isLocalFilePath('https://example.com/cover.jpg'), isFalse);
    });

    test('空字符串返回 false', () {
      expect(ImageUtils.isLocalFilePath(''), isFalse);
    });
  });

  group('ImageUtils.isAbsolutePath', () {
    test('以 / 开头的本地路径返回 true', () {
      expect(ImageUtils.isAbsolutePath('/app/videos/我的吉他.jpg'), isTrue);
      expect(ImageUtils.isAbsolutePath('/data/media/cover.png'), isTrue);
    });

    test('相对路径返回 false', () {
      expect(ImageUtils.isAbsolutePath('videos/cover.jpg'), isFalse);
      expect(ImageUtils.isAbsolutePath('cover.png'), isFalse);
    });

    test('http(s) URL 与空字符串返回 false', () {
      expect(ImageUtils.isAbsolutePath('http://example.com/cover.jpg'), isFalse);
      expect(ImageUtils.isAbsolutePath(''), isFalse);
    });
  });

  group('ImageUtils.isRelativePath', () {
    test('不以 / 开头的本地路径返回 true', () {
      expect(ImageUtils.isRelativePath('videos/cover.jpg'), isTrue);
      expect(ImageUtils.isRelativePath('cover.png'), isTrue);
      expect(ImageUtils.isRelativePath('./assets/img.jpg'), isTrue);
      expect(ImageUtils.isRelativePath('../assets/img.jpg'), isTrue);
    });

    test('绝对路径返回 false', () {
      expect(ImageUtils.isRelativePath('/app/videos/我的吉他.jpg'), isFalse);
    });

    test('data URI 返回 false（不误判为相对路径）', () {
      expect(ImageUtils.isRelativePath('data:image/png;base64,iVBORw0KGgo='), isFalse);
    });

    test('http(s) URL 与空字符串返回 false', () {
      expect(ImageUtils.isRelativePath('http://example.com/cover.jpg'), isFalse);
      expect(ImageUtils.isRelativePath('https://example.com/cover.jpg'), isFalse);
      expect(ImageUtils.isRelativePath(''), isFalse);
    });
  });

  group('ImageUtils.buildDemoImageProxyUrl', () {
    const baseUrl = 'http://localhost:8080';
    const tempToken = 'abc123';

    test('tempToken 非空时返回正确的代理 URL', () {
      final url = ImageUtils.buildDemoImageProxyUrl(
        localPath: '/app/videos/我的吉他.jpg',
        tempToken: tempToken,
        baseUrl: baseUrl,
      );

      expect(url, isNotNull);
      expect(url, startsWith('$baseUrl/api/resource/image/proxy?'));
      expect(url, contains('url='));
      expect(url, contains('token=$tempToken'));
    });

    test('对 localPath 做 URL 编码', () {
      final url = ImageUtils.buildDemoImageProxyUrl(
        localPath: '/app/videos/我的吉他.jpg',
        tempToken: tempToken,
        baseUrl: baseUrl,
      );

      expect(url, isNotNull);
      // 中文 / 特殊字符应被编码，原始明文不应出现在 URL 中
      expect(url!.contains('我的吉他'), isFalse);
    });

    test('baseUrl 末尾带斜杠时自动剥离', () {
      final url = ImageUtils.buildDemoImageProxyUrl(
        localPath: '/app/videos/cover.jpg',
        tempToken: tempToken,
        baseUrl: '$baseUrl/',
      );

      expect(url, isNotNull);
      expect(url, startsWith('$baseUrl/api/resource/image/proxy?'));
      expect(url, isNot(contains('//api')));
    });

    test('tempToken 为空时返回不带 token 的 URL（便于日志排查，后端会 401）', () {
      final url = ImageUtils.buildDemoImageProxyUrl(
        localPath: '/app/videos/cover.jpg',
        tempToken: '',
        baseUrl: baseUrl,
      );

      expect(url, isNotNull);
      expect(url, startsWith('$baseUrl/api/resource/image/proxy?'));
      expect(url, contains('url='));
      expect(url, isNot(contains('token=')));
    });

    test('localPath 为空时返回 null', () {
      final url = ImageUtils.buildDemoImageProxyUrl(
        localPath: '',
        tempToken: tempToken,
        baseUrl: baseUrl,
      );

      expect(url, isNull);
    });
  });
}
