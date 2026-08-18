# ============================================================
# MeowTV 后端 Docker 镜像
#
# 架构: 支持 amd64 / arm64
# CGO: 启用（依赖 mattn/go-sqlite3）
#
# 构建命令（从项目根目录）:
#   单架构: docker build -f scripts/backend/Dockerfile -t meowtv:latest backend/
#   多架构: docker buildx build --platform linux/amd64,linux/arm64 -f scripts/backend/Dockerfile -t meowtv:latest backend/ --push
#
# 运行命令（docker run，无需 --user，由 entrypoint 内 gosu 降权）:
#   docker run -d -p 8088:8088 \
#     -e PUID=$(id -u) -e PGID=$(id -g) \
#     -v $(pwd)/data:/app/data \
#     -v $(pwd)/logs:/app/logs \
#     meowtv:latest
#
# 注意: build context 为 backend/ 目录
# ============================================================

# ----------------------------------------
# 阶段 1: builder - 编译 Go 二进制
# ----------------------------------------
# 注意: 不使用 --platform=$BUILDPLATFORM，让 builder 阶段按目标架构(TARGETPLATFORM)运行，
# 这样 CGO 编译时的 gcc 天然为目标架构，避免在 amd64 主机上交叉编译 arm64 CGO 失败。
# arm64 会在 QEMU 模拟下构建，较慢但工具链完整。
FROM golang:1.25-bookworm AS builder

# 安装 CGO 编译依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /build

# 复制 Go 模块文件
COPY go.mod go.sum ./

# 下载依赖（利用缓存）
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# 复制源代码
COPY . .

# 跨平台编译参数
ARG TARGETOS
ARG TARGETARCH

# 编译二进制（CGO 启用，动态链接；运行时由 debian:bookworm-slim 提供 glibc）
# 注: 不使用 -linkmode external -extldflags '-static'，避免多架构交叉编译时
# 缺少 aarch64 静态链接工具链导致 arm64 构建失败
RUN CGO_ENABLED=1 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -o meowtv .

# ----------------------------------------
# 阶段 2: runtime - 最终运行镜像
# ----------------------------------------
FROM debian:bookworm-slim AS runtime

# 安装运行时依赖（包括 ffmpeg，使用系统包而非静态编译）
# gosu: 用于 entrypoint 降权执行主程序（比 su/sudo 更安全，不保留 root 环境）
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    curl \
    ffmpeg \
    gosu \
    && rm -rf /var/lib/apt/lists/*

# 设置时区
ENV TZ=Asia/Shanghai
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

# 创建工作目录
WORKDIR /app

# 复制 Go 二进制
COPY --from=builder /build/meowtv /app/meowtv

# 复制默认配置文件（开箱即用；可被 bind mount 覆盖）
COPY configs/ /app/configs/

# 复制入口点脚本（负责 chown 挂载目录 + gosu 降权）
COPY docker-entrypoint.sh /app/docker-entrypoint.sh

# 创建非 root 用户（uid/gid=1000，对应 entrypoint PUID/PGID 默认值）
# 注意: 不在此处 USER 切换，因 entrypoint 需以 root 启动以执行 chown，
#       随后由 gosu 降权到 PUID:PGID 运行主程序
RUN groupadd --gid 1000 meowtv \
    && useradd --uid 1000 --gid meowtv --shell /bin/false --create-home meowtv \
    && chmod +x /app/docker-entrypoint.sh \
    && chown -R meowtv:meowtv /app \
    && mkdir -p /app/data /app/logs

# PUID/PGID 默认值（entrypoint 据此 chown 挂载目录并降权，可通过 -e 覆盖）
ENV PUID=1000
ENV PGID=1000


# 暴露端口（默认 8088，可通过 MEOWTV_SERVER_PORT 覆盖）
EXPOSE 8088

# 健康检查
# 使用 curl 检查 /health 端点，容器启动 10s 后开始检查，每 30s 检查一次
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${MEOWTV_SERVER_PORT:-8088}/health || exit 1

# 环境变量默认（可通过 docker run -e 覆盖）
ENV MEOWTV_APP_ENV=prod
ENV MEOWTV_APP_DEBUG=false

# 入口点（以 root 启动，内部 chown 挂载目录后 gosu 降权到 PUID:PGID）
ENTRYPOINT ["/app/docker-entrypoint.sh"]
