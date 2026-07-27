# ============================================================
# MeowTV Flutter Android Docker 构建镜像
#
# 支持 amd64 / arm64 架构（通过 TARGETARCH 自动适配）
# iOS 构建不支持（需要 macOS + Xcode）
#
# 构建命令（从项目根目录）:
#   单架构: docker build -f scripts/frontend/Dockerfile -t meowtv-flutter:latest frontend/
#   多架构: docker buildx build --platform linux/amd64,linux/arm64 -f scripts/frontend/Dockerfile -t meowtv-flutter:latest frontend/ --push
#
# 注意: build context 为 frontend/ 目录
# ============================================================

# ----------------------------------------
# 阶段 1: base - 安装 Flutter SDK 和 Android SDK
# ----------------------------------------
FROM ubuntu:24.04 AS base

# 避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 安装基础依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    wget \
    openjdk-17-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

# Flutter SDK 版本
ENV FLUTTER_VERSION=3.11.5
ENV FLUTTER_SDK=/opt/flutter

# 克隆 Flutter SDK（使用 stable 分支并切换到指定版本）
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git ${FLUTTER_SDK}

# 设置 PATH
ENV PATH="${FLUTTER_SDK}/bin:${PATH}"

# 禁用 Flutter 自动更新检查（容器环境不需要）
ENV FLUTTER_SUPPRESS_ANALYTICS=true

# 预热 Flutter（下载 Dart SDK、初始化缓存）
RUN flutter precache --no-ios --no-web --no-linux --no-macos --no-windows

# ----------------------------------------
# 阶段 2: android-sdk - 安装 Android SDK
# ----------------------------------------
FROM base AS android-sdk

# Android SDK 配置
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=${ANDROID_SDK_ROOT}
ENV PATH="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${PATH}"

# 安装 Android command-line tools
RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools && \
    cd ${ANDROID_SDK_ROOT}/cmdline-tools && \
    wget --no-check-certificate \
        --user-agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
        -O commandlinetools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" && \
    unzip -q commandlinetools.zip && \
    mv cmdline-tools latest && \
    rm commandlinetools.zip

# 接受协议并安装必需的 SDK 组件
# compileSdk=36, build-tools=36.0.0, ndk=29.0.14033849, platform-tools
RUN yes | ${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null 2>&1 || true && \
    ${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager --install \
        "platform-tools" \
        "platforms;android-36" \
        "build-tools;36.0.0" \
        "ndk;29.0.14033849"

# 配置 Android SDK 路径（供 Flutter 使用）
RUN flutter config --android-sdk ${ANDROID_SDK_ROOT}

# 接受 Android 许可证
RUN yes | flutter doctor --android-licenses >/dev/null 2>&1 || true

# 验证安装
RUN flutter doctor

# ----------------------------------------
# 阶段 3: builder - 执行 Flutter 构建
# ----------------------------------------
FROM android-sdk AS builder

# 复制 Flutter 项目（build context 为 frontend/）
COPY app/ /app/

# 设置工作目录
WORKDIR /app

# 清理缓存并重新获取依赖
RUN flutter clean
RUN flutter pub get

# 构建类型由 ARG 传入，默认为 split
ARG BUILD_TYPE=split
ENV BUILD_TYPE=${BUILD_TYPE}

# Flutter 构建
# split: flutter build apk --release --split-per-abi（按架构拆分 APK）
# fat:   flutter build apk --release（单个 APK 包含所有架构）
# appbundle: flutter build appbundle --release（AAB，用于 Google Play）
RUN case "${BUILD_TYPE}" in \
        appbundle) \
            flutter build appbundle --release ;; \
        fat) \
            flutter build apk --release ;; \
        split|*) \
            flutter build apk --release --split-per-abi ;; \
    esac

# ----------------------------------------
# 阶段 4: collector - 收集构建产物
# ----------------------------------------
FROM busybox:musl AS collector

# 收集 Android 产物
COPY --from=builder /app/build/app/outputs/flutter-apk/ /output/apk/
COPY --from=builder /app/build/app/outputs/bundle/ /output/bundle/

# 创建输出目录结构
WORKDIR /output

# 将所有 APK 复制到根目录方便提取
# 注意: 这个阶段的文件结构会被 docker cp 直接提取到宿主机
