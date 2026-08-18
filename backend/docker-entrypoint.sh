#!/bin/sh
# ============================================================
# MeowTV 后端 Docker 入口点
#
# 职责:
#   1. 以 root 身份启动（便于 chown 挂载目录）
#   2. 确保挂载目录存在
#   3. 将挂载目录属主修正为 PUID:PGID（匹配宿主机用户）
#   4. 用 gosu 降权到 PUID:PGID 执行主程序
#
# 为什么需要 entrypoint:
#   bind mount 会覆盖镜像层目录，Docker daemon 首次自动创建
#   宿主机挂载目录时以 root 身份，导致目录属主为 root，
#   容器进程以非 root 的 PUID:PGID 运行时无法写入。
#   本脚本在启动前统一 chown 修复，再用 gosu 降权运行。
#
# 环境变量:
#   PUID  运行用户 UID（默认 1000，对应镜像内 meowtv）
#   PGID  运行用户 GID（默认 1000，对应镜像内 meowtv）
# ============================================================
set -eu

# PUID/PGID 由 Dockerfile ENV 默认 1000:1000（镜像内 meowtv），
# 可通过 docker run -e / compose environment 覆盖以匹配宿主机用户
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# 校验为非负整数（防止误传导致 chown/gosu 失败）
if ! [ "${PUID}" -ge 0 ] 2>/dev/null; then
    echo "[entrypoint] ERROR: PUID 非法（须为非负整数）: ${PUID}" >&2
    exit 1
fi
if ! [ "${PGID}" -ge 0 ] 2>/dev/null; then
    echo "[entrypoint] ERROR: PGID 非法（须为非负整数）: ${PGID}" >&2
    exit 1
fi

if [ "${PUID}" = "1000" ] && [ "${PGID}" = "1000" ]; then
    echo "[entrypoint] WARN: 使用默认 PUID/PGID=1000:1000，若挂载目录属主非此值将导致权限不匹配"
    echo "[entrypoint]        建议 docker run 传 -e PUID=\$(id -u) -e PGID=\$(id -g)"
fi

echo "[entrypoint] 运行用户: uid=${PUID} gid=${PGID}"

# 确保挂载目录存在（即便 bind mount 未覆盖，镜像内也有默认目录）
mkdir -p /app/data /app/logs

# 修正挂载目录属主为 PUID:PGID
# bind mount 源目录可能由 Docker daemon 以 root 创建，这里统一修复
echo "[entrypoint] 修正挂载目录属主: /app/data /app/logs -> ${PUID}:${PGID}"
chown -R "${PUID}:${PGID}" /app/data /app/logs

# gosu 降权执行主程序（不保留 root 环境，比 su/sudo 更安全）
echo "[entrypoint] 降权启动: /app/meowtv $*"
exec gosu "${PUID}:${PGID}" /app/meowtv "$@"
