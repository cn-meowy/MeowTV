// test/core/cache/video_cache_proxy_access_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowtv_mobile/core/cache/video_cache_proxy.dart';

void main() {
  group('VideoCacheProxyServer.isAllowedClientForTest', () {
    final emptyLocalIps = <String>{};

    group('私有段 / loopback 直接放行', () {
      test('127.0.0.1 放行', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('127.0.0.1', null, emptyLocalIps),
          isTrue,
        );
      });

      test('192.168.x 放行', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('192.168.1.10', null, emptyLocalIps),
          isTrue,
        );
      });

      test('10.x 放行', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('10.0.0.5', null, emptyLocalIps),
          isTrue,
        );
      });

      test('172.16-31.x 放行（含边界）', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('172.16.0.1', null, emptyLocalIps),
          isTrue,
        );
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('172.31.255.254', null, emptyLocalIps),
          isTrue,
        );
      });

      test('172.15 / 172.32 不放行（边界外）', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('172.15.0.1', null, emptyLocalIps),
          isFalse,
        );
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('172.32.0.1', null, emptyLocalIps),
          isFalse,
        );
      });

      test('IPv6 fe80:: 放行', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('fe80::1', null, emptyLocalIps),
          isTrue,
        );
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('fe80::abcd:ef01', null, emptyLocalIps),
          isTrue,
        );
      });

      test('IPv6 ::1 放行', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('::1', null, emptyLocalIps),
          isTrue,
        );
      });
    });

    group('公网源 + 命中本机接口 → 放行（iOS VPN 自连场景）', () {
      final localIps = <String>{'40.53.15.52', '192.168.1.20'};

      test('Azure 公网 IP 命中本机 utun 接口 → 放行', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('40.53.15.52', null, localIps),
          isTrue,
        );
      });

      test('公网源 + 本机有 LAN 接口 → 放行', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('192.168.1.20', null, localIps),
          isTrue,
        );
      });

      test('大小写归一化：接口集合小写存储，源 IP 大写也能命中', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('40.53.15.52', null, {'40.53.15.52'}),
          isTrue,
        );
      });
    });

    group('公网源 + Host=localhost → 放行', () {
      test('Host=localhost', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('40.53.15.52', 'localhost', emptyLocalIps),
          isTrue,
        );
      });

      test('Host=localhost:8080', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('40.53.15.52', 'localhost:8080', emptyLocalIps),
          isTrue,
        );
      });

      test('Host=127.0.0.1:8080', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('40.53.15.52', '127.0.0.1:8080', emptyLocalIps),
          isTrue,
        );
      });

      test('Host=[::1]:8080（IPv6 括号）', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('40.53.15.52', '[::1]:8080', emptyLocalIps),
          isTrue,
        );
      });

      test('Host 大小写归一化', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('40.53.15.52', 'LOCALHOST:1234', emptyLocalIps),
          isTrue,
        );
      });
    });

    group('公网源 + 非本机接口 + 普通 Host → 拒绝', () {
      test('拒绝（Host=null）', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('40.53.15.52', null, emptyLocalIps),
          isFalse,
        );
      });

      test('拒绝（Host=公网域名）', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('40.53.15.52', 'example.com', emptyLocalIps),
          isFalse,
        );
      });

      test('拒绝（Host=公网 IP:端口）', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('40.53.15.52', '40.53.15.52:8080', emptyLocalIps),
          isFalse,
        );
      });

      test('拒绝（Host 空字符串）', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('40.53.15.52', '', emptyLocalIps),
          isFalse,
        );
      });
    });

    group('Host 归一化边界', () {
      test('纯 IPv6 不带括号 ::1', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('40.53.15.52', '::1', emptyLocalIps),
          isTrue,
        );
      });

      test('Host 中括号但只有 [::1] 无端口', () {
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('40.53.15.52', '[::1]', emptyLocalIps),
          isTrue,
        );
      });

      test('IPv4 含端口 192.168.1.10:8080 作为 Host 头不算 loopback → 拒绝', () {
        // 192.168.x 是私有段但不是 loopback；Host 头仅作为 loopback 兜底，
        // 故公网源 + 该 Host 应被拒绝（由客户端使用 loopback Host 才放行）。
        expect(
          VideoCacheProxyServer.isAllowedClientForTest('40.53.15.52', '192.168.1.10:8080', emptyLocalIps),
          isFalse,
        );
      });
    });
  });
}