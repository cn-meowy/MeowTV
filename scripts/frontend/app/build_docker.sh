#!/bin/sh
#
# MeowTV Flutter Android Docker 打包脚本
#
# 用法:
#   ./build_docker.sh                     # 构建 Android APK (按架构拆分, 默认)
#   ./build_docker.sh split               # 构建 Android APK (按 CPU 架构拆分)
#   ./build_docker.sh fat                 # 构建 Android APK (fat, 包含所有架构)
#   ./build_docker.sh appbundle           # 构建 Android AAB (Google Play)
#   ./build_docker.sh --help              # 显示帮助
#
# 环境要求:
#   - Docker >= 20.10
#   - docker buildx 支持（用于多架构构建）
#
# 注意事项:
#   - 构建上下文为 frontend/ 目录
#   - iOS 构建不支持（需要 macOS + Xcode）
#   - 构建产物输出到 pkg/android/ 目录
#

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
FRONTEND_DIR="${PROJECT_ROOT}/frontend"
OUTPUT_DIR="${PROJECT_ROOT}/pkg/android"
DOCKER_IMAGE="meowtv-flutter:latest"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
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
MeowTV Flutter Android Docker 打包脚本

用法:
    $0 [选项]

选项:
    split       构建 Android APK (按 CPU 架构拆分, 默认)
    fat         构建 Android APK (fat, 包含所有架构)
    appbundle   构建 Android AAB (Google Play)
    --help, -h  显示此帮助信息

示例:
    $0                      # 构建按架构拆分的 APK
    $0 split                # 同上
    $0 fat                  # 构建包含所有架构的 APK
    $0 appbundle            # 构建 Google Play AAB

Android CPU 架构说明:
    split (默认) - 按 CPU 架构分别打包，体积小，需按设备分发
                 生成: arm64-v8a / armeabi-v7a / x86_64 三个 APK
    fat          - 单个 APK 包含所有架构，体积大但兼容所有设备

注意事项:
    - iOS 构建不支持（需要 macOS + Xcode）
    - 构建产物输出到: ${OUTPUT_DIR}
    - Docker 镜像: ${DOCKER_IMAGE}

EOF
}

# 从 pubspec.yaml 读取版本信息
get_version_info() {
    if [ ! -f "${FRONTEND_DIR}/app/pubspec.yaml" ]; then
        err "未找到 Flutter 项目: ${FRONTEND_DIR}/app/pubspec.yaml"
        exit 1
    fi

    # 解析 version: x.x.x+y 格式
    VERSION_LINE=$(grep '^version:' "${FRONTEND_DIR}/app/pubspec.yaml" | sed 's/version: //')
    VERSION=$(echo "${VERSION_LINE}" | cut -d'+' -f1)
    BUILD_NUMBER=$(echo "${VERSION_LINE}" | cut -d'+' -f2)

    info "应用版本: ${VERSION} (Build ${BUILD_NUMBER})"
}

# Docker 构建
docker_build() {
    local build_type="${1:-split}"

    section "构建 Flutter Android Docker 镜像"
    info "构建类型: ${build_type}"
    info "Docker 镜像: ${DOCKER_IMAGE}"
    info "构建上下文: ${FRONTEND_DIR}"

    # 检查 Docker
    check_cmd docker
    local docker_ver
    docker_ver=$(docker --version 2>/dev/null || true)
    info "Docker 版本: ${docker_ver}"

    # 检查 buildx
    if ! docker buildx version >/dev/null 2>&1; then
        warn "buildx 不可用，将使用单架构构建"
        DOCKER_BUILD_CMD="docker build"
    else
        info "使用 buildx 进行多架构构建支持"
        DOCKER_BUILD_CMD="docker buildx build"
    fi

    # 创建输出目录
    mkdir -p "${OUTPUT_DIR}"

    # 执行 Docker 构建
    # --load: 将镜像加载到本地 docker images（buildx build 默认不加载）
    info "开始构建 Docker 镜像..."
    if DOCKER_BUILDKIT=1 ${DOCKER_BUILD_CMD} \
        --network=host \
        --platform linux/amd64 \
        --build-arg BUILD_TYPE="${build_type}" \
        -f "${SCRIPT_DIR}/Dockerfile" \
        -t "${DOCKER_IMAGE}" \
        "${FRONTEND_DIR}"; then
        ok "Docker 镜像构建成功"
    else
        err "Docker 镜像构建失败"
        exit 1
    fi
}

# 从容器提取构建产物
extract_artifacts() {
    local build_type="${1:-split}"

    section "提取构建产物"

    # 创建临时容器（不运行，只为了提取文件）
    local container_id
    container_id=$(docker create "${DOCKER_IMAGE}" true 2>/dev/null || true)

    if [ -z "${container_id}" ]; then
        err "无法创建临时容器提取产物"
        exit 1
    fi

    info "从容器 ${container_id} 提取构建产物..."

    # 提取 APK 文件
    if [ -d "${OUTPUT_DIR}" ]; then
        rm -rf "${OUTPUT_DIR:?}"/*
    fi
    mkdir -p "${OUTPUT_DIR}"

    # 从容器的 /output 目录复制产物
    # 使用 docker cp 命令
    case "${build_type}" in
        appbundle)
            # AAB 文件
            docker cp "${container_id}:/output/bundle/release/" "${OUTPUT_DIR}/" 2>/dev/null || true
            # 移动到正确位置
            if [ -d "${OUTPUT_DIR}/release" ]; then
                find "${OUTPUT_DIR}/release" -name "*.aab" -exec mv {} "${OUTPUT_DIR}/MeowTV-${VERSION}.aab" \; 2>/dev/null || true
                rm -rf "${OUTPUT_DIR}/release"
            fi
            ;;
        fat|split|*)
            # APK 文件
            docker cp "${container_id}:/output/apk/" "${OUTPUT_DIR}/" 2>/dev/null || true
            ;;
    esac

    # 清理临时容器
    docker rm "${container_id}" >/dev/null 2>&1 || true

    ok "构建产物已提取到: ${OUTPUT_DIR}"
}

# 复制并重命名产物（适配 build_app.sh 的输出格式）
finalize_artifacts() {
    local build_type="${1:-split}"

    section "整理构建产物"

    case "${build_type}" in
        appbundle)
            # AAB 已经在 extract_artifacts 中重命名
            if [ -f "${OUTPUT_DIR}/MeowTV-${VERSION}.aab" ]; then
                ok "Android AAB 构建完成: ${OUTPUT_DIR}/MeowTV-${VERSION}.aab"
            else
                # 尝试查找原始 AAB
                local aab_file
                aab_file=$(find "${OUTPUT_DIR}" -name "*.aab" 2>/dev/null | head -1)
                if [ -n "${aab_file}" ]; then
                    mv "${aab_file}" "${OUTPUT_DIR}/MeowTV-${VERSION}.aab"
                    ok "Android AAB 构建完成: ${OUTPUT_DIR}/MeowTV-${VERSION}.aab"
                else
                    err "未找到 AAB 文件"
                    exit 1
                fi
            fi
            ;;
        split|*)
            # Split APK: app-arm64-v8a-release.apk, app-armeabi-v7a-release.apk, app-x86_64-release.apk
            # 重命名为 MeowTV-x.x.x-arm64-v8a.apk 格式
            for apk in "${OUTPUT_DIR}"/app-*-release.apk; do
                if [ -f "${apk}" ]; then
                    local abi_name
                    abi_name=$(basename "${apk}" | sed 's/app-//' | sed 's/-release.apk//')
                    mv "${apk}" "${OUTPUT_DIR}/MeowTV-${VERSION}-${abi_name}.apk"
                    ok "Android APK (${abi_name}) 构建完成: ${OUTPUT_DIR}/MeowTV-${VERSION}-${abi_name}.apk"
                fi
            done
            # 检查是否成功
            if [ ! -f "${OUTPUT_DIR}/MeowTV-${VERSION}-arm64-v8a.apk" ] && \
               [ ! -f "${OUTPUT_DIR}/MeowTV-${VERSION}-armeabi-v7a.apk" ] && \
               [ ! -f "${OUTPUT_DIR}/MeowTV-${VERSION}-x86_64.apk" ]; then
                err "Android split APK 构建失败: 未找到分架构 .apk 文件"
                exit 1
            fi
            ;;
        fat)
            # Fat APK: app-release.apk (包含所有架构)
            local apk_file
            apk_file=$(find "${OUTPUT_DIR}" -name "app-release.apk" 2>/dev/null | head -1)
            if [ -n "${apk_file}" ]; then
                mv "${apk_file}" "${OUTPUT_DIR}/MeowTV-${VERSION}.apk"
                ok "Android APK (fat) 构建完成: ${OUTPUT_DIR}/MeowTV-${VERSION}.apk"
            else
                err "Android APK 构建失败: 未找到 .apk 文件"
                exit 1
            fi
            ;;
    esac
}

# 打印构建摘要
print_summary() {
    section "构建摘要"

    info "应用版本: ${VERSION} (Build ${BUILD_NUMBER})"
    info "构建类型: ${build_type}"
    info "输出目录: ${OUTPUT_DIR}"
    echo ""
    info "构建产物:"
    for f in "${OUTPUT_DIR}"/*; do
        if [ -f "${f}" ]; then
            local size
            size=$(du -h "${f}" | cut -f1)
            printf '    %-40s %s\n' "$(basename "${f}")" "${size}"
        fi
    done
    echo ""
}

# 主流程
main() {
    local build_type="${1:-split}"

    # 解析参数
    case "${build_type}" in
        -h|--help|help)
            show_help
            exit 0
            ;;
        split|fat|appbundle)
            info "构建类型: ${build_type}"
            ;;
        *)
            err "未知构建类型: ${build_type}"
            echo ""
            show_help
            exit 1
            ;;
    esac

    # 前置检查
    section "前置检查"
    check_cmd docker
    get_version_info

    # Docker 构建
    docker_build "${build_type}"

    # 提取产物
    extract_artifacts "${build_type}"

    # 整理产物
    finalize_artifacts "${build_type}"

    # 打印摘要
    print_summary

    ok "构建完成！"
}

main "$@"
