#!/bin/sh
#
# MeowTV 前端 Web 多架构 Docker 镜像构建并推送脚本
#
# 用法:
#   ./build_push.sh                     # 默认 amd64+arm64，自动 tag（package.json version），打 latest，pull 回载
#   ./build_push.sh -p amd64            # 仅 amd64
#   ./build_push.sh -t v1.2.3           # 显式指定主 tag
#   ./build_push.sh --no-load           # 只推不回载
#   ./build_push.sh --no-latest         # 不打 latest tag
#   ./build_push.sh --help              # 显示帮助信息
#
# 环境要求:
#   - Docker >= 20.10
#   - docker buildx（多架构构建，需用户自行配置 builder 与 QEMU）
#   - 已 docker login 到目标仓库
#
# 注意事项:
#   - 构建上下文为项目根目录（使 scripts/ 与 frontend/ 同时可见），与 build_docker.sh 一致
#   - tag 默认取 frontend/web/package.json 的 version 字段（非 git tag）
#   - 推送后用 docker pull 回载本机架构镜像
#   - 职责与 build_docker.sh 分离：本脚本负责构建+推送+回载，不负责本地仅构建
#

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
FRONTEND_DIR="${PROJECT_ROOT}/frontend"

# 默认参数
IMAGE_NAME="xiaosheng078/meowtv-web"
PLATFORMS_INPUT="amd64,arm64"   # 原始输入，resolve_platforms 转为 linux/ 前缀
TAG_OVERRIDE=""                 # -t 显式指定
NO_LATEST=""                    # --no-latest 时设为 1
NO_LOAD=""                      # --no-load 时设为 1

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
MeowTV 前端 Web 多架构 Docker 镜像构建并推送脚本

用法:
    $0 [选项]

选项:
    -p, --platform <arch>  指定架构，逗号分隔或多次出现 (amd64 | arm64)，默认 amd64,arm64
    -t, --tag <tag>         显式指定主 tag，跳过 package.json version
    --no-latest            不打 latest tag
    --no-load              推送后不 pull 回载本机架构
    -h, --help             显示此帮助信息

tag 生成规则（未指定 -t 时）:
    使用 frontend/web/package.json 的 version 字段（如 0.0.1）。
    无论哪种，默认同时打 latest（除非 --no-latest）。

示例:
    $0                        # 默认 amd64+arm64，自动 tag，打 latest，pull 回载
    $0 -p amd64               # 仅 amd64
    $0 -t v1.2.3              # 指定主 tag v1.2.3
    $0 --no-load              # 只推不回载
    $0 -p arm64 --no-latest -t test-build

环境要求:
    - Docker >= 20.10
    - docker buildx（多架构构建，需自行配置 builder 与 QEMU）
    - 已 docker login 到 ${IMAGE_NAME} 所在仓库

与 build_docker.sh 的关系:
    本脚本只负责构建+推送+回载，不负责本地仅构建。
    仅本地构建（单架构、不推送）可用 build_docker.sh:
        ./build_docker.sh

EOF
}

# 解析命令行参数
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -p|--platform)
                if [ $# -lt 2 ]; then
                    err "-p/--platform 需要参数"
                    exit 1
                fi
                PLATFORMS_INPUT="$2"
                shift 2
                ;;
            -t|--tag)
                if [ $# -lt 2 ]; then
                    err "-t/--tag 需要参数"
                    exit 1
                fi
                TAG_OVERRIDE="$2"
                shift 2
                ;;
            --no-latest)
                NO_LATEST=1
                shift
                ;;
            --no-load)
                NO_LOAD=1
                shift
                ;;
            -h|--help)
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

# 检查环境依赖（最小化，不初始化 builder/QEMU）
# 当通过 -t 显式指定 tag 时，跳过 package.json 读取相关检查
check_env() {
    section "检查环境依赖"

    check_cmd docker

    # 检查 Docker daemon 是否运行
    _docker_info_ret=0
    docker info >/dev/null 2>&1 || _docker_info_ret=$?
    if [ $_docker_info_ret -ne 0 ]; then
        err "Docker daemon 未运行，请先启动 Docker"
        exit 1
    fi
    ok "Docker daemon 运行正常"

    # 检查 buildx（多架构必须）
    if ! docker buildx version >/dev/null 2>&1; then
        err "docker buildx 不可用，多架构构建需要 buildx，请先安装并配置 builder"
        err "提示: docker buildx create --use --name multiarch"
        exit 1
    fi
    ok "docker buildx 可用"

    # 登录态检查（仅警告，不退出）
    _login_ret=0
    docker info 2>/dev/null | grep -q "Username:" || _login_ret=$?
    if [ $_login_ret -ne 0 ]; then
        warn "未检测到 Docker Hub 登录态，推送可能失败"
        warn "提示: docker login"
    else
        ok "已检测到 Docker 仓库登录态"
    fi
}

# 探测本机架构 -> linux/amd64 | linux/arm64
detect_local_arch() {
    _arch="$(uname -m)"
    case "$_arch" in
        x86_64)
            printf '%s' "linux/amd64"
            ;;
        aarch64|arm64)
            printf '%s' "linux/arm64"
            ;;
        *)
            err "不支持的本机架构: $_arch"
            exit 1
            ;;
    esac
}

# 解析 --platform 输入 -> linux/ 前缀的 buildx platform 字符串
# 输入: PLATFORMS_INPUT (如 "amd64,arm64" 或 "amd64")
# 输出: 设置全局 PLATFORMS (如 "linux/amd64,linux/arm64")
resolve_platforms() {
    _result=""
    _seen=""

    # 把逗号分隔拆分循环（用 IFS 临时改为逗号）
    _oldifs="$IFS"
    IFS=','
    for _arch in ${PLATFORMS_INPUT}; do
        # 校验
        case "$_arch" in
            amd64|arm64) ;;
            *)
                err "不支持的架构: $_arch（仅支持 amd64/arm64）"
                exit 1
                ;;
        esac
        # 去重：检查 _seen 是否已包含 ",${_arch},"
        case "${_seen}" in
            *",${_arch},"*)
                continue
                ;;
        esac
        _seen="${_seen},${_arch},"
        if [ -z "$_result" ]; then
            _result="linux/${_arch}"
        else
            _result="${_result},linux/${_arch}"
        fi
    done
    IFS="$_oldifs"

    if [ -z "$_result" ]; then
        err "未指定任何架构"
        exit 1
    fi

    PLATFORMS="$_result"
}

# 从 package.json 读取版本信息
# 当 -t 显式指定 tag 时，跳过读取
get_version_info() {
    if [ -n "${TAG_OVERRIDE}" ]; then
        info "已指定显式 tag（${TAG_OVERRIDE}），跳过 package.json 读取"
        return
    fi

    if [ ! -f "${FRONTEND_DIR}/web/package.json" ]; then
        err "未找到 Web 项目: ${FRONTEND_DIR}/web/package.json"
        exit 1
    fi

    # 解析 version 字段（使用 grep + sed，不依赖 jq）
    VERSION=$(grep '"version"' "${FRONTEND_DIR}/web/package.json" | sed 's/.*"version": *"\([^"]*\)".*/\1/')

    if [ -z "${VERSION}" ]; then
        err "未能从 package.json 解析到 version 字段"
        exit 1
    fi

    info "应用版本: ${VERSION}"
}

# 生成主 tag
# 优先级: -t 显式 > package.json version
# 输出: 设置全局 TAG
resolve_tag() {
    # 1. 显式指定
    if [ -n "${TAG_OVERRIDE}" ]; then
        TAG="${TAG_OVERRIDE}"
        info "使用显式 tag: ${TAG}"
        return
    fi

    # 2. package.json version
    TAG="${VERSION}"
    info "使用 package.json version: ${TAG}"
}

# 构建多架构镜像并推送到远程仓库
build_and_push() {
    section "构建并推送多架构镜像"
    info "platform: ${PLATFORMS}"
    info "tag: ${TAG}"
    info "镜像: ${IMAGE_NAME}"

    # 拼接 -t 片段（POSIX sh，无数组，用变量累积空格分隔）
    TAG_ARGS="-t ${IMAGE_NAME}:${TAG}"
    if [ -z "${NO_LATEST}" ]; then
        TAG_ARGS="${TAG_ARGS} -t ${IMAGE_NAME}:latest"
    fi

    info "这可能需要几分钟时间，请耐心等待..."
    info "执行: docker buildx build --platform ${PLATFORMS} ${TAG_ARGS} --push"

    # ${TAG_ARGS} 不加引号：让 shell 按空格分词成多个 -t ...
    if DOCKER_BUILDKIT=1 docker buildx build \
        --network=host \
        --platform="${PLATFORMS}" \
        ${TAG_ARGS} \
        -f "${SCRIPT_DIR}/Dockerfile" \
        --push \
        --progress=plain \
        "${PROJECT_ROOT}"; then
        ok "多架构镜像构建并推送成功"
    else
        err "构建或推送失败"
        exit 1
    fi
}

# 回载本机架构镜像（方案 B：docker pull）
pull_local() {
    section "回载本机架构镜像"
    LOCAL_PLATFORM="$(detect_local_arch)"
    info "本机架构: ${LOCAL_PLATFORM}"

    info "docker pull ${IMAGE_NAME}:${TAG}"
    # docker pull 默认按本机架构选取多架构 manifest 条目，无需显式 --platform
    if docker pull "${IMAGE_NAME}:${TAG}"; then
        ok "本机架构镜像已回载: ${IMAGE_NAME}:${TAG}"
    else
        warn "回载 ${TAG} 失败，尝试回载 latest"
        if docker pull "${IMAGE_NAME}:latest"; then
            warn "已回载 latest（${TAG} 回载失败）"
        else
            err "镜像回载失败（${TAG} 与 latest 均失败）"
            exit 1
        fi
    fi

    # 同步本地 latest tag（避免本地 latest 与推送版本不一致）
    if [ -z "${NO_LATEST}" ]; then
        info "同步本地 latest tag"
        docker tag "${IMAGE_NAME}:${TAG}" "${IMAGE_NAME}:latest" 2>/dev/null || \
            warn "同步本地 latest 失败（${TAG} 镜像可能未回载成功）"
    fi
}

# 打印构建摘要与后续提示
print_summary() {
    section "完成"
    ok "多架构构建并推送完成！"
    printf '平台:    %s\n' "${PLATFORMS}"
    printf '镜像:    %s\n' "${IMAGE_NAME}"
    printf 'Tag:     %s\n' "${TAG}"
    if [ -z "${NO_LATEST}" ]; then
        printf 'Latest:  %s:latest\n' "${IMAGE_NAME}"
    fi
    printf '\n后续使用:\n'
    printf '  运行容器: docker run -p 3000:80 -e BACKEND_URL=http://meowtv:8088 %s:%s\n' "${IMAGE_NAME}" "${TAG}"
    printf '  远程拉取: docker pull %s:%s\n' "${IMAGE_NAME}" "${TAG}"
}

# 主函数
main() {
    parse_args "$@"
    check_env
    _local_arch="$(detect_local_arch)"
    ok "本机架构: ${_local_arch}"
    resolve_platforms
    get_version_info
    resolve_tag

    build_and_push

    if [ -z "${NO_LOAD}" ]; then
        pull_local
    else
        section "跳过本机回载（--no-load）"
    fi

    print_summary
}

main "$@"
