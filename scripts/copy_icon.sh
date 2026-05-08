#!/bin/bash
# 复制应用图标到构建产物

set -e

echo "📦 复制应用图标..."

# 获取构建产物路径
BUILD_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"
RESOURCES_DIR="${BUILD_DIR}/Contents/Resources"

# 确保 Resources 目录存在
mkdir -p "${RESOURCES_DIR}"

# 复制 .icns 文件
ICON_SOURCE="${SOURCE_ROOT}/OCR_CBD/AppIcon.icns"
if [ -f "${ICON_SOURCE}" ]; then
    cp "${ICON_SOURCE}" "${RESOURCES_DIR}/AppIcon.icns"
    echo "  ✅ AppIcon.icns 已复制到 ${RESOURCES_DIR}"
else
    echo "  ⚠️ 找不到 ${ICON_SOURCE}"
    exit 1
fi

echo "✅ 应用图标处理完成"
