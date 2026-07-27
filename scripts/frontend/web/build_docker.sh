#!/bin/sh
#
# MeowTV Web Frontend Docker 打包脚本
#
# 用法:
#   ./build_docker.sh                     # 构建 Docker 镜像（默认）
#   ./build_docker.sh --help              # 显示帮助
#
# 环境要求:
#   - Docker >= 20.10
#   - docker buildx 支持（用于多架构构建）
#
# 注意事项:
#   - 构建上下文为项目根目录（使 scripts/ 与 frontend/ 同时可见）
#   - 构建产物为 Docker 镜像（无需提取文件）
#

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
FRONTEND_DIR="${PROJECT_ROOT}/frontend"
DOCKER_IMAGE="xiaosheng078/meowtv-web:latest"

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
MeowTV Web Frontend Docker 打包脚本

用法:
    $0 [选项]

选项:
    --help, -h  显示此帮助信息

示例:
    $0                      # 构建 Docker 镜像
    docker run -p 3000:80 \\
        -e BACKEND_URL=http://backend:8088 \\
        meowtv-web:latest   # 运行容器（指定后端地址）

环境变量:
    BACKEND_URL             后端 API 服务地址（默认: http://backend:8088）

构建命令（手动，从项目根目录执行）:
    单架构: docker build -f scripts/frontend/web/Dockerfile -t meowtv-web:latest .
    多架构: docker buildx build --platform linux/amd64,linux/arm64 \\
                -f scripts/frontend/web/Dockerfile -t meowtv-web:latest . --push

Docker 镜像: ${DOCKER_IMAGE}

EOF
}

# 从 package.json 读取版本信息
get_version_info() {
    if [ ! -f "${FRONTEND_DIR}/web/package.json" ]; then
        err "未找到 Web 项目: ${FRONTEND_DIR}/web/package.json"
        exit 1
    fi

    # 解析 version 字段（使用 grep + sed，不依赖 jq）
    VERSION=$(grep '"version"' "${FRONTEND_DIR}/web/package.json" | sed 's/.*"version": *"\([^"]*\)".*/\1/')

    info "应用版本: ${VERSION}"
}

# Docker 构建
docker_build() {
    section "构建 MeowTV Web Docker 镜像"
    info "Docker 镜像: ${DOCKER_IMAGE}"
    info "构建上下文: ${PROJECT_ROOT}"

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

    # 执行 Docker 构建
    # --load: 将镜像加载到本地 docker images（buildx build 默认不加载）
    info "开始构建 Docker 镜像..."
    if DOCKER_BUILDKIT=1 ${DOCKER_BUILD_CMD} \
        --network=host \
        --platform linux/amd64 \
        -f "${SCRIPT_DIR}/Dockerfile" \
        -t "${DOCKER_IMAGE}" \
        "${PROJECT_ROOT}"; then
        ok "Docker 镜像构建成功"
    else
        err "Docker 镜像构建失败"
        exit 1
    fi
}

# 打印构建摘要
print_summary() {
    section "构建摘要"

    info "应用版本: ${VERSION}"
    info "Docker 镜像: ${DOCKER_IMAGE}"
    echo ""
    info "运行容器示例:"
    echo "    docker run -p 3000:80 \\"
    echo "        -e BACKEND_URL=http://localhost:8088 \\"
    echo "        ${DOCKER_IMAGE}"
    echo ""
}

# 主流程
main() {
    case "${1:-}" in
        -h|--help|help)
            show_help
            exit 0
            ;;
        "")
            ;;
        *)
            err "未知参数: $1"
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
    docker_build

    # 打印摘要
    print_summary

    ok "构建完成！"
}

main "$@"
