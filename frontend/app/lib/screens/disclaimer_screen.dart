import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/storage/secure_storage.dart';
import '../features/auth/auth_provider.dart';

class DisclaimerScreen extends ConsumerWidget {
  const DisclaimerScreen({super.key});

  Future<void> _accept(WidgetRef ref) async {
    await SecureStorageService.instance.setHasSeenDisclaimer(true);
    // Updating auth state triggers GoRouter's refreshListenable,
    // which will automatically redirect to /login.
    ref.read(authProvider.notifier).setHasSeenDisclaimer();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(color: colors.background),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '免责声明',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Divider(color: colors.divider, height: 1),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _disclaimerText,
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textSecondary,
                      height: 1.8,
                    ),
                  ),
                ),
              ),
              // Bottom button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => _accept(ref),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                      ),
                    ),
                    child: Text(
                      '我已知晓并同意',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textInverse,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const String _disclaimerText = '''
一、服务说明

MeowTV 是一款影视聚合搜索平台，我们不存储、控制、管理或修改任何第三方资源站点的内容。所有影视资源均来自第三方公开网络，MeowTV 仅提供搜索和链接服务。

二、版权声明

1. MeowTV 尊重知识产权，所有影视作品的版权归各著作权人所有。
2. 用户使用 MeowTV 搜索并跳转至第三方站点观看影视内容时，应遵守各站点各自的服务条款。
3. MeowTV 明确禁止用户将本平台用于任何商业用途或非法目的。

三、免责声明

1. MeowTV 对因使用本平台而产生的任何直接或间接损失不承担责任，包括但不限于：
   - 因访问第三方站点而产生的设备损害或数据丢失
   - 因第三方站点内容而造成的精神损害
   - 因网络故障或技术问题而导致的服务中断
2. MeowTV 不对第三方站点的合法性、安全性、准确性负责。
3. 用户应自行承担使用本平台的风险。

四、用户行为

1. 用户应遵守当地法律法规，不得利用本平台从事违法活动。
2. 用户不得对本平台进行反编译、反汇编或其他逆向工程操作。
3. 用户不得利用技术手段恶意访问或攻击本平台服务器。

五、服务变更

1. MeowTV 保留随时修改或终止服务的权利。
2. 服务变更将不再另行通知。

六、其他

1. 本免责声明的解释权归 MeowTV 所有。
2. 如本声明的任何条款被认定为无效，不影响其他条款的效力。
3. 使用本应用即表示您已阅读并同意本免责声明。
''';
}
