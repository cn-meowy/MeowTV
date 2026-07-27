#!/bin/sh
#
# MeowTV Flutter App macOS 打包脚本
#
# 用法:
#   ./build_macos.sh                     # 构建 macOS App (ad-hoc 签名)
#   ./build_macos.sh --help              # 显示帮助
#
# 环境要求:
#   - Flutter SDK >= 3.11.5
#   - Xcode >= 12.0
#   - macOS (仅在 macOS 上执行)
#
# 签名说明:
#   - 默认使用 ad-hoc 签名 (CODE_SIGN_IDENTITY = -)，无需开发者证书
#   - 如需正式签名，设置环境变量 DEVELOPMENT_TEAM=你的Team ID
#   - macOS entitlements 已配置 App Sandbox + 网络客户端权限
#
# 产物输出:
#   - pkg/macos/MeowTV-{version}.app          (应用包)
#   - pkg/macos/MeowTV-{version}.dmg          (DMG 安装包，可选)
#   - pkg/macos/MeowTV-{version}-unsigned.zip (无签名 ZIP，仅分发用)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
FLUTTER_APP_DIR="${PROJECT_ROOT}/frontend/app"
OUTPUT_DIR="${PROJECT_ROOT}/pkg/macos"
VERSION=""
BUILD_NUMBER=""
FLUTTER_CMD="flutter"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { printf '%b\n' "${BLUE}[INFO]${NC}    $*"; }
warn()    { printf '%b\n' "${YELLOW}[WARN]${NC}   $*"; }
ok()      { printf '%b\n' "${GREEN}[OK]${NC}     $*"; }
err()     { printf '%b\n' "${RED}[ERROR]${NC}  $*" >&2; }
section() { printf '\n%b\n' "${CYAN}==== $* ====${NC}"; }

# 检查命令是否存在
check_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "未找到命令: $1，请先安装后再运行"
        exit 1
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
MeowTV Flutter App macOS 打包脚本

用法:
    $0 [选项]

选项:
    --help, -h         显示此帮助信息
    --no-dmg           跳过 DMG 创建（仅生成 .app 和 .zip）
    --no-zip           跳过 ZIP 创建（仅生成 .app 和 .dmg）

环境变量:
    DEVELOPMENT_TEAM   Apple Developer Team ID（正式签名用，如留空则 ad-hoc）
                      示例: export DEVELOPMENT_TEAM=ABC123DEF4

签名说明:
    ad-hoc 签名 (默认):
        - 无需开发者证书
        - 应用可在任何 Mac 上运行（需在 系统偏好设置 > 安全性与隐私 中允许）
        - 适合内部测试、分发

    正式签名:
        export DEVELOPMENT_TEAM=你的TeamID
        $0
        - 需要 Apple Developer 账号和有效证书
        - 应用可使用 Gatekeeper 验证
        - 可提交到 Mac App Store 或公证

产物位置: ${OUTPUT_DIR}

EOF
}

# 前置检查
preflight_check() {
    info "执行前置检查..."
    info "运行目录: ${FLUTTER_APP_DIR}"
    # 检查操作系统
    if [ "$(uname)" != "Darwin" ]; then
        err "macOS 构建只能在 macOS 上执行，当前系统: $(uname)"
        exit 1
    fi

    check_cmd "${FLUTTER_CMD}"
    local flutter_ver
    flutter_ver=$("${FLUTTER_CMD}" --version 2>/dev/null | head -1 || true)
    info "Flutter 版本: ${flutter_ver}"

    check_cmd xcodebuild
    local xcode_ver
    xcode_ver=$(xcodebuild -version 2>/dev/null | head -1 || true)
    info "Xcode 版本: ${xcode_ver}"

    if [ ! -f "${FLUTTER_APP_DIR}/pubspec.yaml" ]; then
        err "未找到 Flutter 项目: ${FLUTTER_APP_DIR}/pubspec.yaml"
        exit 1
    fi

    if [ ! -d "${FLUTTER_APP_DIR}/macos" ]; then
        err "未找到 macOS 平台支持，请确认 Flutter 项目已启用 macOS"
        exit 1
    fi

    # 解析版本号 (与 build_app.sh 保持一致)
    local version_line
    version_line=$(grep '^version:' "${FLUTTER_APP_DIR}/pubspec.yaml" | sed 's/version: //')
    VERSION="${version_line%%+*}"
    BUILD_NUMBER="${version_line##*+}"
    info "应用版本: ${VERSION} (Build ${BUILD_NUMBER})"

    # 确保输出目录存在
    mkdir -p "${OUTPUT_DIR}"

    ok "前置检查通过"
}

# 配置签名 (可选)
configure_signing() {
    if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
        info "检测到 DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}，将使用正式签名"
        # 修改 DeveloperSigning.xcconfig 中的 DEVELOPMENT_TEAM
        local signing_config="${FLUTTER_APP_DIR}/macos/Runner/Configs/DeveloperSigning.xcconfig"
        if [ -f "${signing_config}" ]; then
            # 备份原配置
            cp "${signing_config}" "${signing_config}.bak"
            # 替换 DEVELOPMENT_TEAM 值
            sed -i '' "s/^DEVELOPMENT_TEAM =.*/DEVELOPMENT_TEAM = ${DEVELOPMENT_TEAM}/" "${signing_config}"
            # 使用 Developer 签名而非 ad-hoc
            sed -i '' 's/^CODE_SIGN_IDENTITY = -/CODE_SIGN_IDENTITY = "Developer ID Application"/' "${signing_config}"
            info "已更新签名配置: ${signing_config}"
        fi
    else
        info "使用 ad-hoc 签名 (无需开发者证书)"
        # ad-hoc 模式: 禁用 build 阶段签名, 规避未签名 framework (ffmpegkit 预编译二进制)
        # 导致的 CodeSign 失败; build 后由 sign_app_bundle 统一 ad-hoc 签名
        local signing_config="${FLUTTER_APP_DIR}/macos/Runner/Configs/DeveloperSigning.xcconfig"
        if [ -f "${signing_config}" ] && [ ! -f "${signing_config}.bak" ]; then
            cp "${signing_config}" "${signing_config}.bak"
        fi
        if [ -f "${signing_config}" ]; then
            # 追加禁用签名的设置 (若已存在不重复)
            grep -q '^CODE_SIGNING_ALLOWED' "${signing_config}" 2>/dev/null || \
                printf '\n// CI ad-hoc: 禁用 build 阶段签名\nCODE_SIGNING_ALLOWED = NO\nCODE_SIGNING_REQUIRED = NO\n' >> "${signing_config}"
            info "已禁用 build 阶段签名 (CODE_SIGNING_ALLOWED=NO)"
        fi
    fi
}

# 恢复签名配置
restore_signing() {
    local signing_config="${FLUTTER_APP_DIR}/macos/Runner/Configs/DeveloperSigning.xcconfig"
    if [ -f "${signing_config}.bak" ]; then
        mv "${signing_config}.bak" "${signing_config}"
        info "已恢复签名配置"
    fi
}

# 清理构建
clean_build() {
    info "清理构建目录..."
    cd "${FLUTTER_APP_DIR}"
    "${FLUTTER_CMD}" clean
    ok "清理完成"
}

# 获取依赖
get_dependencies() {
    info "获取 Flutter 依赖..."
    cd "${FLUTTER_APP_DIR}"
    "${FLUTTER_CMD}" pub get
    ok "依赖获取完成"
}

# 安装 CocoaPods 依赖
install_pods() {
    info "安装 CocoaPods 依赖..."
    local podfile="${FLUTTER_APP_DIR}/macos/Podfile"
    if [ -f "${podfile}" ]; then
        if command -v pod >/dev/null 2>&1; then
            cd "${FLUTTER_APP_DIR}/macos"
            pod install --repo-update
            cd "${FLUTTER_APP_DIR}"
            ok "CocoaPods 安装完成"
        else
            warn "未找到 pod 命令，跳过 CocoaPods 安装"
        fi
    else
        info "无 Podfile，跳过 CocoaPods 安装"
    fi
}

# ad-hoc 签名 app bundle (含内部所有 framework)
# ffmpeg_kit_flutter_new 的预编译 ffmpeg framework (libavfilter 等) 未签名,
# Xcode 构建阶段 CodeSign 会失败. 改为 build 时跳过签名, build 后统一签名.
sign_app_bundle() {
    if ! command -v codesign >/dev/null 2>&1; then
        warn "未找到 codesign 命令，跳过签名"
        return 0
    fi
    local app_path="$1"
    info "ad-hoc 签名 app bundle: ${app_path}"
    # 先签所有 framework/dylib (深优先), 最后签主 app
    find "${app_path}" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 2>/dev/null | \
        while IFS= read -r -d '' lib; do
            codesign --force --sign - --timestamp=none "$lib" >/dev/null 2>&1 || true
        done
    find "${app_path}" -type d -name "*.framework" -print0 2>/dev/null | \
        while IFS= read -r -d '' fw; do
            codesign --force --sign - --timestamp=none "$fw" >/dev/null 2>&1 || true
        done
    # 主 app 最后签名 (会校验内部组件)
    codesign --force --sign - --timestamp=none --deep "${app_path}" >/dev/null 2>&1 || \
        warn "主 app 签名失败 (可能内部仍有未签组件, 不影响产物)"
    ok "app bundle 签名完成"
}

# 构建 macOS App
build_macos_app() {
    section "构建 macOS App"
    info "开始构建 MeowTV macOS 应用..."

    cd "${FLUTTER_APP_DIR}"

    # 执行构建 (跳过 Xcode 签名, build 后统一 ad-hoc 签名, 规避未签名 framework 报错)
    # 正式签名时仍走 Xcode 签名
    local build_env=""
    if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
        build_env="CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO"
        info "ad-hoc 模式: 跳过 build 阶段签名, build 后统一签名"
    fi

    if ! env ${build_env} "${FLUTTER_CMD}" build macos --release \
        --build-name="${VERSION}" \
        --build-number="${BUILD_NUMBER}"; then
        err "macOS App 构建失败"
        exit 1
    fi

    # 查找构建产物
    local app_path
    app_path=$(find "${FLUTTER_APP_DIR}/build/macos/Build/Products/Release" -maxdepth 2 -name "*.app" -type d 2>/dev/null | head -1)

    if [ -z "${app_path}" ] || [ ! -d "${app_path}" ]; then
        err "未找到构建产物 .app，请检查构建日志"
        exit 1
    fi

    # ad-hoc 模式: build 后对 app bundle 统一签名
    if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
        sign_app_bundle "${app_path}"
    fi

    # 复制到输出目录
    local output_app="${OUTPUT_DIR}/MeowTV-${VERSION}.app"
    rm -rf "${output_app}"
    cp -R "${app_path}" "${output_app}"

    ok "macOS App 构建完成: ${output_app}"
    echo ""
    info "应用大小: $(du -sh "${output_app}" | cut -f1)"
}

# 创建 DMG 安装包
create_dmg() {
    section "创建 DMG 安装包"

    local app_path="${OUTPUT_DIR}/MeowTV-${VERSION}.app"
    local dmg_path="${OUTPUT_DIR}/MeowTV-${VERSION}.dmg"

    if [ ! -d "${app_path}" ]; then
        warn "未找到 .app，跳过 DMG 创建"
        return 0
    fi

    if ! command -v hdiutil >/dev/null 2>&1; then
        warn "未找到 hdiutil，跳过 DMG 创建"
        return 0
    fi

    info "创建 DMG 安装包..."

    # 创建临时目录用于 DMG 内容
    local dmg_temp_dir
    dmg_temp_dir=$(mktemp -d)
    cp -R "${app_path}" "${dmg_temp_dir}/"

    # 使用 appdmg 或 hdiutil 创建 DMG
    if command -v appdmg >/dev/null 2>&1; then
        # 如果有 appdmg，使用它（更美观）
        local spec_file
        spec_file=$(mktemp)
        cat > "${spec_file}" << SPEC_EOF
{
  "title": "MeowTV",
  "icon": "${app_path}/Contents/Resources/AppIcon.icns",
  "contents": [
    { "x": 130, "y": 220, "type": "file", "path": "${app_path}" },
    { "x": 410, "y": 220, "type": "link", "path": "/Applications" }
  ]
}
SPEC_EOF
        appdmg "${spec_file}" "${dmg_path}"
        rm -f "${spec_file}"
    else
        # 使用 hdiutil 创建标准 DMG
        hdiutil create -volname "MeowTV-${VERSION}" \
            -srcfolder "${dmg_temp_dir}" \
            -ov -format UDZO \
            "${dmg_path}"
    fi

    rm -rf "${dmg_temp_dir}"

    if [ -f "${dmg_path}" ]; then
        ok "DMG 创建完成: ${dmg_path}"
        info "DMG 大小: $(du -sh "${dmg_path}" | cut -f1)"
    else
        warn "DMG 创建失败，跳过"
    fi
}

# 创建 ZIP 分发包
create_zip() {
    section "创建 ZIP 分发包"

    local app_path="${OUTPUT_DIR}/MeowTV-${VERSION}.app"
    local zip_path="${OUTPUT_DIR}/MeowTV-${VERSION}-unsigned.zip"

    if [ ! -d "${app_path}" ]; then
        warn "未找到 .app，跳过 ZIP 创建"
        return 0
    fi

    info "创建 ZIP 分发包..."

    # 移除已有的 ZIP
    rm -f "${zip_path}"

    # 创建 ZIP (使用 -y 保留符号链接)
    if command -v zip >/dev/null 2>&1; then
        cd "${OUTPUT_DIR}"
        zip -r -y "${zip_path}" "MeowTV-${VERSION}.app"
        cd - >/dev/null
    else
        # 备用方案: 使用 ditto
        ditto -c -k --sequesterRsrc "${app_path}" "${zip_path}"
    fi

    if [ -f "${zip_path}" ]; then
        ok "ZIP 创建完成: ${zip_path}"
        info "ZIP 大小: $(du -sh "${zip_path}" | cut -f1)"
    else
        warn "ZIP 创建失败，跳过"
    fi
}

# 打印构建摘要
print_summary() {
    section "构建摘要"

    info "应用版本: ${VERSION} (Build ${BUILD_NUMBER})"
    info "输出目录: ${OUTPUT_DIR}"
    echo ""

    if [ -d "${OUTPUT_DIR}/MeowTV-${VERSION}.app" ]; then
        info "应用包:"
        echo "    MeowTV-${VERSION}.app  ($(du -sh "${OUTPUT_DIR}/MeowTV-${VERSION}.app" | cut -f1))"
    fi

    if [ -f "${OUTPUT_DIR}/MeowTV-${VERSION}.dmg" ]; then
        info "DMG 安装包:"
        echo "    MeowTV-${VERSION}.dmg  ($(du -sh "${OUTPUT_DIR}/MeowTV-${VERSION}.dmg" | cut -f1))"
    fi

    if [ -f "${OUTPUT_DIR}/MeowTV-${VERSION}-unsigned.zip" ]; then
        info "ZIP 分发包:"
        echo "    MeowTV-${VERSION}-unsigned.zip  ($(du -sh "${OUTPUT_DIR}/MeowTV-${VERSION}-unsigned.zip" | cut -f1))"
    fi

    echo ""
    info "安装说明:"
    if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
        echo "    正式签名版本，可直接双击安装"
    else
        echo "    ad-hoc 签名版本，首次运行需在 系统偏好设置 > 安全性与隐私 > 通用"
        echo "    中允许来自以下来源的应用: '仍要打开'"
    fi
}

# ============================================================
# 主流程
# ============================================================
main() {
    local skip_dmg=0
    local skip_zip=0

    # 解析参数
    while [ $# -gt 0 ]; do
        case "${1}" in
            -h|--help|help)
                show_help
                exit 0
                ;;
            --no-dmg)
                skip_dmg=1
                shift
                ;;
            --no-zip)
                skip_zip=1
                shift
                ;;
            *)
                err "未知参数: ${1}"
                show_help
                exit 1
                ;;
        esac
    done

    # 前置检查
    section "前置检查"
    preflight_check

    # 配置签名
    configure_signing

    # 清理和获取依赖
    clean_build
    get_dependencies
    install_pods

    # 构建 (ad-hoc 模式下 build 后统一签名, 见 build_macos_app)
    build_macos_app

    # 创建分发包
    if [ "${skip_dmg}" -eq 0 ]; then
        create_dmg
    else
        info "已跳过 DMG 创建 (--no-dmg)"
    fi

    if [ "${skip_zip}" -eq 0 ]; then
        create_zip
    else
        info "已跳过 ZIP 创建 (--no-zip)"
    fi

    # 恢复签名配置
    restore_signing

    # 打印摘要
    print_summary

    ok "构建完成！"
}

main "$@"
