#!/bin/sh
#
# MeowTV Web Frontend 容器启动脚本
#
# 功能:
#   1. 读取 BACKEND_URL 环境变量（默认 http://meowtv:8088）
#   2. 使用 envsubst 将 nginx.conf.template 中的 ${BACKEND_URL} 替换为实际值
#   3. 生成最终的 nginx.conf
#   4. 启动 nginx
#
# 环境变量:
#   BACKEND_URL - 后端 API 服务地址（默认: http://meowtv:8088）
#

set -e

# 默认后端地址（export 给 envsubst 子进程使用）
export BACKEND_URL="${BACKEND_URL:-http://meowtv:8088}"

echo "[entrypoint] BACKEND_URL=${BACKEND_URL}"

# 使用 envsubst 替换 nginx.conf.template 中的占位符
# 只替换 BACKEND_URL 变量，避免破坏 nginx 自身的 $xxx 语法
envsubst '${BACKEND_URL}' < /etc/nginx/conf.d/default.conf.template > /etc/nginx/conf.d/default.conf

# 校验替换结果是否为空，避免生成无效配置
if ! grep -q "proxy_pass http" /etc/nginx/conf.d/default.conf; then
    echo "[entrypoint] 错误：BACKEND_URL 替换失败，proxy_pass 为空" >&2
    exit 1
fi

echo "[entrypoint] nginx.conf 已生成"

# 验证配置文件语法
nginx -t

echo "[entrypoint] 启动 nginx..."
exec nginx -g 'daemon off;'
