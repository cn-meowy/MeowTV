import 'package:flutter_test/flutter_test.dart';
import 'package:meowtv_mobile/features/settings/cast_proxy_provider.dart' show LanCandidate, rankLanIp;

void main() {
  group('rankLanIp', () {
    test('en0 192.168.x + utun 40.53.15.52 → 选 192.168.x', () {
      final candidates = [
        const LanCandidate('utun0', '40.53.15.52'),
        const LanCandidate('en0', '192.168.1.5'),
      ];
      expect(rankLanIp(candidates), '192.168.1.5');
    });

    test('en0 192.168.x + utun 10.x → en0 优先', () {
      final candidates = [
        const LanCandidate('utun0', '10.0.0.5'),
        const LanCandidate('en0', '192.168.1.5'),
      ];
      expect(rankLanIp(candidates), '192.168.1.5');
    });

    test('仅 utun 公网 → 回退返回第一个非链路本地', () {
      final candidates = [
        const LanCandidate('utun0', '8.8.8.8'),
        const LanCandidate('en1', '127.0.0.1'),
      ];
      expect(rankLanIp(candidates), '8.8.8.8');
    });

    test('169.254.x 排除', () {
      final candidates = [
        const LanCandidate('en0', '169.254.1.1'),
        const LanCandidate('en1', '192.168.1.5'),
      ];
      expect(rankLanIp(candidates), '192.168.1.5');
    });

    test('172.31.x 在 RFC1918 内、172.32.x 在段外', () {
      expect(
        rankLanIp([const LanCandidate('en0', '172.31.0.1')]),
        '172.31.0.1',
      );
      // 172.32 不在 RFC1918，应回退到非 VPN、非链路本地
      expect(
        rankLanIp([const LanCandidate('en0', '172.32.0.1')]),
        '172.32.0.1',
      );
    });

    test('Android 接口名 wlan0 归入第 2 级（RFC1918）', () {
      final candidates = [
        const LanCandidate('wlan0', '192.168.1.5'),
      ];
      expect(rankLanIp(candidates), '192.168.1.5');
    });

    test('utun0 在无其他候选时才出现（第 4 级最后退路）', () {
      final candidates = [
        const LanCandidate('utun0', '40.53.15.52'),
      ];
      expect(rankLanIp(candidates), '40.53.15.52');
    });

    test('wlan0 + utun0 → wlan0 优先', () {
      final candidates = [
        const LanCandidate('utun0', '10.0.0.5'),
        const LanCandidate('wlan0', '192.168.1.5'),
      ];
      expect(rankLanIp(candidates), '192.168.1.5');
    });

    test('en0 链路本地 + utun0 公网 → 跳过链路本地，取 utun', () {
      final candidates = [
        const LanCandidate('en0', '169.254.1.1'),
        const LanCandidate('utun0', '8.8.8.8'),
      ];
      expect(rankLanIp(candidates), '8.8.8.8');
    });

    test('空列表返回 null', () {
      expect(rankLanIp(const []), isNull);
    });

    test('仅链路本地 → 返回 null', () {
      final candidates = [
        const LanCandidate('en0', '169.254.1.1'),
      ];
      expect(rankLanIp(candidates), isNull);
    });

    test('en1 + en0 同时存在 → 第一个匹配返回', () {
      final candidates = [
        const LanCandidate('en1', '10.0.0.5'),
        const LanCandidate('en0', '192.168.1.5'),
      ];
      expect(rankLanIp(candidates), '10.0.0.5');
    });

    test('en0 RFC1918 优先于 utun0 RFC1918', () {
      final candidates = [
        const LanCandidate('utun0', '172.20.0.1'),
        const LanCandidate('en0', '172.20.0.2'),
      ];
      // en0 优先
      expect(rankLanIp(candidates), '172.20.0.2');
    });
  });
}