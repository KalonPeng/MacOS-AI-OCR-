#!/bin/bash

# 修复辅助功能权限
# 问题：系统可能授权给了 DerivedData 中的旧路径，而非 /Applications 中的应用

echo "🔧 修复辅助功能权限..."

APP_BUNDLE_ID="com.ocrapp.OCR-CBD"
TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"

# 检查数据库是否存在
if [ ! -f "$TCC_DB" ]; then
    echo "⚠️  找不到 TCC 数据库"
    exit 1
fi

echo "📋 当前辅助功能权限记录:"
sqlite3 "$TCC_DB" "SELECT client, auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client LIKE '%OCR_CBD%';" 2>/dev/null || echo "无记录"

echo ""
echo "🧹 清理旧的权限记录..."
# 删除所有相关的辅助功能权限记录
sqlite3 "$TCC_DB" "DELETE FROM access WHERE service='kTCCServiceAccessibility' AND client LIKE '%OCR_CBD%';" 2>/dev/null

echo "✅ 已清理旧记录"
echo ""
echo "⚠️  请执行以下步骤："
echo "   1. 退出 OCR_CBD 应用"
echo "   2. 打开 系统设置 > 隐私与安全性 > 辅助功能"
echo "   3. 如果看到 OCR_CBD，将其删除"
echo "   4. 从 /Applications/OCR_CBD.app 启动应用"
echo "   5. 系统会弹出授权请求，点击允许"
echo ""
echo "💡 提示：如果没有弹出授权请求，请手动添加："
echo "   在辅助功能设置中点击 [+]，选择 /Applications/OCR_CBD.app"
