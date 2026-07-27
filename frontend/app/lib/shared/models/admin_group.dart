/// 用户组模型 — mirrors Web UserGroupItem.
class UserGroupItem {
  final int id;
  final String name;
  final String remark;
  final int userCount;
  final int resourceCount;

  const UserGroupItem({
    required this.id,
    required this.name,
    required this.remark,
    required this.userCount,
    required this.resourceCount,
  });

  factory UserGroupItem.fromJson(Map<String, dynamic> j) => UserGroupItem(
    id: j['id'] as int? ?? 0,
    name: j['name'] as String? ?? '',
    remark: j['remark'] as String? ?? '',
    userCount: j['user_count'] as int? ?? 0,
    resourceCount: j['resource_count'] as int? ?? 0,
  );
}

/// 用户组详情（含关联资源 config_keys）
class GroupDetailResponse {
  final int id;
  final String name;
  final String remark;
  final List<String> configKeys;

  const GroupDetailResponse({
    required this.id,
    required this.name,
    required this.remark,
    required this.configKeys,
  });

  factory GroupDetailResponse.fromJson(Map<String, dynamic> j) => GroupDetailResponse(
    id: j['id'] as int? ?? 0,
    name: j['name'] as String? ?? '',
    remark: j['remark'] as String? ?? '',
    configKeys: (j['config_keys'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [],
  );
}
