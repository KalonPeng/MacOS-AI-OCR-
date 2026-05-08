#!/bin/bash

# Xcode Post-Build Script
# 自动清理旧版本并安装到 /Applications

# 不要用 set -e，避免小错误导致构建失败

BUNDLE_ID="com.ocrapp.OCR-CBD"
APP_NAME="OCR_CBD"
INSTALL_DIR="/Applications"

echo "======================================"
echo "📦 Post-Build: 自动安装与清理"
echo "======================================"

# 只在 Release 配置时执行
if [ "${CONFIGURATION}" != "Release" ]; then
    echo "⏭️  跳过: 仅在 Release 模式下自动安装"
    exit 0
fi

echo "✅ 检测到 Release 构建，开始自动安装..."

# 1. 停止旧实例
echo "1️⃣ 停止运行中的实例..."
killall "$APP_NAME" 2>/dev/null || true
sleep 1

# 2. 安装到 /Applications（先安装再清理）
echo "2️⃣ 安装到 $INSTALL_DIR..."

# 获取当前构建的应用路径
BUILT_APP="${BUILT_PRODUCTS_DIR}/${APP_NAME}.app"

echo "   构建产物: $BUILT_APP"

if [ ! -d "$BUILT_APP" ]; then
    echo "❌ 错误: 找不到构建产物"
    echo "   BUILT_PRODUCTS_DIR=$BUILT_PRODUCTS_DIR"
    exit 0
fi

# 删除 /Applications 中的旧版本
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "   删除旧版本..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

# 使用 ditto 复制（保留权限和元数据）
echo "   安装新版本..."
ditto "$BUILT_APP" "$INSTALL_DIR/$APP_NAME.app"

if [ ! -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "❌ 安装失败"
    exit 0
fi

echo "✅ 安装成功: $INSTALL_DIR/$APP_NAME.app"

# 3. 清理其他位置的所有副本
echo ""
echo "3️⃣ 清理其他位置的副本..."

# 删除常见位置
rm -rf ~/Desktop/"$APP_NAME.app" 2>/dev/null && echo "   ✅ 已删除: ~/Desktop/$APP_NAME.app" || true
rm -rf ~/Downloads/"$APP_NAME.app" 2>/dev/null && echo "   ✅ 已删除: ~/Downloads/$APP_NAME.app" || true

# 查找并删除所有其他位置（保留 /Applications 和 DerivedData）
echo "   搜索系统中的其他副本..."
mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null | while read app; do
    # 跳过 /Applications 和 DerivedData
    if [[ "$app" != "$INSTALL_DIR/$APP_NAME.app" ]] && [[ "$app" != *"DerivedData"* ]]; then
        echo "   🗑️  删除: $app"
        rm -rf "$app" 2>/dev/null || true
    fi
done


# 4. 显示签名信息
echo ""
echo "📋 应用信息:"
codesign -dvvv "$INSTALL_DIR/$APP_NAME.app" 2>&1 | grep -E "Identifier=|CDHash=" || true

# 5. 注册到 Launch Services
echo ""
echo "4️⃣ 注册应用到系统..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true

# 6. 最终验证
echo ""
echo "5️⃣ 验证系统中的应用副本..."
ALL_APPS=$(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null)
APP_COUNT=$(echo "$ALL_APPS" | grep -c . || echo "0")

if [ "$APP_COUNT" -eq 1 ] && [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "✅ 完美！系统中只有一个应用副本"
elif [ "$APP_COUNT" -gt 1 ]; then
    echo "⚠️  警告：系统中仍有 $APP_COUNT 个应用副本："
    echo "$ALL_APPS"
else
    echo "⚠️  未找到应用"
fi

echo ""
echo "======================================"
echo "✅ 自动安装完成！"
echo "======================================"
echo ""
echo "💡 提示:"
echo "   • 唯一位置: $INSTALL_DIR/$APP_NAME.app"
echo "   • 其他位置的副本已清理"
echo "   • 首次运行需要授予屏幕录制权限"
echo "   • 可从 Launchpad 或 Spotlight 启动"
echo ""

# 总是返回成功，避免阻止构建
exit 0
