import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/admin_user.dart';
import '../../../shared/models/admin_group.dart';
import '../../../shared/models/admin_config.dart';
import '../admin_provider.dart';
import 'resource_filter.dart';

class UserTab extends ConsumerStatefulWidget {
  const UserTab({super.key});

  @override
  ConsumerState<UserTab> createState() => _UserTabState();
}

class _UserTabState extends ConsumerState<UserTab>
    with SingleTickerProviderStateMixin {
  late TabController _subTabCtrl;

  @override
  void initState() {
    super.initState();
    _subTabCtrl = TabController(length: 2, vsync: this);
    Future.microtask(() {
      ref.read(adminProvider.notifier).fetchUserList();
      ref.read(adminProvider.notifier).fetchGroupList();
    });
  }

  @override
  void dispose() {
    _subTabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(children: [
      TabBar(
        controller: _subTabCtrl,
        tabs: const [Tab(text: '用户列表'), Tab(text: '用户组')],
        labelColor: colors.primary,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: colors.primary,
      ),
      Expanded(
        child: TabBarView(controller: _subTabCtrl, children: const [
          _UserListSubTab(),
          _UserGroupSubTab(),
        ]),
      ),
    ]);
  }
}

// ── User List Sub Tab ────────────────────────────────────────────────────────

class _UserListSubTab extends ConsumerStatefulWidget {
  const _UserListSubTab();

  @override
  ConsumerState<_UserListSubTab> createState() => _UserListSubTabState();
}

class _UserListSubTabState extends ConsumerState<_UserListSubTab> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(adminProvider);
    final users = state.userPage?.items ?? [];

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: colors.primary,
        foregroundColor: colors.textInverse,
        mini: true,
        child: const Icon(Icons.person_add),
        onPressed: () => _showCreateUserDialog(),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(adminProvider.notifier).fetchUserList(),
        child: state.loading && users.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : users.isEmpty
                ? _emptyState(colors)
                : ListView.builder(
                    padding: const EdgeInsets.all(AppTheme.md),
                    itemCount: users.length,
                    itemBuilder: (_, i) => _userCard(users[i], colors),
                  ),
      ),
    );
  }

  Widget _emptyState(AppColors colors) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.people_outline, size: 48, color: colors.textMuted),
          const SizedBox(height: AppTheme.sm),
          Text('暂无用户', style: TextStyle(color: colors.textSecondary)),
          const SizedBox(height: AppTheme.md),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.textInverse),
            onPressed: () => _showCreateUserDialog(),
            child: const Text('创建用户'),
          ),
        ]),
      );

  Widget _userCard(UserListItem u, AppColors colors) => Container(
        margin: const EdgeInsets.only(bottom: AppTheme.sm),
        padding: const EdgeInsets.all(AppTheme.md),
        decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(u.nickname.isNotEmpty ? u.nickname : u.username,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            // 状态标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: u.status == 1
                    ? colors.success.withValues(alpha: 0.2)
                    : colors.error.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(u.status == 1 ? '正常' : '禁用',
                  style: TextStyle(
                      color: u.status == 1 ? colors.success : colors.error,
                      fontSize: 11)),
            ),
            const SizedBox(width: 6),
            // 角色标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: u.role == 1
                    ? colors.primary.withValues(alpha: 0.2)
                    : colors.textMuted.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(u.role == 1 ? '管理员' : '用户',
                  style: TextStyle(
                      color: u.role == 1 ? colors.primary : colors.textSecondary,
                      fontSize: 11)),
            ),
          ]),
          const SizedBox(height: AppTheme.xs),
          Text('@${u.username}',
              style: TextStyle(color: colors.textSecondary, fontSize: 12)),
          if (u.groupName.isNotEmpty)
            Text('用户组: ${u.groupName}',
                style: TextStyle(color: colors.textSecondary, fontSize: 12)),
          if (u.lastLoginAt != null && u.lastLoginAt!.isNotEmpty)
            Text('最后登录: ${u.lastLoginAt}',
                style: TextStyle(color: colors.textMuted, fontSize: 11)),
          Text('创建: ${u.createdAt}',
              style: TextStyle(color: colors.textMuted, fontSize: 11)),
          Divider(height: 20, color: colors.divider),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => _showEditUserDialog(u),
              child: Text('编辑', style: TextStyle(color: colors.primary)),
            ),
            TextButton(
              onPressed: () => _showResetPasswordDialog(u),
              child: Text('重置密码', style: TextStyle(color: colors.warning)),
            ),
            if (u.role != 1)
              TextButton(
                onPressed: () => _confirmDeleteUser(u),
                child: Text('删除', style: TextStyle(color: colors.error)),
              ),
          ]),
        ]),
      );

  // ── 创建用户 ──────────────────────────────────────────────────────────────

  void _showCreateUserDialog() {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final nicknameCtrl = TextEditingController();
    int role = 0;
    int? groupId;
    bool creating = false;
    final colors = context.colors;
    final groups = ref.read(adminProvider).groups;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final dialogColors = ctx.colors;
          return AlertDialog(
            backgroundColor: dialogColors.card,
            title: Text('创建用户', style: TextStyle(color: dialogColors.textPrimary)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _dialogField(usernameCtrl, '用户名', dialogColors),
                _dialogField(passwordCtrl, '密码', dialogColors, obscure: true),
                _dialogField(nicknameCtrl, '昵称', dialogColors),
                DropdownButtonFormField<int>(
                  initialValue: role,
                  decoration: InputDecoration(
                    labelText: '角色',
                    labelStyle: TextStyle(color: dialogColors.textSecondary),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.border)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.primary)),
                  ),
                  dropdownColor: dialogColors.card,
                  style: TextStyle(color: dialogColors.textPrimary, fontSize: 14),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('普通用户')),
                    DropdownMenuItem(value: 1, child: Text('管理员')),
                  ],
                  onChanged: (v) => setDialogState(() => role = v ?? 0),
                ),
                const SizedBox(height: AppTheme.sm),
                DropdownButtonFormField<int>(
                  initialValue: groupId,
                  decoration: InputDecoration(
                    labelText: '用户组',
                    labelStyle: TextStyle(color: dialogColors.textSecondary),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.border)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.primary)),
                  ),
                  dropdownColor: dialogColors.card,
                  style: TextStyle(color: dialogColors.textPrimary, fontSize: 14),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('未分组')),
                    ...groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))),
                  ],
                  onChanged: (v) => setDialogState(() => groupId = v),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: dialogColors.primary, foregroundColor: dialogColors.textInverse),
                onPressed: creating ? null : () async {
                  if (usernameCtrl.text.isEmpty || passwordCtrl.text.length < 6) return;
                  setDialogState(() => creating = true);
                  final ok = await ref.read(adminProvider.notifier).createUser(
                    username: usernameCtrl.text,
                    password: passwordCtrl.text,
                    nickname: nicknameCtrl.text,
                    role: role,
                  );
                  // 创建用户成功后，设置用户组
                  if (ok && groupId != null) {
                    await ref.read(adminProvider.notifier).setUserGroup(
                      userId: ref.read(adminProvider).userPage?.items.last.id ?? 0,
                      groupId: groupId!,
                    );
                  }
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    _showSnack(ok ? '用户创建成功' : '创建失败', ok ? colors.success : colors.error);
                  }
                },
                child: creating
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: colors.textInverse))
                    : const Text('创建'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── 编辑用户 ──────────────────────────────────────────────────────────────

  void _showEditUserDialog(UserListItem u) {
    final nicknameCtrl = TextEditingController(text: u.nickname);
    int role = u.role;
    int status = u.status;
    int? groupId = u.groupId;
    bool saving = false;
    final colors = context.colors;
    final groups = ref.read(adminProvider).groups;
    final originalGroupId = u.groupId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final dialogColors = ctx.colors;
          return AlertDialog(
            backgroundColor: dialogColors.card,
            title: Text('编辑用户 - ${u.username}', style: TextStyle(color: dialogColors.textPrimary)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _dialogField(nicknameCtrl, '昵称', dialogColors),
                DropdownButtonFormField<int>(
                  initialValue: role,
                  decoration: InputDecoration(
                    labelText: '角色',
                    labelStyle: TextStyle(color: dialogColors.textSecondary),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.border)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.primary)),
                  ),
                  dropdownColor: dialogColors.card,
                  style: TextStyle(color: dialogColors.textPrimary, fontSize: 14),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('普通用户')),
                    DropdownMenuItem(value: 1, child: Text('管理员')),
                  ],
                  onChanged: (v) => setDialogState(() => role = v ?? 0),
                ),
                DropdownButtonFormField<int>(
                  initialValue: status,
                  decoration: InputDecoration(
                    labelText: '状态',
                    labelStyle: TextStyle(color: dialogColors.textSecondary),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.border)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.primary)),
                  ),
                  dropdownColor: dialogColors.card,
                  style: TextStyle(color: dialogColors.textPrimary, fontSize: 14),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('正常')),
                    DropdownMenuItem(value: 0, child: Text('禁用')),
                  ],
                  onChanged: (v) => setDialogState(() => status = v ?? 1),
                ),
                const SizedBox(height: AppTheme.sm),
                DropdownButtonFormField<int>(
                  initialValue: groupId,
                  decoration: InputDecoration(
                    labelText: '用户组',
                    labelStyle: TextStyle(color: dialogColors.textSecondary),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.border)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.primary)),
                  ),
                  dropdownColor: dialogColors.card,
                  style: TextStyle(color: dialogColors.textPrimary, fontSize: 14),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('未分组')),
                    ...groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))),
                  ],
                  onChanged: (v) => setDialogState(() => groupId = v),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: dialogColors.primary, foregroundColor: dialogColors.textInverse),
                onPressed: saving ? null : () async {
                  setDialogState(() => saving = true);
                  final ok = await ref.read(adminProvider.notifier).updateUser(
                    id: u.id,
                    nickname: nicknameCtrl.text,
                    role: role,
                    status: status,
                  );
                  // 如果用户组发生了变化，调用 setUserGroup
                  if (ok && groupId != originalGroupId) {
                    if (groupId != null) {
                      await ref.read(adminProvider.notifier).setUserGroup(
                        userId: u.id,
                        groupId: groupId!,
                      );
                    } else {
                      // 设置为未分组：传入 groupId=0 让后端清除关联
                      await ref.read(adminProvider.notifier).setUserGroup(
                        userId: u.id,
                        groupId: 0,
                      );
                    }
                    // 刷新用户列表以显示新的用户组名称
                    await ref.read(adminProvider.notifier).fetchUserList();
                  }
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    _showSnack(ok ? '用户已更新' : '更新失败', ok ? colors.success : colors.error);
                  }
                },
                child: saving
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: colors.textInverse))
                    : const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── 重置密码 ──────────────────────────────────────────────────────────────

  void _showResetPasswordDialog(UserListItem u) {
    final colors = context.colors;
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        final dialogColors = ctx.colors;
        return AlertDialog(
          backgroundColor: dialogColors.card,
          title: Text('重置密码 - ${u.username}',
              style: TextStyle(color: dialogColors.textPrimary)),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            style: TextStyle(color: dialogColors.textPrimary),
            decoration: InputDecoration(
              labelText: '新密码',
              labelStyle: TextStyle(color: dialogColors.textSecondary),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.border)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.primary)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: colors.warning, foregroundColor: colors.textInverse),
              onPressed: () async {
                if (ctrl.text.length < 6) return;
                final ok = await ref.read(adminProvider.notifier).resetUserPassword(u.id, ctrl.text);
                if (ctx.mounted) { Navigator.pop(ctx); _showSnack(ok ? '重置成功' : '重置失败', ok ? colors.success : colors.error); }
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }

  // ── 删除用户 ──────────────────────────────────────────────────────────────

  void _confirmDeleteUser(UserListItem u) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) {
        final dialogColors = ctx.colors;
        return AlertDialog(
          backgroundColor: dialogColors.card,
          title: Text('确认删除', style: TextStyle(color: dialogColors.textPrimary)),
          content: Text('确定要删除用户 ${u.username} 吗？', style: TextStyle(color: dialogColors.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: dialogColors.error, foregroundColor: dialogColors.textInverse),
              onPressed: () async {
                final ok = await ref.read(adminProvider.notifier).deleteUser(u.id);
                if (ctx.mounted) { Navigator.pop(ctx); _showSnack(ok ? '删除成功' : '删除失败', ok ? colors.success : colors.error); }
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  Widget _dialogField(TextEditingController ctrl, String label, AppColors colors, {bool obscure = false}) =>
      TextField(
        controller: ctrl,
        obscureText: obscure,
        style: TextStyle(color: colors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: colors.textSecondary),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: colors.border)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: colors.primary)),
        ),
      );

  void _showSnack(String msg, Color c) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: c));
}

// ── User Group Sub Tab ───────────────────────────────────────────────────────

class _UserGroupSubTab extends ConsumerStatefulWidget {
  const _UserGroupSubTab();

  @override
  ConsumerState<_UserGroupSubTab> createState() => _UserGroupSubTabState();
}

class _UserGroupSubTabState extends ConsumerState<_UserGroupSubTab> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final groups = ref.watch(adminProvider).groups;
    return RefreshIndicator(
      onRefresh: () => ref.read(adminProvider.notifier).fetchGroupList(),
      child: groups.isEmpty
          ? _emptyState(colors)
          : ListView.builder(
              padding: const EdgeInsets.all(AppTheme.md),
              itemCount: groups.length,
              itemBuilder: (_, i) => _groupCard(groups[i], colors),
            ),
    );
  }

  Widget _emptyState(AppColors colors) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('暂无用户组', style: TextStyle(color: colors.textSecondary)),
      const SizedBox(height: AppTheme.md),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: colors.primary, foregroundColor: colors.textInverse),
        onPressed: () => _showCreateGroupDialog(),
        child: const Text('创建用户组'),
      ),
    ]),
  );

  Widget _groupCard(UserGroupItem g, AppColors colors) => Container(
    margin: const EdgeInsets.only(bottom: AppTheme.sm),
    padding: const EdgeInsets.all(AppTheme.md),
    decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(g.name, style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
      if (g.remark.isNotEmpty) Text(g.remark, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
      Text('用户: ${g.userCount}  资源: ${g.resourceCount}',
          style: TextStyle(color: colors.textMuted, fontSize: 11)),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(onPressed: () => _showResourceConfigDialog(g), child: Text('配置资源', style: TextStyle(color: colors.success))),
        TextButton(onPressed: () => _showEditGroupDialog(g), child: Text('编辑', style: TextStyle(color: colors.primary))),
        TextButton(onPressed: () => _confirmDeleteGroup(g), child: Text('删除', style: TextStyle(color: colors.error))),
      ]),
    ]),
  );

  void _showCreateGroupDialog() => _showGroupDialog(null);

  void _showEditGroupDialog(UserGroupItem g) => _showGroupDialog(g);

  void _showGroupDialog(UserGroupItem? existing) {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final remarkCtrl = TextEditingController(text: existing?.remark ?? '');
    final colors = context.colors;

    showDialog(
      context: context,
      builder: (ctx) {
        final dialogColors = ctx.colors;
        return AlertDialog(
          backgroundColor: dialogColors.card,
          title: Text(isEdit ? '编辑用户组' : '创建用户组', style: TextStyle(color: dialogColors.textPrimary)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, style: TextStyle(color: dialogColors.textPrimary),
              decoration: InputDecoration(labelText: '名称', labelStyle: TextStyle(color: dialogColors.textSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.border)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.primary)))),
            TextField(controller: remarkCtrl, style: TextStyle(color: dialogColors.textPrimary),
              decoration: InputDecoration(labelText: '备注', labelStyle: TextStyle(color: dialogColors.textSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.border)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: dialogColors.primary)))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: dialogColors.primary, foregroundColor: dialogColors.textInverse),
              onPressed: () async {
                bool ok;
                if (isEdit) {
                  ok = await ref.read(adminProvider.notifier).updateGroup(id: existing.id, name: nameCtrl.text, remark: remarkCtrl.text);
                } else {
                  ok = await ref.read(adminProvider.notifier).createGroup(name: nameCtrl.text, remark: remarkCtrl.text);
                }
                if (ctx.mounted) { Navigator.pop(ctx); _showSnack(ok ? '操作成功' : '操作失败', ok ? colors.success : colors.error); }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  /// 资源配置对话框
  void _showResourceConfigDialog(UserGroupItem g) async {
    await ref.read(adminProvider.notifier).fetchConfigList(group: 'resource_site');
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => _ResourceConfigDialog(groupId: g.id, groupName: g.name),
    );
  }

  void _confirmDeleteGroup(UserGroupItem g) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) {
        final dialogColors = ctx.colors;
        return AlertDialog(
          backgroundColor: dialogColors.card,
          title: Text('确认删除', style: TextStyle(color: dialogColors.textPrimary)),
          content: Text('确定要删除用户组 ${g.name} 吗？', style: TextStyle(color: dialogColors.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: dialogColors.error, foregroundColor: dialogColors.textInverse),
              onPressed: () async {
                final ok = await ref.read(adminProvider.notifier).deleteGroup(g.id);
                if (ctx.mounted) { Navigator.pop(ctx); _showSnack(ok ? '删除成功' : '删除失败', ok ? colors.success : colors.error); }
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String msg, Color c) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: c));
}

// ── 资源配置对话框 ──────────────────────────────────────────────────────────

class _ResourceConfigDialog extends ConsumerStatefulWidget {
  final int groupId;
  final String groupName;
  const _ResourceConfigDialog({required this.groupId, required this.groupName});

  @override
  ConsumerState<_ResourceConfigDialog> createState() => _ResourceConfigDialogState();
}

class _ResourceConfigDialogState extends ConsumerState<_ResourceConfigDialog> {
  List<SysConfigItem> _allResources = [];
  Set<String> _selectedKeys = {};
  bool _loading = true;
  bool _saving = false;

  // 过滤与批量
  String _searchQuery = '';
  StatusFilter _statusFilter = StatusFilter.all;
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final detail = await ref.read(adminProvider.notifier).fetchGroupDetail(widget.groupId);
      final resources = ref.read(adminProvider).configItems;
      if (mounted) {
        setState(() {
          _allResources = resources;
          _selectedKeys = Set<String>.from(detail?.configKeys ?? []);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── 选择操作 ──────────────────────────────────────────────
  void _togglePill(String key) {
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  void _onSearchChanged(String v) {
    setState(() => _searchQuery = v.trim());
  }

  void _onStatusFilterChanged(StatusFilter f) {
    setState(() => _statusFilter = f);
  }

  void _toggleAllVisible() {
    final visible = filterResources(_allResources, _statusFilter, _searchQuery);
    setState(() {
      if (isAllVisibleSelected(visible, _selectedKeys)) {
        _selectedKeys = clearVisible(visible, _selectedKeys);
      } else {
        _selectedKeys = selectAllVisible(visible, _selectedKeys);
      }
    });
  }

  void _toggleAdult() {
    final adultKeys = adultKeysOf(_allResources);
    setState(() {
      if (adultKeys.every(_selectedKeys.contains)) {
        _selectedKeys.removeAll(adultKeys);
      } else {
        _selectedKeys.addAll(adultKeys);
      }
    });
  }

  void _invertVisible() {
    final visible = filterResources(_allResources, _statusFilter, _searchQuery);
    setState(() => _selectedKeys = invertVisible(visible, _selectedKeys));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final visible = filterResources(_allResources, _statusFilter, _searchQuery);
    final allSelected = isAllVisibleSelected(visible, _selectedKeys);

    return AlertDialog(
      backgroundColor: colors.card,
      // 撑开对话框宽度：减小水平 inset，允许更宽的 pill 网格
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      title: Row(children: [
        Expanded(child: Text('配置资源 — ${widget.groupName}', style: TextStyle(color: colors.textPrimary))),
        IconButton(icon: Icon(Icons.close, color: colors.textMuted), onPressed: () => Navigator.pop(context)),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 560),
        child: SizedBox(
          width: double.maxFinite,
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _allResources.isEmpty
                ? Text('暂无资源站点，请先在"资源组管理"中添加', style: TextStyle(color: colors.textSecondary))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 搜索框
                      TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search, size: 18, color: colors.textMuted),
                          hintText: '搜索标题 / key / 域名',
                          hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
                          filled: true,
                          fillColor: colors.elevated,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: colors.border, width: 1),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: colors.border, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: colors.primary, width: 1.5),
                          ),
                        ),
                        style: TextStyle(color: colors.textPrimary, fontSize: 13),
                        onChanged: _onSearchChanged,
                      ),
                      const SizedBox(height: 8),
                      // 状态过滤
                      _StatusFilterChipRow(
                        current: _statusFilter,
                        onChanged: _onStatusFilterChanged,
                      ),
                      const SizedBox(height: 8),
                      // 工具栏（全选/18禁/反选 + 计数）
                      _ToolbarRow(
                        allSelected: allSelected,
                        visibleCount: visible.length,
                        selectedCount: _selectedKeys.length,
                        totalCount: _allResources.length,
                        onToggleAll: _toggleAllVisible,
                        onToggleAdult: _toggleAdult,
                        onInvert: _invertVisible,
                      ),
                      const SizedBox(height: 8),
                      // 资源网格（可滚动）
                      Flexible(
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final res in visible)
                                _ResourcePill(
                                  item: res,
                                  selected: _selectedKeys.contains(res.configKey),
                                  onTap: () => _togglePill(res.configKey),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                   ),
         ),
       ),
      actions: [
        Text('已选择 ${_selectedKeys.length} / ${_allResources.length}',
            style: TextStyle(color: colors.textMuted, fontSize: 12)),
        const SizedBox(width: 16),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: colors.primary, foregroundColor: colors.textInverse),
          onPressed: _saving ? null : () async {
            setState(() => _saving = true);
            final ok = await ref.read(adminProvider.notifier).setGroupResources(
              groupId: widget.groupId,
              configKeys: _selectedKeys.toList(),
            );
            if (!context.mounted) return;
            // 在 pop 之前先取 messenger，避免 pop 后对话框 context 脱离树导致找不到 Scaffold
            final messenger = ScaffoldMessenger.of(context);
            setState(() => _saving = false);
            Navigator.pop(context);
            messenger.showSnackBar(
              SnackBar(content: Text(ok ? '资源配置已保存' : '保存失败'), backgroundColor: ok ? colors.success : colors.error),
            );
          },
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('保存配置'),
        ),
      ],
    );
  }
}

// ── 资源 pill ──────────────────────────────────────────────────────────────
class _ResourcePill extends StatelessWidget {
  final SysConfigItem item;
  final bool selected;
  final VoidCallback onTap;
  final GlobalKey _key = GlobalKey();

  _ResourcePill({required this.item, required this.selected, required this.onTap});

  GlobalKey get globalKey => _key;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isAdult = item.value5 == '1';
    final unsearchable = item.value6 == '0';
    final disabled = !item.isEnabled;
    final title = item.title.isNotEmpty ? item.title : item.configKey;

    Color bg;
    Color fg;
    Border? border;
    if (disabled) {
      bg = colors.elevated.withValues(alpha: 0.5);
      fg = colors.textMuted;
      border = Border.all(color: colors.border, width: 1);
    } else if (selected) {
      bg = colors.primary.withValues(alpha: 0.15);
      fg = colors.primary;
      border = Border.all(color: colors.primary, width: 1.5);
    } else {
      bg = colors.elevated;
      fg = colors.textSecondary;
      border = Border.all(color: colors.border, width: 1);
    }

    return Tooltip(
      message: '$title\n${item.configKey}\n${item.value1}${isAdult ? '\n18禁' : ''}${unsearchable ? '\n不可搜索' : ''}',
      preferBelow: false,
      child: GestureDetector(
        key: _key,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_box : Icons.check_box_outline_blank,
                size: 14,
                color: fg,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 12, decoration: disabled ? TextDecoration.lineThrough : null),
                ),
              ),
              if (isAdult) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: colors.error.withValues(alpha: 0.4), width: 0.8),
                  ),
                  child: Text('18', style: TextStyle(color: colors.error, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── 状态过滤 chip 行 ───────────────────────────────────────────────────────
class _StatusFilterChipRow extends StatelessWidget {
  final StatusFilter current;
  final ValueChanged<StatusFilter> onChanged;

  const _StatusFilterChipRow({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final options = [
      (StatusFilter.all, '全部'),
      (StatusFilter.enabled, '启用'),
      (StatusFilter.disabled, '禁用'),
      (StatusFilter.adult, '18禁'),
    ];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final (f, label) = options[i];
          final active = f == current;
          return GestureDetector(
            onTap: () => onChanged(f),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: active ? colors.primary : colors.elevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: active ? colors.primary : colors.border, width: 1),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: active ? colors.textInverse : colors.textSecondary,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── 工具栏（全选/18禁/反选 + 计数） ────────────────────────────────────────
class _ToolbarRow extends StatelessWidget {
  final bool allSelected;
  final int visibleCount;
  final int selectedCount;
  final int totalCount;
  final VoidCallback onToggleAll;
  final VoidCallback onToggleAdult;
  final VoidCallback onInvert;

  const _ToolbarRow({
    required this.allSelected,
    required this.visibleCount,
    required this.selectedCount,
    required this.totalCount,
    required this.onToggleAll,
    required this.onToggleAdult,
    required this.onInvert,
  });

  Widget _chip(BuildContext context, String label, VoidCallback onTap, {bool active = false}) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? colors.primary.withValues(alpha: 0.12) : colors.elevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? colors.primary : colors.border, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? colors.primary : colors.textSecondary,
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip(context, allSelected ? '取消全选' : '全选', onToggleAll, active: allSelected),
        const SizedBox(width: 6),
        _chip(context, '18禁', onToggleAdult),
        const SizedBox(width: 6),
        _chip(context, '反选', onInvert),
        const Spacer(),
        Text(
          '$selectedCount/$totalCount',
          style: TextStyle(color: context.colors.textMuted, fontSize: 11),
        ),
        const SizedBox(width: 4),
        Text(
          '($visibleCount 可见)',
          style: TextStyle(color: context.colors.textMuted, fontSize: 10),
        ),
      ],
    );
  }
}
