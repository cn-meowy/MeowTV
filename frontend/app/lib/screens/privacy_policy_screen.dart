import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私政策'),
      ),
      body: Container(
        color: colors.background,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(
            _privacyPolicyText,
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
              height: 1.8,
            ),
          ),
        ),
      ),
    );
  }

  static const String _privacyPolicyText = '''
PurrTV（以下简称"我们"）非常重视用户隐私。本隐私政策说明我们在您使用 PurrTV 应用时收集、使用和保护个人信息的方式。请您在使用本应用前仔细阅读本隐私政策。

一、信息收集

在您使用 PurrTV 时，我们可能收集以下信息：

1. 设备 ID：用于识别您的设备，实现登录设备管理与安全校验。
2. 服务器地址：您手动配置的 PurrTV 后端服务器地址，用于与您的私有服务器通信。
3. 登录凭证（Token）：登录成功后由服务器下发，用于后续请求的身份验证。
4. 设备名称与类型：用于在"在线设备管理"中展示当前登录设备。
5. 播放与搜索历史：由您的 PurrTV 服务器存储，本应用仅在本地缓存以提升使用体验。

我们不会收集您的浏览记录、通讯录、地理位置或其他与本应用功能无关的个人信息。

二、信息使用

我们收集的信息仅用于以下目的：

1. 实现用户登录、身份验证与会话管理。
2. 与您配置的 PurrTV 服务器通信，提供影视搜索、播放、收藏等功能。
3. 在多设备登录场景下提供设备管理能力。
4. 优化应用性能与用户体验。

三、数据安全

1. 登录凭证（Token）使用系统安全存储（iOS Keychain / Android Keystore / macOS Keychain）保存，并在支持回退的平台上加密存储。
2. "记住我"功能保存的用户名与密码使用 AES-256-CBC 加密后存储，密钥与设备身份绑定。
3. 尽管我们采取了合理的安全措施，但任何通过互联网传输的数据都无法保证 100% 安全。请妥善保管您的账户信息。

四、儿童隐私

PurrTV 不面向 13 岁以下儿童。我们不会故意收集儿童的个人信息。如果您是儿童的监护人，发现您的孩子向我们提供了个人信息，请联系我们，我们将及时删除相关信息。

五、政策变更

1. 我们可能不时更新本隐私政策。更新后的政策将在应用内通过版本号变更提示您重新确认。
2. 隐私政策的变更自您同意新版本起生效。

六、联系我们

如果您对本隐私政策有任何疑问或建议，可通过 PurrTV 官方渠道与我们联系。

七、政策版本

1. 本隐私政策当前版本号为 1。
2. 当政策内容发生变更时，版本号将相应升高，届时您需要重新阅读并同意更新后的隐私政策方可继续使用本应用。
''';
}
