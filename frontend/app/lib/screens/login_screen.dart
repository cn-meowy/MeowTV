import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/platform_util.dart';
import '../core/utils/url_utils.dart';
import '../features/auth/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  String _protocol = 'https://';
  bool _obscurePassword = true;
  bool _loading = false;
  bool _rememberMe = false;
  String? _error;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    _serverController.addListener(_onServerChanged);
    _loadRememberedCredentials();
  }

  void _onServerChanged() {
    if (_serverError != null) {
      setState(() => _serverError = null);
    }
  }

  Future<void> _loadRememberedCredentials() async {
    try {
      final creds = await ref.read(authProvider.notifier).getRememberedCredentials();
      if (creds != null && mounted) {
        setState(() {
          _usernameController.text = creds.username;
          _passwordController.text = creds.password;
          _serverController.text = creds.server;
          _protocol = creds.protocol;
          _rememberMe = true;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    // 服务器地址的 validator 返回 null 以避免内部 error 占位导致对齐问题，
    // 因此需要单独检查 _serverController 是否为空来防止空地址时仍调用登录接口
    if (_serverController.text.trim().isEmpty) {
      setState(() => _serverError = '请输入服务器地址');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final serverUrl = UrlUtils.normalize('$_protocol${_serverController.text.trim()}');
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    try {
      await ref.read(authProvider.notifier).login(
        serverUrl,
        username,
        password,
        rememberMe: _rememberMe,
        protocol: _protocol,
      );
      // GoRouter's refreshListenable will auto-redirect to /home after login
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(color: colors.background),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [colors.primary.withValues(alpha: 0.35), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const SizedBox(height: 60),
                      Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.card.withValues(alpha: 0.15),
                          border: Border.all(color: colors.primary.withValues(alpha: 0.25), width: 1.5),
                          boxShadow: [
                            BoxShadow(color: colors.primary.withValues(alpha: 0.2), blurRadius: 30),
                          ],
                        ),
                        child: ClipOval(
                          child: SvgPicture.asset(
                            'assets/images/logo.svg',
                            fit: BoxFit.cover,
                            width: 160,
                            height: 160,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '登录你的账户',
                        style: TextStyle(fontSize: 15, color: colors.textSecondary),
                      ),
                      const SizedBox(height: 36),
                      _buildServerField(colors),
                      const SizedBox(height: 16),
                      _buildTextField(
                        colors: colors,
                        controller: _usernameController,
                        hint: '用户名',
                        icon: Icons.person_outline,
                        validator: (v) => v == null || v.trim().isEmpty ? '请输入用户名' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        colors: colors,
                        controller: _passwordController,
                        hint: '密码',
                        icon: Icons.lock_outline,
                        obscure: _obscurePassword,
                        validator: (v) => v == null || v.length < 6 ? '密码至少6位' : null,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: colors.textMuted,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppTheme.radiusTag),
                            border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                          ),
                          child: Text(_error!, style: TextStyle(color: colors.error, fontSize: 13)),
                        ),
                      ],
                      // Remember me checkbox
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _rememberMe,
                                onChanged: (v) => setState(() => _rememberMe = v ?? false),
                                activeColor: colors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '记住用户',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                            ),
                          ),
                          child: _loading
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: colors.textInverse,
                                  ),
                                )
                              : Text(
                                  '登录',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 2,
                                    color: colors.textInverse,
                                  ),
                                ),
                        ),
                      ),
                      // Apple TV 扫码登录入口
                      if (PlatformUtil.isAppleTV) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: () => context.push('/qrcode-display'),
                            icon: Icon(Icons.qr_code, color: colors.primary),
                            label: Text(
                              '扫码登录',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: colors.primary,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: colors.primary, width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerField(AppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        IntrinsicHeight(
          child: Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(AppTheme.radiusInput),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                // 左侧协议下拉框 - 由 IntrinsicHeight 撑满高度
                Container(
                  decoration: BoxDecoration(
                    color: colors.elevated,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppTheme.radiusInput)),
                    border: Border(right: BorderSide(color: colors.border)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _protocol,
                      dropdownColor: colors.card,
                      style: TextStyle(color: colors.textSecondary, fontSize: 14),
                      icon: Icon(Icons.arrow_drop_down, color: colors.textMuted, size: 20),
                      padding: const EdgeInsets.only(left: 12),
                      items: const [
                        DropdownMenuItem(value: 'https://', child: Text('https://')),
                        DropdownMenuItem(value: 'http://', child: Text('http://')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _protocol = v);
                      },
                    ),
                  ),
                ),
                // 右侧服务器地址输入框 - 强制不显示内部 error 占位
                Expanded(
                  child: TextFormField(
                    controller: _serverController,
                    style: TextStyle(color: colors.textPrimary, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: '服务器地址',
                      hintStyle: TextStyle(color: colors.textMuted),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      prefixIcon: Icon(Icons.dns_outlined, color: colors.textMuted, size: 20),
                    ),
                    validator: (v) {
                      final error = v == null || v.trim().isEmpty ? '请输入服务器地址' : null;
                      // 同步设置 _serverError 以便 _login 中能及时检查
                      if (_serverError != error) {
                        _serverError = error;
                      }
                      return null; // 返回 null 避免 InputDecoration 显示内部 error 影响对齐
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        // 外部错误提示
        if (_serverError != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 6),
            child: Text(
              _serverError!,
              style: TextStyle(color: colors.error, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildTextField({
    required AppColors colors,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    String? Function(String?)? validator,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: colors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.textMuted),
        prefixIcon: Icon(icon, color: colors.textMuted, size: 20),
        suffixIcon: suffix,
      ),
      validator: validator,
    );
  }
}
