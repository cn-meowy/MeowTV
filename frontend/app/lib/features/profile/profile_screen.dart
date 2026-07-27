import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/cache/cache_meta.dart';
import '../../core/cache/video_cache_proxy.dart';
import '../../core/stream/stream_cache_config.dart';
import '../../core/stream/stream_cache_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/utils/url_utils.dart';
import '../../shared/models/enums.dart';
import '../../shared/models/user_profile.dart';
import '../../shared/widgets/ink_list_tile.dart';
import '../auth/auth_provider.dart';
import '../settings/theme_provider.dart';
import '../settings/douban_image_proxy_provider.dart';
import '../settings/buffer_mode_provider.dart';
import '../../core/cache/play_cache_service.dart';
import '../../shared/widgets/cache_icons.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final profile = authState.profile;
    final username = authState.username ?? '用户';
    final colors = context.colors;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              // Profile header
              Padding(
                padding: const EdgeInsets.all(AppTheme.md),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.card,
                        border: Border.all(color: colors.primary.withValues(alpha: 0.3), width: 2),
                      ),
                      child: Center(
                        child: Text(
                          username.isNotEmpty ? username[0].toUpperCase() : 'U',
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      profile?.nickname ?? username,
                      style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    if (profile != null) ...[
                      const SizedBox(height: 4),
                      Text('@${profile.username}', style: TextStyle(color: colors.textMuted, fontSize: 13)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Quick links — 收藏/历史/下载
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
                child: Row(
                  children: [
                    _QuickLink(
                      icon: Icons.favorite_outline,
                      label: '收藏',
                      onTap: () => context.push('/favorites'),
                    ),
                    _QuickLink(
                      icon: Icons.history,
                      label: '历史',
                      onTap: () => context.push('/history'),
                    ),
                    _QuickLink(
                      icon: Icons.download_outlined,
                      label: '下载',
                      onTap: () => context.push('/downloads'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: colors.divider, height: 1),
              const SizedBox(height: 8),
              // Settings list
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
                child: Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.person_outline,
                      title: '账号设置',
                      subtitle: '修改昵称、密码、在线设备管理',
                      onTap: () => _showAccountSettings(context, ref),
                    ),
                    _SettingsTile(
                      icon: Icons.palette_outlined,
                      title: '主题切换',
                      subtitle: _themeLabel(ref.watch(themeProvider)),
                      onTap: () => _showThemePicker(context, ref),
                    ),
                    _SettingsTile(
                      icon: Icons.dns_outlined,
                      title: '服务器地址',
                      subtitle: authState.baseUrl ?? '未设置',
                      onTap: () => _showServerConfig(context, ref),
                    ),
                    _SettingsTile(
                      icon: Icons.image_outlined,
                      title: '豆瓣图片代理',
                      subtitle: _proxyModeLabel(ref.watch(doubanImageProxyProvider).mode),
                      onTap: () => _showProxyModePicker(context, ref),
                    ),
                    _SettingsTile(
                      icon: Icons.play_circle_outline,
                      title: '缓冲模式',
                      subtitle: ref.watch(bufferModeProvider).mode.label,
                      onTap: () => _showBufferModePicker(context, ref),
                    ),
                    // _SettingsTile(
                    //   icon: Icons.high_quality_outlined,
                    //   title: '缓冲清晰度',
                    //   subtitle: '功能开发中',
                    //   enabled: false,
                    //   onTap: () {},
                    // ),
                    _SettingsTile(
                      icon: Icons.folder_outlined,
                      leadingWidget: CacheIcons.cache(size: 22, color: colors.textSecondary),
                      title: '播放缓存管理',
                      subtitle: '查看缓存大小并清理',
                      onTap: () => _showCacheManagement(context, ref),
                    ),
                    _SettingsTile(
                      icon: Icons.qr_code_scanner,
                      title: '扫码登录',
                      subtitle: '扫描二维码完成登录',
                      onTap: () => context.push('/qrcode-scan'),
                    ),
                    if (profile?.role == 1)
                      _SettingsTile(
                        icon: Icons.admin_panel_settings_outlined,
                        title: '后台管理',
                        subtitle: '订阅、资源组、用户、下载、豆瓣配置',
                        onTap: () => context.push('/admin-settings'),
                      ),
                    _SettingsTile(
                      icon: Icons.info_outline,
                      title: '关于',
                      subtitle: 'v1.0.0',
                      onTap: () => context.push('/about'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: colors.divider, height: 1),
              const SizedBox(height: 8),
              // Logout
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
                child: _SettingsTile(
                  icon: Icons.logout,
                  title: '退出登录',
                  titleColor: colors.error,
                  onTap: () => _showLogoutDialog(context, ref),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  String _themeLabel(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.dark: return '深色';
      case AppThemeMode.light: return '浅色';
      case AppThemeMode.system: return '跟随系统';
    }
  }

  String _proxyModeLabel(DoubanImageProxyMode mode) {
    switch (mode) {
      case DoubanImageProxyMode.backend: return '后端代理';
      case DoubanImageProxyMode.frontend: return '前端代理';
    }
  }

  void _showProxyModePicker(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final current = ref.read(doubanImageProxyProvider).mode;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('选择豆瓣图片代理模式',
                    style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              InkListTile(
                leading: Icon(Icons.dns_outlined,
                    color: current == DoubanImageProxyMode.backend ? colors.primary : colors.textSecondary),
                title: Text('后端代理',
                    style: TextStyle(color: current == DoubanImageProxyMode.backend ? colors.primary : colors.textPrimary)),
                subtitle: Text('通过服务器转发豆瓣图片，稳定可靠',
                    style: TextStyle(color: colors.textMuted, fontSize: 12)),
                trailing: current == DoubanImageProxyMode.backend
                    ? Icon(Icons.check, color: colors.primary) : null,
                onTap: () {
                  ref.read(doubanImageProxyProvider.notifier).setMode(DoubanImageProxyMode.backend);
                  Navigator.pop(context);
                },
              ),
              InkListTile(
                leading: Icon(Icons.speed_outlined,
                    color: current == DoubanImageProxyMode.frontend ? colors.primary : colors.textSecondary),
                title: Text('前端代理',
                    style: TextStyle(color: current == DoubanImageProxyMode.frontend ? colors.primary : colors.textPrimary)),
                subtitle: Text('直接加载豆瓣图片并设置请求头，延迟更低',
                    style: TextStyle(color: colors.textMuted, fontSize: 12)),
                trailing: current == DoubanImageProxyMode.frontend
                    ? Icon(Icons.check, color: colors.primary) : null,
                onTap: () {
                  ref.read(doubanImageProxyProvider.notifier).setMode(DoubanImageProxyMode.frontend);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBufferModePicker(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final current = ref.read(bufferModeProvider).mode;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('选择缓冲模式',
                    style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              InkListTile(
                leading: Icon(Icons.memory,
                    color: current == BufferMode.strategyA ? colors.primary : colors.textSecondary),
                title: Text('HLS 标准缓冲',
                    style: TextStyle(color: current == BufferMode.strategyA ? colors.primary : colors.textPrimary)),
                subtitle: Text('纯内存缓冲约 30s，退出后释放，适合临时观看',
                    style: TextStyle(color: colors.textMuted, fontSize: 12)),
                trailing: current == BufferMode.strategyA
                    ? Icon(Icons.check, color: colors.primary) : null,
                onTap: () {
                  ref.read(bufferModeProvider.notifier).setMode(BufferMode.strategyA);
                  Navigator.pop(context);
                },
              ),
              InkListTile(
                leading: Icon(Icons.download_for_offline_outlined,
                    color: current == BufferMode.strategyB ? colors.primary : colors.textSecondary),
                title: Text('边播边下',
                    style: TextStyle(color: current == BufferMode.strategyB ? colors.primary : colors.textPrimary)),
                subtitle: Text('边播边缓存到磁盘，播放完成后保留，适合追剧',
                    style: TextStyle(color: colors.textMuted, fontSize: 12)),
                trailing: current == BufferMode.strategyB
                    ? Icon(Icons.check, color: colors.primary) : null,
                onTap: () {
                  ref.read(bufferModeProvider.notifier).setMode(BufferMode.strategyB);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCacheManagement(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CacheManagementSheet(),
    );
  }

  void _showAccountSettings(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _AccountSettingsSheet(),
    );
  }

  void _showThemePicker(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final current = ref.read(themeProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.all(16), child: Text('选择主题', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600))),
              ...AppThemeMode.values.map((mode) => InkListTile(
                leading: Icon(
                  mode == AppThemeMode.dark ? Icons.dark_mode : mode == AppThemeMode.light ? Icons.light_mode : Icons.brightness_auto,
                  color: current == mode ? colors.primary : colors.textSecondary,
                ),
                title: Text(_themeLabel(mode), style: TextStyle(color: current == mode ? colors.primary : colors.textPrimary)),
                trailing: current == mode ? Icon(Icons.check, color: colors.primary) : null,
                onTap: () {
                  ref.read(themeProvider.notifier).setTheme(mode);
                  Navigator.pop(context);
                },
              )),
            ],
          ),
        ),
      ),
    );
  }

  void _showServerConfig(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final controller = TextEditingController(text: ref.read(authProvider).baseUrl ?? '');
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('服务器地址', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(hintText: 'https://your-server.com', hintStyle: TextStyle(color: colors.textMuted)),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      final url = UrlUtils.normalize(controller.text.trim());
                      if (url.isNotEmpty) {
                        SecureStorageService.instance.write(key: 'server_base_url', value: url);
                        ref.read(apiClientProvider).setBaseUrl(url);
                      }
                      Navigator.pop(context);
                    },
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('退出登录', style: TextStyle(color: colors.textPrimary)),
        content: Text('确定要退出登录吗？', style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              // GoRouter's refreshListenable will auto-redirect to /login after logout
            },
            child: Text('退出', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickLink({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
          child: Column(
            children: [
              Icon(icon, color: colors.primary, size: 28),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  /// 自定义前导图标 Widget（SVG 等）。优先于 [icon] 使用。
  final Widget? leadingWidget;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final bool enabled;
  final VoidCallback onTap;
  const _SettingsTile({
    required this.icon,
    this.leadingWidget,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final effectiveEnabled = enabled;
    final effectiveTitleColor = effectiveEnabled ? (titleColor ?? colors.textPrimary) : colors.textMuted;
    final effectiveSubtitleColor = effectiveEnabled ? colors.textMuted : colors.textMuted.withValues(alpha: 0.5);
    final leading = leadingWidget ??
        Icon(icon, color: effectiveEnabled ? (titleColor ?? colors.textSecondary) : colors.textMuted, size: 22);
    return InkListTile(
      contentPadding: EdgeInsets.zero,
      leading: leading,
      title: Text(title, style: TextStyle(color: effectiveTitleColor, fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null ? Text(subtitle!, style: TextStyle(color: effectiveSubtitleColor, fontSize: 12)) : null,
      trailing: effectiveEnabled
          ? Icon(Icons.chevron_right, color: colors.textMuted, size: 20)
          : Icon(Icons.hourglass_empty, color: colors.textMuted, size: 20),
      onTap: () {
        if (!effectiveEnabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('功能开发中，敬请期待'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        onTap();
      },
    );
  }
}

class _AccountSettingsSheet extends ConsumerStatefulWidget {
  const _AccountSettingsSheet();

  @override
  ConsumerState<_AccountSettingsSheet> createState() => _AccountSettingsSheetState();
}

class _AccountSettingsSheetState extends ConsumerState<_AccountSettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final profile = ref.watch(authProvider).profile;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('账号设置', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              InkListTile(
                leading: Icon(Icons.person_outline, color: colors.textSecondary),
                title: Text('修改昵称', style: TextStyle(color: colors.textPrimary)),
                subtitle: Text(profile?.nickname ?? '', style: TextStyle(color: colors.textMuted)),
                onTap: () => _showNicknameDialog(context, profile),
              ),
              InkListTile(
                leading: Icon(Icons.lock_outline, color: colors.textSecondary),
                title: Text('修改密码', style: TextStyle(color: colors.textPrimary)),
                onTap: () => _showPasswordDialog(context),
              ),
              InkListTile(
                leading: Icon(Icons.devices_outlined, color: colors.textSecondary),
                title: Text('在线设备管理', style: TextStyle(color: colors.textPrimary)),
                onTap: () => _showDevicesSheet(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 修改昵称 ──────────────────────────────────────────────────────
  void _showNicknameDialog(BuildContext context, dynamic profile) {
    final colors = context.colors;
    final controller = TextEditingController(text: profile?.nickname ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('修改昵称', style: TextStyle(color: colors.textPrimary)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: '请输入新昵称',
            hintStyle: TextStyle(color: colors.textMuted),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final nickname = controller.text.trim();
              if (nickname.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await ref.read(apiClientProvider).post(
                  ApiConstants.userUpdate,
                  data: {'nickname': nickname},
                );
                await ref.read(authProvider.notifier).fetchProfile();
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('昵称修改成功'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('修改失败: $e'), backgroundColor: colors.error),
                  );
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ── 修改密码 ──────────────────────────────────────────────────────
  void _showPasswordDialog(BuildContext context) {
    final colors = context.colors;
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('修改密码', style: TextStyle(color: colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldCtrl,
              obscureText: true,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: '旧密码',
                hintStyle: TextStyle(color: colors.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: '新密码（至少6位）',
                hintStyle: TextStyle(color: colors.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: '确认新密码',
                hintStyle: TextStyle(color: colors.textMuted),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final oldPwd = oldCtrl.text;
              final newPwd = newCtrl.text;
              final confirmPwd = confirmCtrl.text;
              if (newPwd.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: const Text('新密码至少6位'), backgroundColor: colors.error),
                );
                return;
              }
              if (newPwd != confirmPwd) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: const Text('两次密码不一致'), backgroundColor: colors.error),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                await ref.read(apiClientProvider).post(
                  ApiConstants.userPassword,
                  data: {'old_password': oldPwd, 'new_password': newPwd},
                );
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('密码修改成功'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('修改失败: $e'), backgroundColor: colors.error),
                  );
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ── 在线设备管理 ──────────────────────────────────────────────────
  void _showDevicesSheet(BuildContext context) {
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _DevicesSheet(),
    );
  }
}

/// 在线设备管理 BottomSheet
class _DevicesSheet extends ConsumerStatefulWidget {
  const _DevicesSheet();

  @override
  ConsumerState<_DevicesSheet> createState() => _DevicesSheetState();
}

class _DevicesSheetState extends ConsumerState<_DevicesSheet> {
  List<DeviceInfo> _devices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchDevices();
  }

  Future<void> _fetchDevices() async {
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await ref.read(apiClientProvider).post<Map<String, dynamic>>(
        ApiConstants.userDevices,
      );
      final body = resp.data!;
      if (body['data'] != null) {
        final deviceResp = DeviceListResponse.fromJson(body['data'] as Map<String, dynamic>);
        setState(() { _devices = deviceResp.devices; _loading = false; });
      } else {
        setState(() { _devices = []; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _kickDevice(int deviceType) async {
    final colors = context.colors;
    try {
      await ref.read(apiClientProvider).post(
        ApiConstants.userKickDevice,
        data: {'device_type': deviceType},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('设备已踢出'), backgroundColor: Colors.green),
        );
      }
      await _fetchDevices();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('踢出失败: $e'), backgroundColor: colors.error),
        );
      }
    }
  }

  String _deviceTypeLabel(int type) {
    switch (type) {
      case 0: return 'Web';
      case 1: return 'Android';
      case 2: return 'iOS';
      case 3: return 'Apple TV';
      default: return '未知';
    }
  }

  IconData _deviceTypeIcon(int type) {
    switch (type) {
      case 0: return Icons.computer;
      case 1: return Icons.phone_android;
      case 2: return Icons.phone_iphone;
      case 3: return Icons.tv;
      default: return Icons.devices;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('在线设备', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.refresh, color: colors.textSecondary, size: 20),
                    onPressed: _fetchDevices,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loading)
                Center(child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(color: colors.primary),
                ))
              else if (_error != null)
                Center(child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(_error!, style: TextStyle(color: colors.error)),
                ))
              else if (_devices.isEmpty)
                Center(child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('暂无在线设备', style: TextStyle(color: colors.textMuted)),
                ))
              else
                ..._devices.map((d) => InkListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_deviceTypeIcon(d.deviceType), color: d.online ? colors.primary : colors.textMuted, size: 22),
                  title: Text(d.deviceName.isNotEmpty ? d.deviceName : _deviceTypeLabel(d.deviceType),
                      style: TextStyle(color: colors.textPrimary, fontSize: 14)),
                  subtitle: Text(
                    '${_deviceTypeLabel(d.deviceType)}${d.online ? ' · 在线' : ' · 离线'}',
                    style: TextStyle(color: d.online ? colors.primary : colors.textMuted, fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.close, color: colors.error, size: 18),
                    tooltip: '踢出设备',
                    onPressed: () => _kickDevice(d.deviceType),
                  ),
                )),
            ],
          ),
        ),
      ),
    );
  }
}

/// 播放缓存管理 Sheet
class _CacheManagementSheet extends ConsumerStatefulWidget {
  const _CacheManagementSheet();

  @override
  ConsumerState<_CacheManagementSheet> createState() => _CacheManagementSheetState();
}

class _CacheManagementSheetState extends ConsumerState<_CacheManagementSheet> {
  int _autoCacheSize = 0;
  int _manualCacheSize = 0;
  List<CacheMeta> _manualCacheList = [];
  int _streamCacheSize = 0;
  int _streamCacheMaxMB = StreamCacheConfig.defaultMaxCacheSizeMB;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCacheInfo();
  }

  Future<void> _loadCacheInfo() async {
    final autoSize = await PlayCacheService.instance.getAutoCacheSize();
    final manualSize = await PlayCacheService.instance.getManualCacheSize();
    final manualList = await PlayCacheService.instance.getManualCacheList();
    final streamSize = await StreamCacheManager.instance.getTotalCacheSize();
    final config = await StreamCacheConfig.load();
    
    if (mounted) {
      setState(() {
        _autoCacheSize = autoSize;
        _manualCacheSize = manualSize;
        _manualCacheList = manualList;
        _streamCacheSize = streamSize;
        _streamCacheMaxMB = config.maxCacheSizeMB;
        _isLoading = false;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  Future<void> _clearAutoCache() async {
    final bufferState = ref.read(bufferModeProvider);
    final maxSize = bufferState.autoCacheSizeLimit.bytes;
    
    // 调用 LRU 清理
    await PlayCacheService.instance.evictAutoCache(maxSizeBytes: maxSize);
    await _loadCacheInfo();
  }

  Future<void> _clearManualCache(String key) async {
    await PlayCacheService.instance.deleteManualCache(key);
    await _loadCacheInfo();
  }

  Future<void> _clearAllManualCache() async {
    for (final meta in _manualCacheList) {
      await PlayCacheService.instance.deleteManualCache(meta.key);
    }
    await _loadCacheInfo();
  }

  Future<void> _clearStreamCache() async {
    // 停止所有活跃的流代理 Session
    await VideoCacheProxyServer.instance.pauseActiveProxying();
    // 清理磁盘缓存
    await StreamCacheManager.instance.clearAllCache();
    await _loadCacheInfo();
  }

  void _showClearStreamCacheDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有流代理缓存（TS 分片）吗？正在播放的视频可能需要重新加载。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearStreamCache();
            },
            child: Text('清空', style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bufferState = ref.watch(bufferModeProvider);
    final maxSize = bufferState.autoCacheSizeLimit.bytes;
    final autoProgress = maxSize > 0 ? (_autoCacheSize / maxSize).clamp(0.0, 1.0) : 0.0;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('播放缓存管理',
                  style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),

              if (_isLoading)
                Center(child: CircularProgressIndicator(color: colors.primary))
              else ...[
                // 自动缓存区域
                _SectionHeader(
                  title: '自动缓存',
                  titleColor: colors.primary,
                  icon: CacheIcons.cacheAuto(size: 16, color: colors.primary),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_formatSize(_autoCacheSize)} / ${bufferState.autoCacheSizeLimit.label}',
                      style: TextStyle(color: colors.textSecondary, fontSize: 14),
                    ),
                    Text(
                      '${(autoProgress * 100).toStringAsFixed(1)}%',
                      style: TextStyle(color: colors.primary, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: autoProgress,
                    backgroundColor: colors.elevated,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                        label: const Text('清理自动缓存'),
                        onPressed: _clearAutoCache,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.primary,
                          side: BorderSide(color: colors.primary),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 手动缓存区域
                _SectionHeader(
                  title: '手动缓存',
                  titleColor: colors.warning,
                  icon: CacheIcons.cacheManual(size: 16, color: colors.warning),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatSize(_manualCacheSize),
                      style: TextStyle(color: colors.textSecondary, fontSize: 14),
                    ),
                    if (_manualCacheList.isNotEmpty)
                      TextButton(
                        onPressed: () => _showClearAllManualDialog(),
                        child: Text('清空全部', style: TextStyle(color: colors.error, fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_manualCacheList.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.elevated,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text('暂无手动缓存', style: TextStyle(color: colors.textMuted, fontSize: 14)),
                    ),
                  )
                else
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _manualCacheList.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final meta = _manualCacheList[index];
                        return _ManualCacheItem(
                          meta: meta,
                          colors: colors,
                          onDelete: () => _clearManualCache(meta.key),
                          formatSize: _formatSize,
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),

                // 流代理缓存区域
                _SectionHeader(
                  title: '流代理缓存',
                  titleColor: colors.success,
                  icon: CacheIcons.cacheStream(size: 16, color: colors.success),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_formatSize(_streamCacheSize)} / ${_streamCacheMaxMB >= 1024 ? '${(_streamCacheMaxMB / 1024).toStringAsFixed(1)} GB' : '$_streamCacheMaxMB MB'}',
                      style: TextStyle(color: colors.textSecondary, fontSize: 14),
                    ),
                    Text(
                      '${_streamCacheMaxMB > 0 ? ((_streamCacheSize / (_streamCacheMaxMB * 1024 * 1024)).clamp(0.0, 1.0) * 100).toStringAsFixed(1) : 0}%',
                      style: TextStyle(color: colors.success, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _streamCacheMaxMB > 0 ? (_streamCacheSize / (_streamCacheMaxMB * 1024 * 1024)).clamp(0.0, 1.0) : 0.0,
                    backgroundColor: colors.elevated,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.success),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                        label: const Text('清空流代理缓存'),
                        onPressed: _showClearStreamCacheDialog,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.success,
                          side: BorderSide(color: colors.success),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 流代理缓存容量上限设置
                _SectionHeader(title: '流代理缓存容量上限', titleColor: colors.textPrimary),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [512, 1024, 2048, 4096, 8192, 10240].map((mb) {
                    final isSelected = _streamCacheMaxMB == mb;
                    final label = mb >= 1024 ? '${(mb / 1024).toStringAsFixed(mb % 1024 == 0 ? 0 : 1)} GB' : '$mb MB';
                    return GestureDetector(
                      onTap: () async {
                        final config = StreamCacheConfig(maxCacheSizeMB: mb);
                        await config.saveMaxCacheSizeMB(mb);
                        setState(() {
                          _streamCacheMaxMB = mb;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? colors.success.withValues(alpha: 0.15) : colors.elevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? colors.success : colors.border,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: isSelected ? colors.success : colors.textSecondary,
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // 自动缓存大小限制设置
                _SectionHeader(title: '自动缓存大小限制', titleColor: colors.textPrimary),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AutoCacheSizeLimit.values.map((limit) {
                    final isSelected = bufferState.autoCacheSizeLimit == limit;
                    return GestureDetector(
                      onTap: () {
                        ref.read(bufferModeProvider.notifier).setAutoCacheSizeLimit(limit);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? colors.primary.withValues(alpha: 0.15) : colors.elevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? colors.primary : colors.border,
                          ),
                        ),
                        child: Text(
                          limit.label,
                          style: TextStyle(
                            color: isSelected ? colors.primary : colors.textSecondary,
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showClearAllManualDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有手动缓存吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearAllManualCache();
            },
            child: Text('清空', style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );
  }
}

/// 手动缓存项
class _ManualCacheItem extends StatelessWidget {
  final CacheMeta meta;
  final AppColors colors;
  final VoidCallback onDelete;
  final String Function(int) formatSize;

  const _ManualCacheItem({
    required this.meta,
    required this.colors,
    required this.onDelete,
    required this.formatSize,
  });

  @override
  Widget build(BuildContext context) {
    final fileSize = meta.totalBytes > 0 ? meta.totalBytes : meta.downloadedBytes;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.elevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            meta.isComplete ? Icons.check_circle : Icons.sync,
            size: 20,
            color: meta.isComplete ? colors.success : colors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta.resourceDomain,
                  style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '第${meta.epIndex + 1}集 · ${formatSize(fileSize)}',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: colors.error, size: 20),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// 区域标题
class _SectionHeader extends StatelessWidget {
  final String title;
  final Color titleColor;
  /// 可选的前导图标
  final Widget? icon;

  const _SectionHeader({required this.title, required this.titleColor, this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[icon!, const SizedBox(width: 6)],
        Text(
          title,
          style: TextStyle(
            color: titleColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
