# OCR 截图转文字工具

一个简洁的 macOS 截图 OCR 工具，支持快捷键截图和 AI 文字识别。

## 功能特点

- 🖥️ **系统栏应用**：驻留在系统栏，不干扰工作
- ⌨️ **快捷键截图**：Command + Shift + R 快速截图
- 🎯 **区域选择**：拖拽选择要识别的区域
- 🤖 **AI 识别**：基于智谱 AI GLM-OCR 模型的高精度文字识别
- 📋 **自动复制**：识别结果自动复制到剪切板
- ⚙️ **简洁配置**：只需 5 个核心配置项

## 快速开始

### 1. 打开项目

双击 `OCR_CBD.xcodeproj` 用 Xcode 打开项目。

### 2. 编译运行

在 Xcode 中:
1. 选择运行目标为 "My Mac"
2. 点击运行按钮 (▶️) 或按 `Command + R`

### 3. 配置 API

首次运行时:
1. 点击系统栏图标
2. 选择"设置"
3. 在 "OCR 配置" 标签页填写:
   - **Base URL**: `https://open.bigmodel.cn/api/paas/v4/layout_parsing`
   - **API Key**: 你的智谱 AI API 密钥（格式：`xxxxx.xxxxxxxxxxxxxxxx`）
   - **Model**: `glm-ocr`
   - ~~**System Message**: 智谱 OCR 不需要（留空）~~
   - ~~**User Message**: 智谱 OCR 不需要（留空）~~
4. 点击"测试连接"确认配置正确
5. 点击"保存"

### 4. 使用

1. 按 `Command + Shift + R` 触发截图
2. 拖动鼠标选择要识别的区域
3. 等待 AI 识别（会显示"正在识别..."）
4. 识别完成后:
   - 文字自动复制到剪切板
   - 弹出结果窗口显示识别的文字
   - 可以再次点击"复制"按钮

## 权限设置

首次使用需要授予以下权限：

### 方法一：自动修复（推荐）

如果遇到权限混乱问题（授权后仍然无效），使用一键修复脚本：

```bash
# 1. 退出应用
# 2. 运行修复脚本
cd /path/to/OCR_CBD
./fix_all_permissions.sh

# 3. 按照提示操作
# 4. 从 /Applications 启动应用
open /Applications/OCR_CBD.app
```

### 方法二：手动设置

**屏幕录制权限**（截图功能需要）：
1. 系统设置 → 隐私与安全性 → 屏幕录制
2. 确保授权给 `/Applications/OCR_CBD.app`
3. 如果列表中有其他路径的 OCR_CBD，请删除

**辅助功能权限**（全局快捷键需要）：
1. 系统设置 → 隐私与安全性 → 辅助功能
2. 确保授权给 `/Applications/OCR_CBD.app`
3. 如果列表中有其他路径的 OCR_CBD，请删除

⚠️ **重要提示**：权限必须授予 `/Applications/OCR_CBD.app`，而不是 DerivedData 中的临时路径

## 系统要求

- macOS 13.0 或更高版本
- Xcode 15.0 或更高版本
- 智谱 AI API 密钥

## 获取 API Key

访问 [智谱AI开放平台](https://open.bigmodel.cn/) 注册账号并获取 API Key。

### GLM-OCR 模型特性

- **版面解析**：自动识别文档布局结构
- **高精度识别**：支持图片和PDF文档的OCR识别
- **多格式输出**：提供Markdown格式和详细布局信息
- **图片限制**：单图 ≤10MB，PDF ≤50MB，最大支持100页

## 常见问题

**Q: 为什么截图后没有反应?**  
A: 请确保已授予屏幕录制权限。

**Q: 识别失败怎么办?**  
A: 检查:
- API Key 是否正确（格式：`xxxxx.xxxxxxxxxxxxxxxx`）
- Base URL 是否为 `https://open.bigmodel.cn/api/paas/v4/layout_parsing`
- Model 是否为 `glm-ocr`
- 网络连接是否正常
- 图片是否符合要求（≤10MB）
- 在设置中点击"测试连接"查看详细错误

**Q: 如何更改快捷键?**  
A: 当前版本快捷键固定为 Command + Shift + R，后续版本会支持自定义。

## 项目结构

```
OCR_CBD/
├── OCR_CBDApp.swift          # 应用入口和快捷键注册
├── ContentView.swift         # 主视图和系统栏控制器
├── OCRService.swift          # OCR 服务和 API 调用
├── ScreenshotService.swift   # 截图服务和区域选择
├── SettingsView.swift        # 设置界面
├── Info.plist                # 应用配置
└── OCR_CBD.entitlements      # 权限声明
```

## 许可证

MIT License
