.PHONY: help clean build install debug release run open

SCHEME = OCR_CBD
PROJECT = OCR_CBD.xcodeproj
APP_NAME = OCR_CBD
INSTALL_DIR = /Applications

help:
	@echo "======================================"
	@echo "OCR_CBD 构建命令"
	@echo "======================================"
	@echo ""
	@echo "make build     - 构建 Release 版本（自动安装到 /Applications）"
	@echo "make debug     - 构建 Debug 版本"
	@echo "make release   - 等同于 build"
	@echo "make install   - 手动安装到 /Applications"
	@echo "make clean     - 清理构建产物"
	@echo "make run       - 运行已安装的应用"
	@echo "make open      - 打开 Xcode 项目"
	@echo ""

clean:
	@echo "🧹 清理构建产物..."
	@xcodebuild clean -project $(PROJECT) -scheme $(SCHEME) -configuration Release
	@xcodebuild clean -project $(PROJECT) -scheme $(SCHEME) -configuration Debug
	@rm -rf build/
	@echo "✅ 清理完成"

debug:
	@echo "🔨 构建 Debug 版本..."
	@xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -configuration Debug

build: release

release:
	@echo "🔨 构建 Release 版本（会自动安装到 /Applications）..."
	@if [ -f "APP_ICON.png" ]; then \
		echo "🎨 检测到 APP_ICON.png，更新应用图标..."; \
		./update_icon_from_png.sh APP_ICON.png; \
	fi
	@xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -configuration Release
	@echo ""
	@echo "✅ 构建完成！应用已安装到 $(INSTALL_DIR)/$(APP_NAME).app"

install:
	@echo "📦 手动安装到 /Applications..."
	@./install.sh

run:
	@echo "🚀 启动应用..."
	@killall $(APP_NAME) 2>/dev/null || true
	@sleep 1
	@open $(INSTALL_DIR)/$(APP_NAME).app

open:
	@echo "🔧 打开 Xcode 项目..."
	@open $(PROJECT)
