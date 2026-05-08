import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "doc.text.viewfinder")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("OCR 截图转文字工具")
                .font(.title)
            Text("请使用 Command+Shift+R 截图")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}

// Status Bar Controller
class StatusBarController {
    private var statusItem: NSStatusItem?
    private var screenshotService: ScreenshotService
    private var settingsWindow: NSWindow?
    private var logWindow: NSWindow?
    private var historyWindow: NSWindow?  // 历史记录窗口
    
    init(screenshotService: ScreenshotService) {
        self.screenshotService = screenshotService
        setupStatusBar()
        // 将自己传递给 ScreenshotService 以获取菜单栏位置
        screenshotService.statusBarController = self
        
        // 监听快捷键变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenu),
            name: .hotkeyDidChange,
            object: nil
        )
        
        // 监听图标变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateIcon),
            name: .statusBarIconDidChange,
            object: nil
        )
        
        // 监听打开设置窗口的请求
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: NSNotification.Name("OpenSettingsWindow"),
            object: nil
        )
    }
    
    // 获取菜单栏按钮的位置
    func getStatusBarButtonFrame() -> NSRect? {
        return statusItem?.button?.window?.frame
    }
    
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            updateIcon()
            button.action = #selector(showMenu)
            button.target = self
        }
        
        updateMenu()
    }
    
    @objc func updateIcon() {
        if let button = statusItem?.button {
            button.image = StatusBarIconManager.shared.getStatusBarImage()
        }
    }
    
    @objc func showMenu() {
        updateMenu()
        statusItem?.menu = statusItem?.menu // 强制刷新菜单
        statusItem?.button?.performClick(nil)
    }
    
    @objc func updateMenu() {
        let menu = NSMenu()
        
        // 获取版本号
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let versionItem = NSMenuItem(title: "版本 \(version) (\(build))", action: nil, keyEquivalent: "")
        versionItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 开始截图菜单项（始终显示，但快捷键提示根据启用状态显示）
        let screenshotItem: NSMenuItem
        if HotkeyManager.shared.isEnabled {
            let hotkeyString = HotkeyManager.shared.currentHotkey.displayString
            screenshotItem = NSMenuItem(title: "开始截图", action: #selector(startScreenshot), keyEquivalent: "")
            screenshotItem.attributedTitle = NSAttributedString(string: "开始截图    \(hotkeyString)", attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.labelColor
            ])
        } else {
            screenshotItem = NSMenuItem(title: "开始截图", action: #selector(startScreenshot), keyEquivalent: "")
        }
        screenshotItem.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)
        menu.addItem(screenshotItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let historyItem = NSMenuItem(title: "查看历史", action: #selector(openHistory), keyEquivalent: "h")
        historyItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        menu.addItem(historyItem)
        
        let logItem = NSMenuItem(title: "显示调试日志", action: #selector(openLogWindow), keyEquivalent: "l")
        logItem.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)
        menu.addItem(logItem)
        
        let settingsItem = NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let fixItem = NSMenuItem(title: "权限修复", action: #selector(fixPermissions), keyEquivalent: "")
        fixItem.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
        menu.addItem(fixItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        menu.addItem(quitItem)
        
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
    }
    
    @objc func startScreenshot() {
        screenshotService.startScreenshot()
    }
    
    @objc func openSettings() {
        // 如果设置窗口已经存在，直接显示
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // 创建新的设置窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 550),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        
        // 设置窗口关闭后的处理
        window.isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.settingsWindow = nil
            // 确保应用不会处于假死状态
            NSApp.deactivate()
        }
        
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func openLogWindow() {
        // 如果日志窗口已经存在，直接显示
        if let window = logWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // 创建新的日志窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "调试日志"
        window.contentView = NSHostingView(rootView: LogWindowView())
        window.center()
        window.isReleasedWhenClosed = false
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.logWindow = nil
        }
        
        logWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        LogManager.shared.log("日志窗口已打开", level: .info)
    }
    
    @objc func openHistory() {
        // 如果历史记录窗口已经存在，直接显示
        if let window = historyWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // 创建新的历史记录窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "识别历史"
        window.contentView = NSHostingView(rootView: HistoryViewWrapper(window: window))
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 400)
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.historyWindow = nil
        }
        
        historyWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        LogManager.shared.log("历史记录窗口已打开", level: .info)
    }
    
    @objc func fixPermissions() {
        // 先显示确认对话框
        let alert = NSAlert()
        alert.messageText = "权限修复工具"
        alert.informativeText = """
        此工具将执行以下操作来修复权限问题：
        
        🔍 将要执行的操作：
        • 查找并清理所有应用副本
        • 删除非 ~/Applications 目录的旧版本
        • 重新注册应用到系统
        • 重置屏幕录制权限
        • 重置辅助功能权限（全局快捷键）
        
        ⚠️ 注意事项：
        • 操作过程中应用会自动退出
        • 需要手动重新启动应用
        • 重启后需要重新授予权限
        
        📝 操作完成后请：
        1. 从 ~/Applications 重新启动 OCR_CBD
        2. 在权限弹窗中点击「好」
        3. 打开「系统设置」→「隐私与安全性」
        4. 在「屏幕录制」和「辅助功能」中勾选 OCR_CBD
        
        是否继续？
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "继续修复")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        
        // 用户取消
        if response != .alertFirstButtonReturn {
            LogManager.shared.log("用户取消权限修复", level: .info)
            return
        }
        
        // 显示进度对话框
        let progressAlert = NSAlert()
        progressAlert.messageText = "正在修复权限..."
        progressAlert.informativeText = "请稍候，详细日志可在「调试日志」窗口查看"
        progressAlert.alertStyle = .informational
        
        // 在后台线程执行修复
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performPermissionFix()
        }
    }
    
    private func performPermissionFix() {
        LogManager.shared.log("=== 开始权限修复 ===", level: .info)
        
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let appPath = Bundle.main.bundlePath
        let appName = "OCR_CBD"
        
        LogManager.shared.log("Bundle ID: \(bundleID)", level: .info)
        LogManager.shared.log("当前路径: \(appPath)", level: .info)
        
        // 步骤 1: 查找所有版本
        LogManager.shared.log("", level: .info)
        LogManager.shared.log("📋 步骤 1/5: 查找所有应用副本", level: .warning)
        
        var foundApps: [String] = []
        let task1 = Process()
        task1.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        task1.arguments = ["kMDItemCFBundleIdentifier == '\(bundleID)'"]
        
        let pipe1 = Pipe()
        task1.standardOutput = pipe1
        
        do {
            try task1.run()
            task1.waitUntilExit()
            
            let data = pipe1.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                foundApps = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                LogManager.shared.log("找到 \(foundApps.count) 个应用副本:", level: .info)
                for app in foundApps {
                    LogManager.shared.log("  • \(app)", level: .info)
                }
            }
        } catch {
            LogManager.shared.log("❌ 查找失败: \(error.localizedDescription)", level: .error)
        }
        
        // 步骤 2: 删除所有非 /Applications 的副本
        LogManager.shared.log("", level: .info)
        LogManager.shared.log("🗑️  步骤 2/5: 删除旧版本", level: .warning)
        
        for app in foundApps {
            // 保留 /Applications 和 DerivedData 中的版本
            if !app.contains("/Applications/") && !app.contains("DerivedData") {
                do {
                    try FileManager.default.removeItem(atPath: app)
                    LogManager.shared.log("✅ 已删除: \(app)", level: .success)
                } catch {
                    LogManager.shared.log("❌ 删除失败 \(app): \(error.localizedDescription)", level: .error)
                }
            }
        }
        
        // 步骤 3: 清理 Xcode DerivedData
        LogManager.shared.log("", level: .info)
        LogManager.shared.log("🧹 步骤 3/5: 清理构建缓存", level: .warning)
        
        let derivedDataPath = NSString(string: "~/Library/Developer/Xcode/DerivedData").expandingTildeInPath
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: derivedDataPath) {
            for item in contents where item.contains("OCR_CBD") {
                let fullPath = (derivedDataPath as NSString).appendingPathComponent(item)
                do {
                    try FileManager.default.removeItem(atPath: fullPath)
                    LogManager.shared.log("✅ 已删除: \(item)", level: .success)
                } catch {
                    LogManager.shared.log("❌ 删除失败: \(error.localizedDescription)", level: .error)
                }
            }
        }
        
        // 步骤 4: 重新注册 ~/Applications 中的应用
        LogManager.shared.log("", level: .info)
        LogManager.shared.log("📝 步骤 4/5: 重新注册应用", level: .warning)
        
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let targetApp = "\(homeDir)/Applications/\(appName).app"
        if FileManager.default.fileExists(atPath: targetApp) {
            let task4 = Process()
            task4.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
            task4.arguments = ["-f", "-R", "-trusted", targetApp]
            
            do {
                try task4.run()
                task4.waitUntilExit()
                LogManager.shared.log("✅ 已注册: \(targetApp)", level: .success)
            } catch {
                LogManager.shared.log("❌ 注册失败: \(error.localizedDescription)", level: .error)
            }
        } else {
            LogManager.shared.log("❌ 错误: \(targetApp) 不存在", level: .error)
        }
        
        // 步骤 5: 重置屏幕录制权限
        LogManager.shared.log("", level: .info)
        LogManager.shared.log("🔐 步骤 5/7: 重置屏幕录制权限", level: .warning)
        
        let task5 = Process()
        task5.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task5.arguments = ["reset", "ScreenCapture", bundleID]
        
        do {
            try task5.run()
            task5.waitUntilExit()
            LogManager.shared.log("✅ 屏幕录制权限已重置", level: .success)
        } catch {
            LogManager.shared.log("❌ 重置失败: \(error.localizedDescription)", level: .error)
        }
        
        // 步骤 6: 重置辅助功能权限
        LogManager.shared.log("", level: .info)
        LogManager.shared.log("⌨️  步骤 6/7: 重置辅助功能权限", level: .warning)
        
        let task6 = Process()
        task6.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task6.arguments = ["reset", "Accessibility", bundleID]
        
        do {
            try task6.run()
            task6.waitUntilExit()
            LogManager.shared.log("✅ 辅助功能权限已重置", level: .success)
        } catch {
            LogManager.shared.log("❌ 重置失败: \(error.localizedDescription)", level: .error)
        }
        
        // 步骤 7: 刷新系统缓存（Dock & Finder）
        LogManager.shared.log("", level: .info)
        LogManager.shared.log("🔄 步骤 7/7: 刷新系统图标缓存", level: .warning)
        
        // 刷新 Dock
        let killDock = Process()
        killDock.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killDock.arguments = ["Dock"]
        
        do {
            try killDock.run()
            killDock.waitUntilExit()
            LogManager.shared.log("✅ Dock 已刷新", level: .success)
        } catch {
            LogManager.shared.log("❌ Dock 刷新失败: \(error.localizedDescription)", level: .error)
        }
        
        // 刷新 Finder
        let killFinder = Process()
        killFinder.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killFinder.arguments = ["Finder"]
        
        do {
            try killFinder.run()
            killFinder.waitUntilExit()
            LogManager.shared.log("✅ Finder 已刷新", level: .success)
        } catch {
            LogManager.shared.log("❌ Finder 刷新失败: \(error.localizedDescription)", level: .error)
        }
        
        // 完成提示
        LogManager.shared.log("", level: .info)
        LogManager.shared.log("=== 权限修复完成 ===", level: .success)
        
        // 在主线程显示完成对话框
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "权限修复完成"
            alert.informativeText = """
            已完成以下操作：
            ✅ 清理所有旧版本副本
            ✅ 清理构建缓存
            ✅ 重新注册应用到系统
            ✅ 重置屏幕录制权限
            ✅ 重置辅助功能权限
            ✅ 刷新系统图标缓存
            
            请按以下步骤重新授权：
            
            1️⃣ 应用即将退出并自动重启
            2️⃣ 打开「系统设置」→「隐私与安全性」
            3️⃣ 在「屏幕录制」中勾选 OCR_CBD
            4️⃣ 在「辅助功能」中勾选 OCR_CBD
            
            ⚠️ 重要：确保授权的是 ~/Applications/OCR_CBD.app
            
            点击「确定」后应用将自动重启。
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定并重启应用")
            
            alert.runModal()
            
            // 重启应用 - 使用更可靠的方式
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let appPath = "\(homeDir)/Applications/OCR_CBD.app"
            
            // 创建临时脚本来延迟启动新实例
            let script = """
            #!/bin/bash
            # 等待当前实例完全退出
            sleep 2
            # 启动新实例
            open "\(appPath)"
            # 删除自己
            rm -f "$0"
            """
            
            let tempScriptPath = NSTemporaryDirectory() + "restart_ocr_cbd.sh"
            
            do {
                try script.write(toFile: tempScriptPath, atomically: true, encoding: .utf8)
                
                // 设置脚本可执行权限
                let chmod = Process()
                chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmod.arguments = ["+x", tempScriptPath]
                try chmod.run()
                chmod.waitUntilExit()
                
                // 在后台执行脚本（分离进程）
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/bash")
                task.arguments = ["-c", "nohup \(tempScriptPath) > /dev/null 2>&1 &"]
                task.standardOutput = nil
                task.standardError = nil
                
                try task.run()
                
                LogManager.shared.log("重启脚本已启动，应用即将退出", level: .info)
                
                // 立即退出当前实例
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApplication.shared.terminate(nil)
                }
            } catch {
                LogManager.shared.log("❌ 重启失败: \(error.localizedDescription)", level: .error)
                
                // 如果脚本方式失败，尝试简单的 open 命令
                let fallbackTask = Process()
                fallbackTask.launchPath = "/usr/bin/open"
                fallbackTask.arguments = ["-n", appPath]
                try? fallbackTask.run()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
