// 单元测试：DoubanImageProxyState.resolveImageUrl
//
// 覆盖：
//   - 空输入 → 返回 ''
//   - HTTP 远程 + 后端代理 → 走 buildResourceImageProxyUrl
//   - HTTP 远程 + 前端代理 → 原样返回
//   - 豆瓣图片 + 后端代理 + token 非空 → 豆瓣代理 URL
//   - 演示模式绝对路径 + 后端代理 + token 非空 → 资源图片代理 URL
//   - 演示模式绝对路径 + 后端代理 + token 空 → 不带 token 的代理 URL
//   - 演示模式绝对路径 + 前端代理 → 降级走后端代理 URL
//   - 演示模式绝对路径 + 前端代理 + token 空 → 不带 token 的代理 URL

import 'package:flutter_test/flutter_test.dart';
import 'package:meowtv_mobile/features/settings/douban_image_proxy_provider.dart';
import 'package:meowtv_mobile/shared/models/enums.dart';

void main() {
  const baseUrl = 'http://localhost:8080';
  const tempToken = 'abc123';

  group('DoubanImageProxyState.resolveImageUrl', () {
    test('空输入返回空字符串', () {
      final state = DoubanImageProxyState(
        mode: DoubanImageProxyMode.backend,
        tempToken: tempToken,
      );
      expect(state.resolveImageUrl('', baseUrl), '');
    });

    test('HTTP 远程 + 后端代理 → 资源图片代理 URL（含 token）', () {
      final state = DoubanImageProxyState(
        mode: DoubanImageProxyMode.backend,
        tempToken: tempToken,
      );
      final url = state.resolveImageUrl('https://example.com/cover.jpg', baseUrl);
      expect(url, isNotNull);
      expect(url, contains('/api/resource/image/proxy?url='));
      expect(url, contains('token=$tempToken'));
    });

    test('HTTP 远程 + 前端代理 → 原样返回', () {
      final state = DoubanImageProxyState(
        mode: DoubanImageProxyMode.frontend,
        tempToken: tempToken,
      );
      final url = state.resolveImageUrl('https://example.com/cover.jpg', baseUrl);
      expect(url, 'https://example.com/cover.jpg');
    });

    test('豆瓣图片 + 后端代理 + token 非空 → 豆瓣代理 URL', () {
      final state = DoubanImageProxyState(
        mode: DoubanImageProxyMode.backend,
        tempToken: tempToken,
      );
      final url = state.resolveImageUrl(
        'https://img9.doubanio.com/view/photo/s_ratio_poster/p123.jpg',
        baseUrl,
      );
      expect(url, isNotNull);
      expect(url, contains('/api/douban/image/proxy?url='));
      expect(url, contains('token=$tempToken'));
    });

    test('演示模式绝对路径 + 后端代理 + token 非空 → 资源图片代理 URL', () {
      final state = DoubanImageProxyState(
        mode: DoubanImageProxyMode.backend,
        tempToken: tempToken,
      );
      final url = state.resolveImageUrl('/app/videos/我的吉他.jpg', baseUrl);
      expect(url, isNotNull);
      expect(url, contains('/api/resource/image/proxy?url='));
      expect(url, contains('token=$tempToken'));
    });

    test('演示模式绝对路径 + 后端代理 + token 空 → 不带 token 的代理 URL', () {
      final state = DoubanImageProxyState(
        mode: DoubanImageProxyMode.backend,
        tempToken: '',
      );
      final url = state.resolveImageUrl('/app/videos/cover.jpg', baseUrl);
      expect(url, isNotNull);
      expect(url, contains('/api/resource/image/proxy?url='));
      expect(url, isNot(contains('token=')));
    });

    test('演示模式绝对路径 + 前端代理 → 降级走后端代理 URL', () {
      final state = DoubanImageProxyState(
        mode: DoubanImageProxyMode.frontend,
        tempToken: tempToken,
      );
      final url = state.resolveImageUrl('/app/videos/cover.jpg', baseUrl);
      expect(url, isNotNull);
      expect(url, contains('/api/resource/image/proxy?url='));
      expect(url, contains('token=$tempToken'));
    });

    test('演示模式绝对路径 + 前端代理 + token 空 → 不带 token 的代理 URL', () {
      final state = DoubanImageProxyState(
        mode: DoubanImageProxyMode.frontend,
        tempToken: '',
      );
      final url = state.resolveImageUrl('/app/videos/cover.jpg', baseUrl);
      expect(url, isNotNull);
      expect(url, contains('/api/resource/image/proxy?url='));
      expect(url, isNot(contains('token=')));
    });
  });
}
