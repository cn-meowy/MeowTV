# ============================================================
# MeowTV Web Frontend Docker 构建镜像
#
# 多阶段构建：
#   阶段 1 (builder): node:22-alpine 用于构建前端
#   阶段 2 (runtime): nginx:1.27-alpine 用于运行静态产物
#
# 支持 amd64 / arm64 架构
# builder 阶段固定使用 --platform=$BUILDPLATFORM（构建机原生架构）运行：
#   前端产物为静态文件、与目标架构无关，无需模拟；
#   且可避开 QEMU 模拟 arm64 Node/pnpm 时 SIGILL (signal 4) 崩溃的已知问题。
# 仅 runtime 阶段按目标架构构建（QEMU 下仅 apk add，轻量可靠）。
#
# 构建命令（从项目根目录）:
#   单架构: docker build -f scripts/frontend/web/Dockerfile -t meowtv-web:latest .
#   多架构: docker buildx build --platform linux/amd64,linux/arm64 -f scripts/frontend/web/Dockerfile -t meowtv-web:latest . --push
#
# 注意: build context 为项目根目录（使 scripts/ 与 frontend/ 同时可见）
# ============================================================

# ----------------------------------------
# 阶段 1: builder - 构建前端
# ----------------------------------------
# --platform=$BUILDPLATFORM: 始终以构建机原生架构运行（产物为静态文件，与目标架构无关）
FROM --platform=$BUILDPLATFORM node:22-alpine AS builder

# 安装 pnpm
RUN corepack enable && corepack prepare pnpm@9.0.0 --activate

# 设置工作目录
WORKDIR /app

# 复制 package.json 和 pnpm-lock.yaml（利用 Docker 缓存层）
COPY frontend/web/package.json frontend/web/pnpm-lock.yaml ./

# 安装依赖（使用 frozen lockfile 确保一致性）
RUN pnpm install --frozen-lockfile

# 复制源码
COPY frontend/web/ ./

# 构建前端（生产构建）
RUN pnpm run build

# ----------------------------------------
# 阶段 2: runtime - Nginx 运行
# ----------------------------------------
FROM nginx:1.27-alpine AS runtime

# 安装 gettext（提供 envsubst 命令，用于模板替换）
RUN apk add --no-cache gettext

# 复制 nginx 配置模板（直接从构建上下文，不经 builder 中转）
COPY scripts/frontend/web/nginx.conf.template /etc/nginx/conf.d/default.conf.template

# 复制 entrypoint 启动脚本（直接从构建上下文，不经 builder 中转）
COPY scripts/frontend/web/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 复制前端构建产物
COPY --from=builder /app/dist/ /usr/share/nginx/html/

# 暴露端口
EXPOSE 80

# 设置入口点
ENTRYPOINT ["/entrypoint.sh"]
