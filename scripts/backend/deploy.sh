#!/bin/sh
#
# MeowTV 后端 Docker 部署脚本
#
# 用法:
#   sudo ./deploy.sh --uid $(id -u) --gid $(id -g)              # 构建 + 部署（默认）
#   sudo ./deploy.sh --build --uid $(id -u) --gid $(id -g)      # 仅构建镜像
#   sudo ./deploy.sh --deploy --uid $(id -u) --gid $(id -g)     # 仅部署（假设镜像已存在）
#   sudo ./deploy.sh --full --uid $(id -u) --gid $(id -g)       # 构建 + 部署
#   sudo ./deploy.sh -p amd64 --uid $(id -u) --gid $(id -g)     # 指定架构构建（amd64/arm64）
#   sudo ./deploy.sh -e prod --uid $(id -u) --gid $(id -g)      # 指定环境（dev/prod）
#   ./deploy.sh --help                                          # 显示帮助信息
#
#   ⚠️ --uid/--gid 必须显式传入，用于匹配宿主机 bind mount 目录属主。
#      $(id -u)/$(id -g) 由调用方 shell 在 sudo 提权前展开为字面量。
#      切勿写成 "sudo bash -c './deploy.sh --uid $(id -u) ...'"，
#      否则 $(id -u) 在 root shell 内展开为 0，容器将以 root 运行。
#
# 环境要求:
#   - Docker >= 20.10
#   - Docker Compose v2（或 docker-compose 插件）
#   - buildx 支持（用于多架构构建）
#
# 注意事项:
#   - 构建上下文为 backend/ 目录
#   - 架构默认为当前系统架构（amd64 或 arm64）
#   - 多架构构建示例: docker buildx build --platform linux/amd64,linux/arm64 ...
#

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"
BACKEND_DIR="${PROJECT_ROOT}/backend"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

# 默认参数
ACTION="full"              # full | build | deploy
PLATFORM=""                # amd64 | arm64 | 空（当前架构）
ENVIRONMENT="prod"         # dev | prod
IMAGE_NAME="xiaosheng078/meowtv:latest"
RUN_UID=""                 # 运行用户 UID（须与宿主机 bind mount 目录属主一致）
RUN_GID=""                 # 运行用户 GID（须与宿主机 bind mount 目录属主一致）

# 颜色定义（使用 \033 格式，由 printf %b 解释）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数（使用 printf %b 替代 echo -e）
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
MeowTV 后端 Docker 部署脚本

用法:
    $0 [选项]

选项:
    --build, -b       仅构建 Docker 镜像
    --deploy, -d      仅部署服务（需要镜像已存在）
    --full, -f        构建 + 部署（默认）
    --platform, -p    指定目标架构 (amd64 | arm64)，默认当前架构
    --env, -e         指定环境 (dev | prod)，默认 prod
    --uid U           运行用户 UID（必须配合 --gid，用于匹配宿主机目录属主）
    --gid G           运行用户 GID（必须配合 --uid）
    --help, -h        显示此帮助信息

示例:
    sudo $0 --uid \$(id -u) --gid \$(id -g)              # 构建 + 部署（当前架构）
    sudo $0 --build --uid \$(id -u) --gid \$(id -g)      # 仅构建
    sudo $0 -p arm64 -e prod --uid \$(id -u) --gid \$(id -g)
    sudo $0 --deploy --uid \$(id -u) --gid \$(id -g)     # 部署已有镜像

    ⚠️ 不要把 \$(id -u) 包进 "sudo bash -c '...'" 内：
    那样 \$(id -u) 会在 root shell 展开为 0，容器将以 root 运行。
    正确做法是在提权前由当前用户 shell 展开：sudo $0 --uid \$(id -u) --gid \$(id -g)

环境变量:
    MEOWTV_PORT        服务端口（默认 8080）
    MEOWTV_JWT_SECRET  JWT 密钥（生产环境必须修改）
    MEOWTV_ADMIN_PASSWORD  管理员密码

    运行用户必须通过 --uid/--gid 显式指定，须与宿主机 bind mount
    目录属主一致，否则容器内进程无法写入挂载目录。

EOF
}

# 解析命令行参数
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --build|-b)
                ACTION="build"
                shift
                ;;
            --deploy|-d)
                ACTION="deploy"
                shift
                ;;
            --full|-f)
                ACTION="full"
                shift
                ;;
            --platform|-p)
                PLATFORM="$2"
                shift 2
                ;;
            --env|-e)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --uid)
                RUN_UID="$2"
                shift 2
                ;;
            --gid)
                RUN_GID="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                err "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 检查环境依赖
check_env() {
    section "检查环境依赖"
    check_cmd docker
    check_cmd docker

    # 检查 Docker daemon 是否运行
    # 手动捕获管道错误（替代 pipefail）
    _docker_info_ret=0
    docker info >/dev/null 2>&1 || _docker_info_ret=$?
    if [ $_docker_info_ret -ne 0 ]; then
        err "Docker daemon 未运行，请先启动 Docker"
        exit 1
    fi
    ok "Docker daemon 运行正常"

    # 检查 docker compose 版本（兼容 v1 和 v2）
    _compose_v2_ret=0
    docker compose version >/dev/null 2>&1 || _compose_v2_ret=$?
    if [ $_compose_v2_ret -eq 0 ]; then
        ok "Docker Compose v2"
    else
        _compose_v1_ret=0
        docker-compose --version >/dev/null 2>&1 || _compose_v1_ret=$?
        if [ $_compose_v1_ret -eq 0 ]; then
            ok "Docker Compose v1"
        fi
    fi

    # 确定目标架构
    if [ -z "${PLATFORM}" ]; then
        _arch="$(uname -m)"
        case "$_arch" in
            x86_64)
                PLATFORM="linux/amd64"
                ;;
            aarch64|arm64)
                PLATFORM="linux/arm64"
                ;;
            *)
                err "不支持的架构: $_arch"
                exit 1
                ;;
        esac
    else
        # 转换为完整的 platform 格式
        PLATFORM="linux/${PLATFORM}"
    fi
    ok "目标架构: ${PLATFORM}"
    ok "部署环境: ${ENVIRONMENT}"
}

# 检查运行用户参数（uid/gid 必须显式指定，用于匹配宿主机 bind mount 目录属主）
check_run_user() {
    # uid/gid 均不能为空
    if [ -z "${RUN_UID}" ] || [ -z "${RUN_GID}" ]; then
        err "未指定运行用户。请用 sudo $0 --uid \$(id -u) --gid \$(id -g) 指定运行用户，以匹配宿主机 bind mount 目录属主"
        show_help
        exit 1
    fi

    # uid/gid 必须为非负整数
    if ! [ "${RUN_UID}" -ge 0 ] 2>/dev/null; then
        err "--uid 必须为非负整数，当前值: ${RUN_UID}"
        exit 1
    fi
    if ! [ "${RUN_GID}" -ge 0 ] 2>/dev/null; then
        err "--gid 必须为非负整数，当前值: ${RUN_GID}"
        exit 1
    fi

    # 警告 root 误用：若 uid 为 0，容器将以 root 运行，绕过非 root 安全性
    if [ "${RUN_UID}" -eq 0 ]; then
        warn "UID 为 0，容器将以 root 运行（通常因 sudo bash -c '... \$(id -u)' 误用导致），已绕过非 root 安全性"
    fi

    ok "运行用户: uid=${RUN_UID} gid=${RUN_GID}"
}

# 构建 Docker 镜像
build_image() {
    section "构建 Docker 镜像"

    info "构建命令: docker buildx build --network=host --platform=${PLATFORM} -f ${SCRIPT_DIR}/Dockerfile -t ${IMAGE_NAME} ${BACKEND_DIR}"
    info "这可能需要几分钟时间，请耐心等待..."

    # 直接内联参数（避免 Bash 数组）
    if DOCKER_BUILDKIT=1 docker buildx build \
        --network=host \
        --platform="${PLATFORM}" \
        -f "${SCRIPT_DIR}/Dockerfile" \
        -t "${IMAGE_NAME}" \
        "${BACKEND_DIR}" \
        --progress=plain; then
        ok "镜像构建成功: ${IMAGE_NAME}"
    else
        err "镜像构建失败"
        exit 1
    fi
}

# 部署服务
deploy_service() {
    section "部署服务"

    # 设置环境变量
    MEOWTV_ENV="${ENVIRONMENT}"
    MEOWTV_PORT="${MEOWTV_PORT:-8080}"
    export MEOWTV_ENV
    export MEOWTV_PORT

    # 运行用户（传给 compose 的 user: "${PUID}:${PGID}"，须与宿主机 bind mount 目录属主一致）
    PUID="${RUN_UID}"
    PGID="${RUN_GID}"
    export PUID
    export PGID

    # 检查 docker-compose.yml 是否存在
    if [ ! -f "${COMPOSE_FILE}" ]; then
        err "docker-compose.yml 不存在: ${COMPOSE_FILE}"
        exit 1
    fi

    # 检查 backend 目录是否存在
    if [ ! -d "${BACKEND_DIR}" ]; then
        err "backend 目录不存在: ${BACKEND_DIR}"
        exit 1
    fi

    info "使用 docker-compose 文件: ${COMPOSE_FILE}"
    info "端口映射: ${MEOWTV_PORT}:${MEOWTV_PORT}"

    # 拉取最新镜像（如有）
    info "尝试拉取最新基础镜像..."
    docker compose -f "${COMPOSE_FILE}" pull || true

    # 启动服务
    info "启动服务..."
    if docker compose -f "${COMPOSE_FILE}" up -d; then
        ok "服务启动成功"
    else
        err "服务启动失败"
        exit 1
    fi

    # 等待服务健康
    info "等待服务就绪..."
    sleep 3

    # 显示服务状态
    info "服务状态:"
    docker compose -f "${COMPOSE_FILE}" ps
}

# 停止服务
stop_service() {
    section "停止服务"
    if docker compose -f "${COMPOSE_FILE}" down; then
        ok "服务已停止"
    else
        warn "服务停止时出现一些问题"
    fi
}

# 主函数
main() {
    printf '%b\n' "${CYAN}"
    printf '%s\n' "  ____  _           _        ____ _             _    "
    printf '%s\n' " / ___|| |__   __ _| |_ ___ / ___| |_ __ _ _ __| | __"
    printf '%s\n' " \___ \| '_ \ / _\` | __/ _ \ |   | __/ _\` | '__| |/ /"
    printf '%s\n' "  ___) | | | | (_| | ||  __/ |___| || (_| | |  |   < "
    printf '%s\n' " |____/|_| |_|\__,_|\__\___|\____|_| \__,_|_|  |_|\_\\"
    printf '%b\n' "${NC}"
    printf '%s\n' "  MeowTV Backend Docker Deployment Script"
    printf '\n'

    parse_args "$@"
    check_env
    check_run_user

    case "${ACTION}" in
        build)
            build_image
            ;;
        deploy)
            deploy_service
            ;;
        full)
            build_image
            deploy_service
            ;;
    esac

    section "完成"
    ok "部署完成！"
    printf '\n'
    printf '%s\n' "后续操作:"
    printf '%s\n' "  查看日志: docker compose -f ${COMPOSE_FILE} logs -f"
    printf '%s\n' "  进入容器: docker compose -f ${COMPOSE_FILE} exec meowtv sh"
    printf '%s\n' "  停止服务: docker compose -f ${COMPOSE_FILE} down"
    printf '%s\n' "  重新部署: $0 --full"
}

main "$@"
