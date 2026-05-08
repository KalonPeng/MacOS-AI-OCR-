import SwiftUI
import Carbon
import ServiceManagement

@main
struct OCR_CBDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // 不使用任何 Scene，完全由 AppDelegate 管理
        WindowGroup {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController?
    var screenshotService: ScreenshotService?
    var ocrService: OCRService?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 关闭所有默认窗口
        NSApplication.shared.windows.forEach { $0.close() }
        
        // 初始化服务
        ocrService = OCRService()
        screenshotService = ScreenshotService(ocrService: ocrService!)
        statusBar = StatusBarController(screenshotService: screenshotService!)
        
        // 不在启动时请求权限，改为在用户首次截图时请求
        
        // 注册全局快捷键（使用 HotkeyManager）
        HotkeyManager.shared.register { [weak self] in
            self?.screenshotService?.startScreenshot()
        }
        
        // 设置应用激活策略为辅助应用（不显示在 Dock，但可以有窗口）
        NSApp.setActivationPolicy(.accessory)
    }
    
    // 防止最后一个窗口关闭时应用退出
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 防止点击 Dock 图标后应用激活但无响应
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }
}
