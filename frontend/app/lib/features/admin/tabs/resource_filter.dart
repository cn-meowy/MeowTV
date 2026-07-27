import 'package:meowtv_mobile/shared/models/admin_config.dart';

/// 状态过滤选项（单选）。
enum StatusFilter { all, enabled, disabled, adult }

/// 按 [filter] 与 [query] 过滤资源列表。
///
/// [query] 为空或纯空白时不做关键字过滤。
/// 匹配字段：`title` / `configKey` / `value1`，大小写不敏感。
List<SysConfigItem> filterResources(
  List<SysConfigItem> all,
  StatusFilter filter,
  String query,
) {
  List<SysConfigItem> list;
  switch (filter) {
    case StatusFilter.enabled:
      list = all.where((r) => r.isEnabled).toList();
      break;
    case StatusFilter.disabled:
      list = all.where((r) => !r.isEnabled).toList();
      break;
    case StatusFilter.adult:
      list = all.where((r) => r.value5 == '1').toList();
      break;
    case StatusFilter.all:
      list = List.of(all);
      break;
  }
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    list = list.where((r) {
      return r.title.toLowerCase().contains(q) ||
          r.configKey.toLowerCase().contains(q) ||
          r.value1.toLowerCase().contains(q);
    }).toList();
  }
  return list;
}

/// 对 [visible] 中每个 key 翻转选中状态，返回新集合。
/// 不在 [visible] 中的已选 key 保持不变。
Set<String> invertVisible(List<SysConfigItem> visible, Set<String> selected) {
  final next = Set<String>.from(selected);
  for (final r in visible) {
    final k = r.configKey;
    if (next.contains(k)) {
      next.remove(k);
    } else {
      next.add(k);
    }
  }
  return next;
}

/// 将 [visible] 全部加入选中集合。
Set<String> selectAllVisible(
    List<SysConfigItem> visible, Set<String> selected) {
  final next = Set<String>.from(selected);
  for (final r in visible) {
    next.add(r.configKey);
  }
  return next;
}

/// 将 [visible] 全部从选中集合移除，保留其余已选项。
Set<String> clearVisible(
    List<SysConfigItem> visible, Set<String> selected) {
  final next = Set<String>.from(selected);
  for (final r in visible) {
    next.remove(r.configKey);
  }
  return next;
}

/// 返回 18禁（`value5 == '1'`）资源的 configKey 集合。
Set<String> adultKeysOf(List<SysConfigItem> all) {
  return all.where((r) => r.value5 == '1').map((r) => r.configKey).toSet();
}

/// 判断当前可见列表是否全部已选。
/// 可见列表为空时返回 false。
bool isAllVisibleSelected(List<SysConfigItem> visible, Set<String> selected) {
  if (visible.isEmpty) return false;
  return visible.every((r) => selected.contains(r.configKey));
}
