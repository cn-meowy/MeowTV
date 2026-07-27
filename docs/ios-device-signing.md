# iOS 真机调试签名配置

本文档说明如何在 iOS 真机上运行 MeowTV（Flutter App）。
面向使用**免费个人 Apple ID** + **Xcode 自动签名**的开发者。

## 背景

Flutter 真机部署会报：

```
No valid code signing certificates were found
No development certificates available to code sign app for device deployment
```

根因：iOS 工程未配置开发团队（DEVELOPMENT_TEAM）。本仓库采用
**本地覆盖** 方式注入 Team ID，避免团队成员的 Team ID 冲突。

## 配置步骤

### 1. 复制本地覆盖文件

```bash
cp frontend/app/ios/Flutter/LocalOverrides.example.xcconfig \
   frontend/app/ios/Flutter/LocalOverrides.xcconfig
```

`LocalOverrides.xcconfig` 已被 `ios/.gitignore` 忽略，不会提交。

### 2. 填入你的 Team ID

打开 `frontend/app/ios/Flutter/LocalOverrides.xcconfig`，把
`DEVELOPMENT_TEAM` 的值改成你的 10 位 Team ID。

获取 Team ID：

- 方式一：Xcode → Settings（Preferences）→ Accounts → 选中 Apple ID
  → 右侧 "Team" 列下方的 10 位字母数字串。
- 方式二：登录 https://developer.apple.com/account → Membership Details。

### 3. 在 Xcode 登录 Apple ID

```bash
open frontend/app/ios/Runner.xcworkspace
```

- Xcode → Settings → Accounts → 点 "+" → 用 Apple ID 登录。
- 登录后会出现 "Personal Team"（个人团队）。

### 4. 选择 Signing Team

- 左侧导航选中 `Runner` 工程 → 选 `Runner` target
- 切到 "Signing & Capabilities"
- "Team" 下拉选你的 Personal Team（自动勾选 Automatically manage signing）

> 如果下拉里没看到你的 Team，确认第 2 步的 `DEVELOPMENT_TEAM`
> 与登录的 Apple ID 一致。

### 5. 连接真机并运行

```bash
cd frontend/app
flutter clean
flutter run --release   # 或不指定默认 debug
```

或在 Xcode 选设备后点 ▶ Run。

### 6. 首次安装需在设备上信任证书

首次把签名包安装到 iPhone 后，App 图标会显示"不受信任的开发者"。
在 iPhone 上：

> 设置 → 通用 → VPN与设备管理 → 选你的开发者证书 → 信任

之后即可正常启动。

## 免费个人 Apple ID 的限制

- 真机签名包**有效期 7 天**，到期后再次 `flutter run` 会自动重新签发。
- 同一个 Bundle ID（`cn.meowy.meowtv`）每周只能签一次；
  若提示 `An App ID with Identifier ... is not available`，
  等待 7 天后再试，或临时改 `PRODUCT_BUNDLE_IDENTIFIER` 后缀。
- 每个免费 Apple ID 最多同时签 3 个 App。
- 无法使用推送、iCloud 等 Capabilities（需要付费开发者账号）。

## 仓库配置说明（给维护者）

| 文件 | 是否入库 | 作用 |
|---|---|---|
| `ios/Flutter/Debug.xcconfig` | 是 | 末尾 `#include? "LocalOverrides.xcconfig"` |
| `ios/Flutter/Release.xcconfig` | 是 | 同上 |
| `ios/Flutter/LocalOverrides.example.xcconfig` | 是 | 模板，供复制 |
| `ios/Flutter/LocalOverrides.xcconfig` | 否（gitignore） | 本地实际生效，含 Team ID |
| `ios/Runner.xcodeproj/project.pbxproj` | 是 | Runner target 三个配置声明 `CODE_SIGN_STYLE = Automatic`，**不写 DEVELOPMENT_TEAM** |

xcconfig 的 `#include?`（带问号）表示文件不存在也不报错，
团队成员即使没有 `LocalOverrides.xcconfig` 也能正常构建（仅无法真机签名）。
