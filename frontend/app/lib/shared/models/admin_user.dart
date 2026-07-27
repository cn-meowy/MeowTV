/// 管理员用户模型 — mirrors Web UserListItem.
class UserListItem {
  final int id;
  final String username;
  final String nickname;
  final int role;
  final int status;
  final int? groupId;
  final String groupName;
  final String? lastLoginAt;
  final String createdAt;

  const UserListItem({
    required this.id,
    required this.username,
    required this.nickname,
    required this.role,
    required this.status,
    this.groupId,
    this.groupName = '',
    this.lastLoginAt,
    required this.createdAt,
  });

  factory UserListItem.fromJson(Map<String, dynamic> j) => UserListItem(
    id: j['id'] as int? ?? 0,
    username: j['username'] as String? ?? '',
    nickname: j['nickname'] as String? ?? '',
    role: j['role'] as int? ?? 0,
    status: j['status'] as int? ?? 1,
    groupId: j['group_id'] as int?,
    groupName: j['group_name'] as String? ?? '',
    lastLoginAt: j['last_login_at'] as String?,
    createdAt: j['created_at'] as String? ?? '',
  );
}

/// 分页数据包装
class PaginatedData<T> {
  final List<T> items;
  final int total;

  const PaginatedData({required this.items, required this.total});
}
