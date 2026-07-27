import 'package:flutter_test/flutter_test.dart';
import 'package:meowtv_mobile/features/admin/tabs/resource_filter.dart';
import 'package:meowtv_mobile/shared/models/admin_config.dart';

SysConfigItem _item({
  required String key,
  String title = '',
  String value1 = '',
  String value5 = '',
  String value6 = '',
  bool enabled = true,
}) =>
    SysConfigItem(
      id: 0,
      configKey: key,
      configGroup: 'resource_site',
      title: title,
      title1: '', title2: '', title3: '',
      value1: value1, value2: '', value3: '', value4: '',
      value5: value5, value6: value6,
      isEnabled: enabled,
    );

void main() {
  group('filterResources', () {
    test('all filter returns everything', () {
      final list = [_item(key: 'a'), _item(key: 'b')];
      expect(filterResources(list, StatusFilter.all, ''), list);
    });

    test('enabled filter keeps only enabled', () {
      final list = [
        _item(key: 'a', enabled: true),
        _item(key: 'b', enabled: false),
      ];
      expect(
        filterResources(list, StatusFilter.enabled, '').map((r) => r.configKey),
        ['a'],
      );
    });

    test('disabled filter keeps only disabled', () {
      final list = [
        _item(key: 'a', enabled: true),
        _item(key: 'b', enabled: false),
      ];
      expect(
        filterResources(list, StatusFilter.disabled, '').map((r) => r.configKey),
        ['b'],
      );
    });

    test('adult filter keeps only value5==1', () {
      final list = [
        _item(key: 'a', value5: '1'),
        _item(key: 'b', value5: '0'),
      ];
      expect(
        filterResources(list, StatusFilter.adult, '').map((r) => r.configKey),
        ['a'],
      );
    });

    test('query matches title/configKey/value1 case-insensitively', () {
      final list = [
        _item(key: 'site_a', title: 'Foo'),
        _item(key: 'bar', title: '', value1: 'https://Baz.com'),
      ];
      expect(
        filterResources(list, StatusFilter.all, 'baz').map((r) => r.configKey),
        ['bar'],
      );
      expect(
        filterResources(list, StatusFilter.all, 'foo').map((r) => r.configKey),
        ['site_a'],
      );
    });

    test('empty query does no filtering', () {
      final list = [_item(key: 'a'), _item(key: 'b')];
      expect(filterResources(list, StatusFilter.all, '   ').length, 2);
    });

    test('filter and query compose', () {
      final list = [
        _item(key: 'a', value5: '1', title: 'foo'),
        _item(key: 'b', value5: '1', title: 'bar'),
        _item(key: 'c', value5: '0', title: 'foo'),
      ];
      expect(
        filterResources(list, StatusFilter.adult, 'foo').map((r) => r.configKey),
        ['a'],
      );
    });
  });

  group('invertVisible', () {
    test('toggles each visible key, leaves hidden keys untouched', () {
      final all = [_item(key: 'a'), _item(key: 'b'), _item(key: 'c')];
      final visible = filterResources(all, StatusFilter.all, '');
      final selected = <String>{'a'};
      final next = invertVisible(visible, selected);
      expect(next.contains('a'), isFalse);
      expect(next.contains('b'), isTrue);
      expect(next.contains('c'), isTrue);
    });

    test('hidden keys are preserved even if previously selected', () {
      final all = [
        _item(key: 'a', enabled: false),
        _item(key: 'b', enabled: true),
      ];
      final visible = filterResources(all, StatusFilter.enabled, ''); // only b
      final selected = <String>{'a'};
      final next = invertVisible(visible, selected);
      expect(next.contains('a'), isTrue); // hidden, untouched
      expect(next.contains('b'), isTrue); // visible, inverted
    });
  });

  group('selectAllVisible', () {
    test('adds all visible keys', () {
      final all = [_item(key: 'a'), _item(key: 'b')];
      final visible = filterResources(all, StatusFilter.all, '');
      final next = selectAllVisible(visible, <String>{});
      expect(next, {'a', 'b'});
    });
  });

  group('clearVisible', () {
    test('removes all visible keys, keeps hidden', () {
      final all = [_item(key: 'a'), _item(key: 'b')];
      final visible = filterResources(all, StatusFilter.all, '');
      final next = clearVisible(visible, {'a', 'b', 'hidden'});
      expect(next, {'hidden'});
    });
  });

  group('adultKeysOf', () {
    test('returns set of value5==1 keys', () {
      final list = [
        _item(key: 'a', value5: '1'),
        _item(key: 'b', value5: '0'),
      ];
      expect(adultKeysOf(list), {'a'});
    });
  });

  group('isAllVisibleSelected', () {
    test('true when visible non-empty and all in selected', () {
      final all = [_item(key: 'a')];
      final visible = filterResources(all, StatusFilter.all, '');
      expect(isAllVisibleSelected(visible, {'a'}), isTrue);
      expect(isAllVisibleSelected(visible, <String>{}), isFalse);
    });

    test('false when visible empty', () {
      expect(isAllVisibleSelected([], {'a'}), isFalse);
    });
  });
}
