#!/bin/sh
#
# MeowTV Flutter App Windows 打包脚本
#
# 用法:
#   ./build_windows.sh                            # 构建 x64 Windows 应用 + ZIP 分发包
#   ./build_windows.sh --arch x64                 # 构建 x64 架构
#   ./build_windows.sh --arch arm64               # 构建 arm64 架构
#   ./build_windows.sh --arch all                 # 依次构建 x64 + arm64 两个架构
#   ./build_windows.sh --help                     # 显示帮助
#
# 环境要求:
#   - Flutter SDK >= 3.11.5
#   - Visual Studio Build Tools (包含 MSVC 工具链)
#     * 构建 x64: 安装 "MSVC v143 - VS 2022 C++ x64/x86 build tools"
#     * 构建 arm64: 额外安装 "MSVC v143 - VS 2022 C++ ARM64 build tools"
#   - Windows SDK (x64 / arm64)
#   - Git for Windows (提供 bash 环境)
#
# 架构说明:
#   - x64 (默认): 适用于绝大多数 Intel/AMD Windows 设备
#   - arm64: 适用于 Surface Pro X / Snapdragon X 等 ARM Windows 设备
#   - all: 依次构建两个架构，各自输出独立目录和分发包
#   - 注意: 在 x64 主机上交叉构建 arm64 需安装 ARM64 工具链组件
#           在 arm64 设备上原生构建 arm64 更为可靠
#
# 签名说明:
#   - 默认不签名 (适合内部测试)
#   - 如需正式签名，设置环境变量:
#       WINDOWS_CERT_PATH=path/to/certificate.pfx
#       WINDOWS_CERT_PASSWORD=your_password
#     或使用 Azure SignTool:
#       AZURE_SIGNING_ENDPOINT=https://xxx.codesigning.azure.net/
#       WINDOWS_CERT_NAME=certificate-name
#
# 产物输出 (每个架构独立命名):
#   - pkg/windows/MeowTV-{version}-{arch}/           (应用目录)
#   - pkg/windows/MeowTV-{version}-{arch}.zip        (ZIP 分发包)
#   - pkg/windows/MeowTV-{version}-{arch}-setup.exe  (NSIS 安装包，可选)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
FLUTTER_APP_DIR="${PROJECT_ROOT}/frontend/app"
OUTPUT_DIR="${PROJECT_ROOT}/pkg/windows"
VERSION=""
BUILD_NUMBER=""
FLUTTER_CMD="flutter"
ARCH="x64"          # 默认架构: x64 | arm64 | all
BUILT_ARCHS=""      # 记录成功构建的架构列表

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

# 将 ARCH 映射为 Flutter --target-platform 值
arch_to_target_platform() {
    case "$1" in
        x64)   echo "windows-x64" ;;
        arm64) echo "windows-arm64" ;;
        *)     return 1 ;;
    esac
}

# 显示帮助信息
show_help() {
    cat << EOF
MeowTV Flutter App Windows 打包脚本

用法:
    $0 [选项]

选项:
    --help, -h         显示此帮助信息
    --arch <架构>      指定目标 CPU 架构: x64 | arm64 | all (默认: x64)
    --no-zip           跳过 ZIP 创建
    --no-nsis          跳过 NSIS 安装包创建
    --sign             执行 Authenticode 签名 (需要证书配置)

架构说明:
    x64 (默认)        适用于 Intel/AMD Windows 设备
    arm64             适用于 Surface Pro X / Snapdragon X 等 ARM Windows 设备
    all               依次构建 x64 + arm64，各自输出独立产物
                      (单个架构失败不中断整体流程)

环境变量:
    WINDOWS_CERT_PATH      PFX 证书路径 (用于 signtool)
    WINDOWS_CERT_PASSWORD   证书密码
    AZURE_SIGNING_ENDPOINT Azure 代码签名终结点
    WINDOWS_CERT_NAME      Azure 证书名称
    FLUTTER_SKIP_SIGNING   设置为 1 则跳过签名 (默认)

签名说明:
    PFX 证书签名:
        export WINDOWS_CERT_PATH=/path/to/certificate.pfx
        export WINDOWS_CERT_PASSWORD=your_password
        $0 --sign

    Azure SignTool 签名:
        export AZURE_SIGNING_ENDPOINT=https://xxx.codesigning.azure.net/
        export WINDOWS_CERT_NAME=cert-name
        $0 --sign

产物位置: ${OUTPUT_DIR}
    每个架构独立命名: MeowTV-{version}-{arch}

EOF
}

# 前置检查
preflight_check() {
    info "执行前置检查..."
    info "运行目录: ${FLUTTER_APP_DIR}"
    info "目标架构: ${ARCH}"

    # 检查操作系统 (Git Bash / MSYS2 / WSL)
    local os_type
    case "$(uname -s)" in
        MINGW*|MSYS*) os_type="windows-git-bash" ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                os_type="wsl"
            else
                err "Windows 构建需要在 Windows、Git Bash、MSYS2 或 WSL 环境中执行"
                exit 1
            fi
            ;;
        *) err "Windows 构建需要在 Windows、Git Bash、MSYS2 或 WSL 环境中执行" && exit 1 ;;
    esac
    info "运行环境: ${os_type}"

    check_cmd "${FLUTTER_CMD}"
    local flutter_ver
    flutter_ver=$("${FLUTTER_CMD}" --version 2>/dev/null | head -1 || true)
    info "Flutter 版本: ${flutter_ver}"

    # 检查 Flutter doctor Windows 工具链
    info "检查 Windows 桌面支持..."
    if ! "${FLUTTER_CMD}" config --enable-windows-desktop 2>/dev/null; then
        warn "Flutter Windows 桌面支持可能未启用"
    fi

    if [ ! -f "${FLUTTER_APP_DIR}/pubspec.yaml" ]; then
        err "未找到 Flutter 项目: ${FLUTTER_APP_DIR}/pubspec.yaml"
        exit 1
    fi

    if [ ! -d "${FLUTTER_APP_DIR}/windows" ]; then
        err "未找到 Windows 平台支持，请确认 Flutter 项目已启用 Windows"
        exit 1
    fi

    # 解析版本号
    local version_line
    version_line=$(grep '^version:' "${FLUTTER_APP_DIR}/pubspec.yaml" | sed 's/version: //')
    VERSION="${version_line%%+*}"
    BUILD_NUMBER="${version_line##*+}"
    info "应用版本: ${VERSION} (Build ${BUILD_NUMBER})"

    # 确保输出目录存在
    mkdir -p "${OUTPUT_DIR}"

    ok "前置检查通过"
}

# 检查签名工具
check_signing_tools() {
    local skip_signing="${FLUTTER_SKIP_SIGNING:-1}"

    if [ "${skip_signing}" = "1" ]; then
        info "签名检查: 已跳过 (FLUTTER_SKIP_SIGNING=1)"
        return 0
    fi

    # 检查 PFX 证书方式
    if [ -n "${WINDOWS_CERT_PATH:-}" ] && [ -n "${WINDOWS_CERT_PASSWORD:-}" ]; then
        if command -v signtool >/dev/null 2>&1; then
            info "签名工具: signtool (PFX 证书)"
            return 0
        else
            warn "未找到 signtool，尝试使用 Azure SignTool"
        fi
    fi

    # 检查 Azure SignTool 方式
    if [ -n "${AZURE_SIGNING_ENDPOINT:-}" ] && [ -n "${WINDOWS_CERT_NAME:-}" ]; then
        if command -v azuresigntool >/dev/null 2>&1; then
            info "签名工具: AzureSignTool"
            return 0
        else
            warn "未找到 azuresigntool，将跳过签名"
            return 1
        fi
    fi

    warn "未配置有效的签名方式，将跳过签名"
    return 1
}

# 对 EXE 文件进行签名
sign_executables() {
    local app_dir="$1"

    if [ -z "${WINDOWS_CERT_PATH:-}" ] || [ -z "${WINDOWS_CERT_PASSWORD:-}" ]; then
        if [ -z "${AZURE_SIGNING_ENDPOINT:-}" ] || [ -z "${WINDOWS_CERT_NAME:-}" ]; then
            info "未配置签名，跳过签名"
            return 0
        fi
    fi

    info "开始签名 EXE 文件..."

    # 查找所有 EXE 文件
    local exe_files
    exe_files=$(find "${app_dir}" -name "*.exe" -type f 2>/dev/null)

    if [ -z "${exe_files}" ]; then
        warn "未找到 EXE 文件"
        return 0
    fi

    for exe in ${exe_files}; do
        info "签名: ${exe}"

        if [ -n "${WINDOWS_CERT_PATH:-}" ] && [ -n "${WINDOWS_CERT_PASSWORD:-}" ]; then
            # PFX 证书签名
            if command -v signtool >/dev/null 2>&1; then
                signtool sign //f "${WINDOWS_CERT_PATH}" //p "${WINDOWS_CERT_PASSWORD}" //fd SHA256 //tr http://timestamp.digicert.com //td SHA256 "${exe}" 2>/dev/null && {
                    ok "已签名: $(basename "${exe}")"
                } || warn "签名失败: $(basename "${exe}")"
            fi
        fi

        if [ -n "${AZURE_SIGNING_ENDPOINT:-}" ] && [ -n "${WINDOWS_CERT_NAME:-}" ]; then
            # Azure SignTool 签名
            if command -v azuresigntool >/dev/null 2>&1; then
                azuresigntool sign --azure-signing-endpoint "${AZURE_SIGNING_ENDPOINT}" --certificate-name "${WINDOWS_CERT_NAME}" --file-digest sha256 --timestamp-rfc3161 http://timestamp.digicert.com "${exe}" 2>/dev/null && {
                    ok "已签名: $(basename "${exe}")"
                } || warn "签名失败: $(basename "${exe}")"
            fi
        fi
    done
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

    # Windows CI: Flutter 生成的 .plugin_symlinks 是 symlink, CMake 的 libarchive
    # 拒绝穿越 symlink 解压 (ffmpegkit zip 报 "Cannot extract through symlink").
    # 改用 junction: Dart Link.existsSync() 对 junction 返回 true, Flutter build
    # 阶段 createPluginSymlinks 会跳过重建; junction 是目录链接, CMake 可正常解压.
    if [ -n "${MSYSTEM:-}" ]; then
        local symlinks_dir
        for symlinks_dir in \
            "windows/flutter/ephemeral/.plugin_symlinks" \
            "linux/flutter/ephemeral/.plugin_symlinks"; do
            [ -d "${symlinks_dir}" ] || continue
            local link
            for link in "${symlinks_dir}"/*; do
                [ -L "$link" ] || continue
                local target
                target=$(readlink -f "$link") || continue
                [ -n "$target" ] || continue
                # mklink /J 需要绝对路径
                local abs_target abs_link
                abs_target=$(cd "$target" && pwd -W 2>/dev/null || pwd)
                abs_link=$(cd "$(dirname "$link")" && pwd -W 2>/dev/null || pwd)/$(basename "$link")
                rm -f "$link"
                # 用 PowerShell 创建 junction (比 cmd mklink 更可靠)
                if powershell -NoProfile -Command \
                    "New-Item -ItemType Junction -Path '${abs_link}' -Target '${abs_target}'" \
                    >/dev/null 2>&1; then
                    info "junction: $(basename "$link") -> ${abs_target}"
                else
                    err "junction 创建失败: ${abs_link} -> ${abs_target}"
                    return 1
                fi
            done
        done
    fi
}

# 构建 Windows App (指定架构)
build_windows_app() {
    local arch="$1"
    local target_platform
    target_platform=$(arch_to_target_platform "${arch}") || {
        err "无效的架构: ${arch}"
        return 1
    }

    section "构建 Windows 应用 [${arch}]"
    info "开始构建 MeowTV Windows 应用 (${arch})..."

    cd "${FLUTTER_APP_DIR}"

    # 执行构建 (Flutter 3.29+ 移除了 --target-platform, 按 host 架构构建)
    # gal 插件用 experimental/coroutine, 新版 MSVC 报废弃错误, 通过 CL 环境变量注入抑制宏
    if [ -n "${MSYSTEM:-}" ]; then
        export CL="${CL:-} /D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS"
    fi
    if ! "${FLUTTER_CMD}" build windows --release \
        --build-name="${VERSION}" \
        --build-number="${BUILD_NUMBER}"; then
        err "Windows 应用构建失败 [${arch}]"
        if [ "${arch}" = "arm64" ]; then
            warn "arm64 构建失败，请确认已安装:"
            warn "  - Visual Studio: MSVC v143 - VS 2022 C++ ARM64 build tools"
            warn "  - Windows SDK for ARM64"
            warn "  或在 arm64 Windows 设备上原生构建"
        fi
        return 1
    fi

    # 查找构建产物目录
    # Flutter 新版输出到 build/windows/<arch>/runner/Release, 旧版 build/windows/runner/Release
    local release_dir=""
    for candidate in \
        "${FLUTTER_APP_DIR}/build/windows/${arch}/runner/Release" \
        "${FLUTTER_APP_DIR}/build/windows/x64/runner/Release" \
        "${FLUTTER_APP_DIR}/build/windows/arm64/runner/Release" \
        "${FLUTTER_APP_DIR}/build/windows/runner/Release"; do
        if [ -d "${candidate}" ]; then
            release_dir="${candidate}"
            break
        fi
    done

    if [ -z "${release_dir}" ]; then
        err "未找到构建产物目录 (build/windows/*/runner/Release)"
        return 1
    fi
    info "构建产物目录: ${release_dir}"

    # 复制到输出目录 (带架构后缀，避免被后续架构构建覆盖)
    local output_app_dir="${OUTPUT_DIR}/MeowTV-${VERSION}-${arch}"
    rm -rf "${output_app_dir}"
    mkdir -p "${output_app_dir}"

    # 复制所有构建产物
    cp -R "${release_dir}/." "${output_app_dir}/"

    # 验证主程序存在 (exe 名取自 pubspec, meowtv_mobile.exe 或 MeowTV.exe)
    local exe_file
    exe_file=$(find "${output_app_dir}" -maxdepth 1 -name "*.exe" -type f 2>/dev/null | head -1)
    if [ -z "${exe_file}" ]; then
        err "未找到主程序 *.exe [${arch}]"
        return 1
    fi

    ok "Windows 应用构建完成 [${arch}]: ${output_app_dir}"
    echo ""
    info "应用大小: $(du -sh "${output_app_dir}" | cut -f1)"
    return 0
}

# 编排多架构构建
build_all_arches() {
    local do_sign="$1"
    local skip_zip="$2"
    local skip_nsis="$3"
    local arch_list="x64 arm64"
    local arch

    info "多架构模式: 将依次构建 ${arch_list}"

    for arch in ${arch_list}; do
        info ""
        info "-------- 架构 ${arch} --------"

        if build_windows_app "${arch}"; then
            # 签名 (如启用)
            if [ "${do_sign}" = "1" ]; then
                sign_executables "${OUTPUT_DIR}/MeowTV-${VERSION}-${arch}"
            fi
            # 创建分发包
            if [ "${skip_zip}" -eq 0 ]; then
                create_zip "${arch}"
            fi
            if [ "${skip_nsis}" -eq 0 ]; then
                create_installer "${arch}"
            fi
            BUILT_ARCHS="${BUILT_ARCHS} ${arch}"
            ok "架构 ${arch} 全部完成"
        else
            warn "架构 ${arch} 构建失败，已跳过该架构的后续步骤"
        fi
    done

    if [ -z "${BUILT_ARCHS// /}" ]; then
        err "所有架构构建均失败"
        exit 1
    fi
    info "成功构建的架构:${BUILT_ARCHS}"
}

# 创建 ZIP 分发包 (指定架构)
create_zip() {
    local arch="$1"
    section "创建 ZIP 分发包 [${arch}]"

    local app_dir="${OUTPUT_DIR}/MeowTV-${VERSION}-${arch}"
    local zip_path="${OUTPUT_DIR}/MeowTV-${VERSION}-${arch}.zip"

    if [ ! -d "${app_dir}" ]; then
        warn "未找到应用目录 [${arch}]，跳过 ZIP 创建"
        return 0
    fi

    info "创建 ZIP 分发包 [${arch}]..."

    # 移除已有的 ZIP
    rm -f "${zip_path}"

    # 创建 ZIP
    cd "${OUTPUT_DIR}"
    if command -v zip >/dev/null 2>&1; then
        # 使用 InfoZIP zip
        zip -r -q "${zip_path}" "MeowTV-${VERSION}-${arch}"
    elif command -v 7z >/dev/null 2>&1; then
        # 备用: 7-Zip
        7z a -tzip "${zip_path}" "MeowTV-${VERSION}-${arch}" >/dev/null
    elif command -v powershell >/dev/null 2>&1; then
        # Windows 备用: PowerShell Compress-Archive
        powershell -Command "Compress-Archive -Path 'MeowTV-${VERSION}-${arch}' -DestinationPath '${zip_path}' -Force"
    else
        err "未找到 ZIP 工具 (zip, 7z, 或 powershell)"
        cd - >/dev/null
        return 1
    fi

    cd - >/dev/null

    if [ -f "${zip_path}" ]; then
        ok "ZIP 创建完成 [${arch}]: ${zip_path}"
        info "ZIP 大小: $(du -sh "${zip_path}" | cut -f1)"
    else
        err "ZIP 创建失败 [${arch}]"
        return 1
    fi
}

# 创建 NSIS 安装包 (指定架构)
create_installer() {
    local arch="$1"
    section "创建 NSIS 安装包 [${arch}]"

    local app_dir="${OUTPUT_DIR}/MeowTV-${VERSION}-${arch}"
    local installer_path="${OUTPUT_DIR}/MeowTV-${VERSION}-${arch}-setup.exe"

    if [ ! -d "${app_dir}" ]; then
        warn "未找到应用目录 [${arch}]，跳过安装包创建"
        return 0
    fi

    # 检查 NSIS 是否安装
    if ! command -v makensis >/dev/null 2>&1; then
        info "未找到 makensis，跳过 NSIS 安装包创建"
        info "如需创建安装包，请安装 NSIS: https://nsis.sourceforge.io/Download"
        return 0
    fi

    info "创建 NSIS 安装包 [${arch}]..."

    # 创建 NSIS 脚本 (使用占位符，后续 sed 替换)
    local nsis_script="${OUTPUT_DIR}/MeowTV-${VERSION}-${arch}-installer.nsi"
    cat > "${nsis_script}" << 'NSIS_EOF'
; MeowTV Windows Installer Script
; Auto-generated by build_windows.sh

!include "MUI2.nsh"

; General
Name "MeowTV"
OutFile "..\MeowTV-__VERSION__-__ARCH__-setup.exe"
InstallDir "$PROGRAMFILES64\MeowTV"
InstallDirRegKey HKLM "Software\MeowTV" "InstallDir"
RequestExecutionLevel admin

; Interface Settings
!define MUI_ABORTWARNING

; Pages
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "LICENSE"  ; 可选: 如有 LICENSE 文件
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; Languages
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

; Installer Section
Section "Install"
    SetOutPath "$INSTDIR"

    ; 复制所有文件
    File /r "MeowTV-__VERSION__-__ARCH__\*.*"

    ; 创建开始菜单快捷方式
    CreateDirectory "$SMPROGRAMS\MeowTV"
    CreateShortcut "$SMPROGRAMS\MeowTV\MeowTV.lnk" "$INSTDIR\MeowTV.exe"
    CreateShortcut "$SMPROGRAMS\MeowTV\卸载 MeowTV.lnk" "$INSTDIR\Uninstall.exe"
    CreateShortcut "$DESKTOP\MeowTV.lnk" "$INSTDIR\MeowTV.exe"

    ; 注册卸载信息
    WriteUninstaller "$INSTDIR\Uninstall.exe"
    WriteRegStr HKLM "Software\MeowTV" "InstallDir" "$INSTDIR"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MeowTV" "DisplayName" "MeowTV"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MeowTV" "UninstallString" "$INSTDIR\Uninstall.exe"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MeowTV" "DisplayVersion" "__VERSION__"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MeowTV" "Publisher" "MeowTV"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MeowTV" "InstallLocation" "$INSTDIR"
NSIS_EOF

    # 添加应用大小信息
    local app_size
    app_size=$(du -sb "${app_dir}" 2>/dev/null | cut -f1 || echo "10000000")
    sed -i "s/^Section \"Install\"$/Section \"Install\"\n    SetShellVarContext all\n    SpaceTexts $((${app_size} / 1024)) KB/" "${nsis_script}"

    # 在 NSIS 脚本末尾添加结束标记
    cat >> "${nsis_script}" << 'NSIS_EOF'

Section "Uninstall"
    ; 删除文件
    RMDir /r "$INSTDIR"

    ; 删除开始菜单快捷方式
    RMDir /r "$SMPROGRAMS\MeowTV"

    ; 删除桌面快捷方式
    Delete "$DESKTOP\MeowTV.lnk"

    ; 移除注册信息
    DeleteRegKey HKLM "Software\MeowTV"
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MeowTV"
SectionEnd
NSIS_EOF

    # 替换版本号和架构占位符 (使用 __ 前后缀避免与 NSIS 变量 ${} 冲突)
    sed -i "s/__VERSION__/${VERSION}/g; s/__ARCH__/${arch}/g" "${nsis_script}"

    # 创建 LICENSE 占位文件 (避免编译错误)
    if [ ! -f "${OUTPUT_DIR}/LICENSE" ]; then
        echo "MeowTV - Free and Open Source Software" > "${OUTPUT_DIR}/LICENSE"
    fi

    # 执行 NSIS 编译
    cd "${OUTPUT_DIR}"
    makensis "${nsis_script}" 2>/dev/null
    cd - >/dev/null

    # 清理临时文件
    rm -f "${nsis_script}"

    if [ -f "${installer_path}" ]; then
        ok "NSIS 安装包创建完成 [${arch}]: ${installer_path}"
        info "安装包大小: $(du -sh "${installer_path}" | cut -f1)"
    else
        warn "NSIS 安装包创建失败 [${arch}]，跳过"
    fi
}

# 打印构建摘要
print_summary() {
    section "构建摘要"

    info "应用版本: ${VERSION} (Build ${BUILD_NUMBER})"
    info "输出目录: ${OUTPUT_DIR}"
    echo ""

    # 确定要汇总的架构列表
    local arch_list
    if [ "${ARCH}" = "all" ]; then
        arch_list="${BUILT_ARCHS}"
    else
        arch_list=" ${ARCH}"
    fi

    for arch in ${arch_list}; do
        info "---- 架构 ${arch} ----"

        if [ -d "${OUTPUT_DIR}/MeowTV-${VERSION}-${arch}" ]; then
            info "应用目录:"
            echo "    MeowTV-${VERSION}-${arch}/  ($(du -sh "${OUTPUT_DIR}/MeowTV-${VERSION}-${arch}" | cut -f1))"
        fi

        if [ -f "${OUTPUT_DIR}/MeowTV-${VERSION}-${arch}.zip" ]; then
            info "ZIP 分发包:"
            echo "    MeowTV-${VERSION}-${arch}.zip  ($(du -sh "${OUTPUT_DIR}/MeowTV-${VERSION}-${arch}.zip" | cut -f1))"
        fi

        if [ -f "${OUTPUT_DIR}/MeowTV-${VERSION}-${arch}-setup.exe" ]; then
            info "NSIS 安装包:"
            echo "    MeowTV-${VERSION}-${arch}-setup.exe  ($(du -sh "${OUTPUT_DIR}/MeowTV-${VERSION}-${arch}-setup.exe" | cut -f1))"
        fi
        echo ""
    done

    info "安装说明:"
    echo "    ZIP: 解压后运行 MeowTV.exe"
    echo "    NSIS: 双击 setup.exe 运行安装向导"
    echo ""
    if [ -n "${WINDOWS_CERT_PATH:-}" ] || [ -n "${AZURE_SIGNING_ENDPOINT:-}" ]; then
        info "签名状态: 已签名 (可在属性中查看数字签名)"
    else
        info "签名状态: 未签名 (如需签名，使用 --sign 选项)"
    fi
}

# ============================================================
# 主流程
# ============================================================
main() {
    local skip_zip=0
    local skip_nsis=0
    local do_sign=0

    # 解析参数
    while [ $# -gt 0 ]; do
        case "${1}" in
            -h|--help|help)
                show_help
                exit 0
                ;;
            --arch)
                shift
                if [ $# -eq 0 ]; then
                    err "--arch 需要参数: x64 | arm64 | all"
                    exit 1
                fi
                ARCH="${1}"
                case "${ARCH}" in
                    x64|arm64|all) ;;
                    *) err "无效的架构: ${ARCH}，可选: x64, arm64, all" && exit 1 ;;
                esac
                shift
                ;;
            --no-zip)
                skip_zip=1
                shift
                ;;
            --no-nsis)
                skip_nsis=1
                shift
                ;;
            --sign)
                do_sign=1
                FLUTTER_SKIP_SIGNING=0
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

    # 检查签名工具
    if [ "${do_sign}" = "1" ]; then
        check_signing_tools || true
    else
        info "签名检查: 已跳过 (默认不签名，使用 --sign 启用)"
    fi

    # 清理和获取依赖
    clean_build
    get_dependencies

    # 构建
    if [ "${ARCH}" = "all" ]; then
        build_all_arches "${do_sign}" "${skip_zip}" "${skip_nsis}"
    else
        build_windows_app "${ARCH}" || { err "构建失败 [${ARCH}]"; exit 1; }
        # 签名 (如启用)
        if [ "${do_sign}" = "1" ]; then
            sign_executables "${OUTPUT_DIR}/MeowTV-${VERSION}-${ARCH}"
        fi
        # 创建分发包
        if [ "${skip_zip}" -eq 0 ]; then
            create_zip "${ARCH}"
        else
            info "已跳过 ZIP 创建 (--no-zip)"
        fi
        if [ "${skip_nsis}" -eq 0 ]; then
            create_installer "${ARCH}"
        else
            info "已跳过 NSIS 安装包创建 (--no-nsis)"
        fi
        BUILT_ARCHS=" ${ARCH}"
    fi

    # 打印摘要
    print_summary

    ok "构建完成！"
}

main "$@"
