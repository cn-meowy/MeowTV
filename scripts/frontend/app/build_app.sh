#!/bin/sh
#
# MeowTV Flutter App 打包脚本
# 用法:
#   ./build_app.sh                     # 构建 Android APK (按架构拆分) + iOS IPA
#   ./build_app.sh android             # 仅构建 Android APK (按 CPU 架构拆分, 默认)
#   ./build_app.sh android fat         # 构建 Android APK (fat, 包含所有架构)
#   ./build_app.sh android appbundle   # 构建 Android AAB (Google Play)
#   ./build_app.sh ios                 # 仅构建 iOS IPA
#
# Android CPU 架构说明:
#   split (默认) - 按 CPU 架构分别打包，每个 APK 体积小，需按设备分发对应版本
#                  生成: MeowTV-x.x.x-arm64-v8a.apk / armeabi-v7a.apk / x86_64.apk
#   fat          - 单个 APK 包含 arm64-v8a + armeabi-v7a + x86_64，体积大但兼容所有设备
#
# 环境要求:
#   - Flutter SDK >= 3.11.5
#   - Android SDK (NDK 29.0.14033849)
#   - Xcode (仅 macOS, iOS 构建)
#   - Ruby + cocoapods (仅 iOS 构建)
#

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
FLUTTER_APP_DIR="${PROJECT_ROOT}/frontend/app"
OUTPUT_DIR="${PROJECT_ROOT}/pkg"
VERSION=""
BUILD_NUMBER=""
FLUTTER_CMD="flutter"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { printf '%b\n' "${BLUE}[INFO]${NC} $*"; }
warn()  { printf '%b\n' "${YELLOW}[WARN]${NC} $*"; }
ok()    { printf '%b\n' "${GREEN}[OK]${NC} $*"; }
err()   { printf '%b\n' "${RED}[ERROR]${NC} $*" >&2; }

check_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "未找到命令: $1，请先安装后再运行"
        exit 1
    fi
}

usage() {
    echo "MeowTV Flutter App 打包脚本"
    echo ""
    echo "用法:"
    echo "  $0                     # 构建 Android APK (按架构拆分) + iOS IPA"
    echo "  $0 android             # 仅构建 Android APK (按 CPU 架构拆分, 默认)"
    echo "  $0 android fat         # 构建 Android APK (fat, 包含所有架构)"
    echo "  $0 android appbundle   # 构建 Android AAB (Google Play)"
    echo "  $0 ios                 # 仅构建 iOS IPA"
    echo ""
    echo "Android CPU 架构说明:"
    echo "  split (默认) - 按 CPU 架构分别打包，体积小，需按设备分发"
    echo "               生成: arm64-v8a / armeabi-v7a / x86_64 三个 APK"
    echo "  fat          - 单个 APK 包含所有架构，体积大但兼容所有设备"
}

preflight_check() {
    info "执行前置检查..."

    check_cmd "${FLUTTER_CMD}"
    local flutter_ver
    flutter_ver=$("${FLUTTER_CMD}" --version 2>/dev/null | head -1 || true)
    info "Flutter 版本: ${flutter_ver}"

    if [ ! -f "${FLUTTER_APP_DIR}/pubspec.yaml" ]; then
        err "未找到 Flutter 项目: ${FLUTTER_APP_DIR}/pubspec.yaml"
        exit 1
    fi

    local version_line
    version_line=$(grep '^version:' "${FLUTTER_APP_DIR}/pubspec.yaml" | sed 's/version: //')
    VERSION="${version_line%%+*}"
    BUILD_NUMBER="${version_line##*+}"
    info "应用版本: ${VERSION} (Build ${BUILD_NUMBER})"

    mkdir -p "${OUTPUT_DIR}"
    ok "前置检查通过"
}

build_android() {
    local build_type="${1:-split}"
    cd "${FLUTTER_APP_DIR}"

    info "开始构建 Android (${build_type})..."

    if [ -z "${ANDROID_HOME:-}" ] && [ -z "${ANDROID_SDK_ROOT:-}" ]; then
        warn "未设置 ANDROID_HOME 或 ANDROID_SDK_ROOT 环境变量"
        warn "如果构建失败，请确保 Android SDK 已正确安装"
    fi

    "${FLUTTER_CMD}" clean
    "${FLUTTER_CMD}" pub get

    local android_output_dir="${OUTPUT_DIR}/android"
    mkdir -p "${android_output_dir}"

    case "${build_type}" in
        appbundle)
            "${FLUTTER_CMD}" build appbundle --release \
                --build-name="${VERSION}" \
                --build-number="${BUILD_NUMBER}"

            local aab_file
            aab_file=$(find "${FLUTTER_APP_DIR}/build/app/outputs/bundle/release" -name "*.aab" 2>/dev/null | head -1)
            if [ -n "${aab_file}" ]; then
                cp "${aab_file}" "${android_output_dir}/MeowTV-${VERSION}.aab"
                ok "Android AAB 构建完成: ${android_output_dir}/MeowTV-${VERSION}.aab"
            else
                err "Android AAB 构建失败: 未找到 .aab 文件"
                exit 1
            fi
            ;;
        split|*)
            "${FLUTTER_CMD}" build apk --release --split-per-abi \
                --build-name="${VERSION}" \
                --build-number="${BUILD_NUMBER}"

            local found=0
            for apk in "${FLUTTER_APP_DIR}"/build/app/outputs/flutter-apk/app-*-release.apk; do
                if [ -f "$apk" ]; then
                    local abi_name
                    abi_name=$(basename "$apk" | sed 's/app-//' | sed 's/-release.apk//')
                    cp "$apk" "${android_output_dir}/MeowTV-${VERSION}-${abi_name}.apk"
                    ok "Android APK (${abi_name}) 构建完成: ${android_output_dir}/MeowTV-${VERSION}-${abi_name}.apk"
                    found=1
                fi
            done
            if [ "${found}" -eq 0 ]; then
                err "Android split APK 构建失败: 未找到分架构 .apk 文件"
                exit 1
            fi
            ;;
        fat)
            "${FLUTTER_CMD}" build apk --release \
                --build-name="${VERSION}" \
                --build-number="${BUILD_NUMBER}"

            local apk_file
            apk_file=$(find "${FLUTTER_APP_DIR}/build/app/outputs/flutter-apk" -maxdepth 1 -name "*.apk" 2>/dev/null | head -1)
            if [ -n "${apk_file}" ]; then
                cp "${apk_file}" "${android_output_dir}/MeowTV-${VERSION}.apk"
                ok "Android APK (fat) 构建完成: ${android_output_dir}/MeowTV-${VERSION}.apk"
            else
                err "Android APK 构建失败: 未找到 .apk 文件"
                exit 1
            fi
            ;;
    esac
}

build_ios() {
    cd "${FLUTTER_APP_DIR}"

    if [ "$(uname)" != "Darwin" ]; then
        err "iOS 构建只能在 macOS 上执行"
        exit 1
    fi

    check_cmd xcodebuild
    local xcode_ver
    xcode_ver=$(xcodebuild -version 2>/dev/null | head -1 || true)
    info "Xcode 版本: ${xcode_ver}"

    info "开始构建 iOS IPA..."

    "${FLUTTER_CMD}" clean
    "${FLUTTER_CMD}" pub get

    cd "${FLUTTER_APP_DIR}/ios"
    if [ -f Podfile ]; then
        if command -v pod >/dev/null 2>&1; then
            info "安装 CocoaPods 依赖..."
            pod install --repo-update
        else
            err "未找到 pod 命令，请先安装 CocoaPods: sudo gem install cocoapods"
            exit 1
        fi
    fi
    cd "${FLUTTER_APP_DIR}"

    "${FLUTTER_CMD}" build ipa --release \
        --build-name="${VERSION}" \
        --build-number="${BUILD_NUMBER}"

    local ipa_file
    ipa_file=$(find "${FLUTTER_APP_DIR}/build/ios/ipa" -name "*.ipa" 2>/dev/null | head -1)
    if [ -n "${ipa_file}" ]; then
        local ios_output_dir="${OUTPUT_DIR}/ios"
        mkdir -p "${ios_output_dir}"
        cp "${ipa_file}" "${ios_output_dir}/MeowTV-${VERSION}.ipa"
        ok "iOS IPA 构建完成: ${ios_output_dir}/MeowTV-${VERSION}.ipa"
    else
        local xcarchive_dir
        xcarchive_dir=$(find "${FLUTTER_APP_DIR}/build/ios/archive" -name "*.xcarchive" 2>/dev/null | head -1)
        if [ -n "${xcarchive_dir}" ]; then
            warn "未自动生成 IPA 文件，但找到了 xcarchive"
            warn "请使用 Xcode Organizer 或以下命令手动导出 IPA:"
            warn "  xcodebuild -exportArchive \\"
            warn "    -archive '${xcarchive_dir}' \\"
            warn "    -exportOptionsPlist ExportOptions.plist \\"
            warn "    -exportPath '${OUTPUT_DIR}/ios'"

            local ios_output_dir="${OUTPUT_DIR}/ios"
            mkdir -p "${ios_output_dir}"
            ok "iOS xcarchive 位置: ${xcarchive_dir}"
        else
            err "iOS 构建失败: 未找到 .ipa 或 .xcarchive 文件"
            exit 1
        fi
    fi
}

print_summary() {
    echo ""
    echo "============================================"
    printf '%b\n' "${GREEN}  MeowTV v${VERSION} 构建完成${NC}"
    echo "============================================"
    echo ""

    if [ -d "${OUTPUT_DIR}/android" ]; then
        echo "  Android:"
        for f in "${OUTPUT_DIR}/android"/*; do
            [ -f "$f" ] && echo "    $(basename "$f")  ($(du -h "$f" | cut -f1))"
        done
        echo ""
    fi

    if [ -d "${OUTPUT_DIR}/ios" ]; then
        echo "  iOS:"
        for f in "${OUTPUT_DIR}/ios"/*; do
            [ -f "$f" ] && echo "    $(basename "$f")  ($(du -h "$f" | cut -f1))"
        done
        echo ""
    fi

    echo "  输出目录: ${OUTPUT_DIR}"
    echo ""
}

# ============================================================
# 主流程
# ============================================================
main() {
    local platform="${1:-all}"
    local sub_type="${2:-}"

    case "${platform}" in
        -h|--help|help)
            usage
            exit 0
            ;;
        android)
            preflight_check
            build_android "${sub_type}"
            ;;
        ios)
            preflight_check
            build_ios
            ;;
        all|"")
            preflight_check
            build_android "${sub_type}"
            if [ "$(uname)" == "Darwin" ]; then
                build_ios
            else
                warn "当前系统非 macOS，跳过 iOS 构建"
            fi
            ;;
        *)
            err "未知平台: ${platform}"
            usage
            exit 1
            ;;
    esac

    print_summary
}

main "$@"
