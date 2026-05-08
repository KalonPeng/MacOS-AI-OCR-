import Foundation
import AppKit
import SwiftUI

// MARK: - 可接收键盘焦点的自定义 Panel
class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    
    override func resignKey() {
        super.resignKey()
        // 当失去焦点时不关闭窗口
    }
}

class ScreenshotService: ObservableObject {
    private var ocrService: OCRService
    private var overlayWindow: NSWindow?
    private var lastDebugImagePath: String?
    weak var statusBarController: StatusBarController?  // 用于获取菜单栏位置
    private var notificationWindow: NSWindow?  // 持有通知窗口的强引用
    
    init(ocrService: OCRService) {
        self.ocrService = ocrService
        
        // 设置剪贴板监听回调
        ClipboardMonitor.shared.setOCRCallback { [weak self] image in
            self?.processClipboardImage(image)
        }
    }
    
    func startScreenshot() {
        // 检查屏幕录制权限
        let hasPermission = CGPreflightScreenCaptureAccess()
        
        LogManager.shared.log("=== 权限检查 ===", level: .info)
        LogManager.shared.log("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")", level: .info)
        LogManager.shared.log("权限状态: \(hasPermission)", level: hasPermission ? .success : .warning)
        
        if !hasPermission {
            LogManager.shared.log("缺少屏幕录制权限，正在请求...", level: .warning)
            
            // 先请求权限
            let granted = CGRequestScreenCaptureAccess()
            LogManager.shared.log("权限请求结果: \(granted)", level: granted ? .success : .error)
            
            if !granted {
                let alert = NSAlert()
                alert.messageText = "需要屏幕录制权限"
                alert.informativeText = """
                应用需要屏幕录制权限才能截取屏幕内容。
                
                📱 请按以下步骤授予权限：
                
                1️⃣ 点击下方「打开系统设置」按钮
                2️⃣ 进入「隐私与安全性」→「屏幕录制」
                3️⃣ 在列表中找到「OCR_CBD」并勾选
                4️⃣ 完全退出应用（⌘+Q）
                5️⃣ 重新启动应用
                
                ⚠️ 注意事项：
                • 如果已经勾选但不工作，请取消勾选后重新勾选
                • 必须完全退出应用，不是隐藏或最小化
                
                当前应用ID: \(Bundle.main.bundleIdentifier ?? "unknown")
                """
                alert.alertStyle = .warning
                alert.addButton(withTitle: "打开系统设置")
                alert.addButton(withTitle: "取消")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // 打开系统设置的屏幕录制页面
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                return
            }
        }
        
        LogManager.shared.log("屏幕录制权限已授予", level: .success)
        
        // 使用系统截图工具（更可靠的方案）
        useSystemScreenshot()
    }
    
    // 方案1：使用系统截图工具（推荐）
    private func useSystemScreenshot() {
        LogManager.shared.log("使用系统截图工具...", level: .info)
        
        // 直接启动系统截图，不显示提示
        captureUsingSystemCommand()
    }
    
    // 使用 screencapture 命令
    private func captureUsingSystemCommand() {
        LogManager.shared.log("执行 screencapture 命令...", level: .info)
        
        let tempFile = NSTemporaryDirectory() + "ocr_screenshot_\(UUID().uuidString).png"
        LogManager.shared.log("临时文件路径: \(tempFile)", level: .info)
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = [
            "-i",  // 交互模式（允许用户选择区域）
            "-o",  // 仅捕获窗口（不包含阴影）
            tempFile
        ]
        
        task.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    // 检查文件是否存在
                    if FileManager.default.fileExists(atPath: tempFile) {
                        if let image = NSImage(contentsOfFile: tempFile) {
                            LogManager.shared.log("截图成功: \(tempFile)", level: .success)
                            LogManager.shared.log("图片尺寸: \(image.size.width)x\(image.size.height)", level: .info)
                            self?.performOCR(on: image)
                            
                            // 清理临时文件
                            try? FileManager.default.removeItem(atPath: tempFile)
                        } else {
                            LogManager.shared.log("无法加载图片", level: .error)
                        }
                    } else {
                        LogManager.shared.log("用户取消了截图", level: .info)
                    }
                } else {
                    LogManager.shared.log("screencapture 命令失败: \(process.terminationStatus)", level: .error)
                }
            }
        }
        
        do {
            try task.run()
            LogManager.shared.log("等待用户截图...", level: .info)
        } catch {
            LogManager.shared.log("无法启动 screencapture: \(error)", level: .error)
            showAlert(title: "截图失败", message: "无法启动系统截图工具")
        }
    }
    
    // 执行 OCR
    private func performOCR(on image: NSImage) {
        LogManager.shared.log("开始 OCR 识别...", level: .info)
        LogManager.shared.log("图片信息: \(image.size.width)x\(image.size.height)", level: .info)
        
        // 检查图片是否有效
        guard image.size.width > 0 && image.size.height > 0 else {
            LogManager.shared.log("图片尺寸无效", level: .error)
            showAlert(title: "截图失败", message: "图片尺寸无效，请重试")
            return
        }
        
        // 检查图片是否太小
        if image.size.width < 10 || image.size.height < 10 {
            LogManager.shared.log("图片太小: \(image.size.width)x\(image.size.height)", level: .warning)
            showAlert(title: "截图区域太小", message: "请选择更大的区域进行识别")
            return
        }
        
        showProcessingAlert()
        
        ocrService.recognize(image: image) { [weak self] result in
            DispatchQueue.main.async {
                // hideProcessingAlert 在 showResultWindow 中自动处理
                
                switch result {
                case .success(let text):
                    let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    LogManager.shared.log("OCR 识别完成", level: .info)
                    LogManager.shared.log("原始文本长度: \(text.count), 清理后: \(cleanText.count)", level: .info)
                    
                    if cleanText.isEmpty {
                        LogManager.shared.log("识别结果为空字符串", level: .warning)
                        self?.hideProcessingAlert()
                        self?.showNoTextAlert()
                        return
                    }
                    
                    if cleanText.hasPrefix("![](") {
                        LogManager.shared.log("识别结果只包含图片标记: \(cleanText.prefix(50))", level: .warning)
                        self?.hideProcessingAlert()
                        self?.showNoTextAlert()
                        return
                    }
                    
                    LogManager.shared.log("识别成功，识别到 \(cleanText.count) 个字符", level: .success)
                    LogManager.shared.log("内容预览: \(cleanText.prefix(100))", level: .info)
                    
                    // 显示结果（会根据用户设置自动复制）
                    self?.showResultWindow(text: cleanText)
                    
                case .failure(let error):
                    LogManager.shared.log("识别失败: \(error.localizedDescription)", level: .error)
                    self?.hideProcessingAlert()
                    
                    // 判断是否是 API 配置错误
                    let errorMessage = error.localizedDescription
                    if errorMessage.contains("请先在设置中配置") || 
                       errorMessage.contains("API Key 无效") ||
                       errorMessage.contains("API 地址") {
                        // API 配置相关错误，显示详细的引导信息（保留弹窗，因为需要引导用户配置）
                        self?.showAPIConfigAlert(message: errorMessage)
                    } else {
                        // 其他错误，使用轻量级通知
                        self?.showErrorNotification(message: errorMessage)
                    }
                }
            }
        }
    }
    
    private func showOverlay() {
        let frame = NSScreen.main?.frame ?? NSRect.zero
        print("🖥️  屏幕尺寸: \(frame.width)x\(frame.height)")
        
        // 创建一个特殊的全屏窗口
        let window = ScreenshotWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // 关键配置
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        
        print("🪟 创建覆盖窗口: level=\(window.level.rawValue)")
        
        // 使用纯 NSView 实现，避免 SwiftUI 事件冲突
        let overlayView = ScreenshotOverlayView(frame: frame) { [weak self] rect in
            print("📞 收到截图回调")
            // 先隐藏窗口
            window.orderOut(nil)
            print("🚪 覆盖窗口已隐藏")
            
            if let rect = rect {
                print("⏱️  等待150ms后截图...")
                // 延迟一小段时间，确保窗口完全隐藏并从屏幕刷新
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self?.overlayWindow = nil
                    self?.captureScreen(rect: rect)
                }
            } else {
                print("❌ 未选择有效区域，取消截图")
                self?.overlayWindow = nil
            }
        }
        
        window.contentView = overlayView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // 强制让窗口成为焦点并接收事件
        DispatchQueue.main.async {
            window.makeKey()
            window.makeFirstResponder(overlayView)
            print("✅ 覆盖窗口已显示，FirstResponder=\(window.firstResponder?.className ?? "nil")")
            print("   窗口是否为key: \(window.isKeyWindow)")
            print("   窗口是否可见: \(window.isVisible)")
        }
        
        self.overlayWindow = window
    }
    
    private func captureScreen(rect: CGRect) {
        print("📐 截图区域: x=\(rect.origin.x), y=\(rect.origin.y), w=\(rect.width), h=\(rect.height)")
        print("🪟 覆盖窗口状态: \(overlayWindow == nil ? "已关闭" : "仍然存在")")
        
        guard let image = captureScreenImage(rect: rect) else {
            showAlert(title: "截图失败", message: "无法捕获屏幕内容")
            return
        }
        
        print("🖼️  图片信息: 尺寸=\(image.size.width)x\(image.size.height)")
        
        // 调试：保存截图到桌面（可选）
        #if DEBUG
        saveDebugImage(image)
        #endif
        
        // 显示识别中状态
        showProcessingAlert()
        
        // 执行 OCR
        ocrService.recognize(image: image) { [weak self] result in
            DispatchQueue.main.async {
                self?.hideProcessingAlert()
                
                switch result {
                case .success(let text):
                    // 检查是否只有图片标记而没有实际文本
                    let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanText.isEmpty || cleanText.hasPrefix("![](") {
                        self?.showNoTextAlert()
                        return
                    }
                    
                    // 复制到剪切板
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cleanText, forType: .string)
                    
                    // 显示结果
                    self?.showResultWindow(text: cleanText)
                    
                case .failure(let error):
                    self?.showAlert(title: "识别失败", message: error.localizedDescription)
                }
            }
        }
    }
    
    private func captureScreenImage(rect: CGRect) -> NSImage? {
        // 获取屏幕的缩放因子（Retina屏幕是2.0）
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 1.0
        print("🖥️  屏幕缩放因子: \(scaleFactor)")
        
        // 使用 CGDisplayCreateImage 来截取屏幕内容
        // 这个API可以截取所有可见内容，包括其他应用的窗口
        guard let displayID = CGMainDisplayID() as CGDirectDisplayID? else {
            print("❌ 无法获取主显示器ID")
            return nil
        }
        
        // 将逻辑坐标转换为像素坐标
        let pixelRect = CGRect(
            x: rect.origin.x * scaleFactor,
            y: rect.origin.y * scaleFactor,
            width: rect.width * scaleFactor,
            height: rect.height * scaleFactor
        )
        
        print("📍 逻辑坐标: (\(rect.origin.x), \(rect.origin.y), \(rect.width), \(rect.height))")
        print("📍 像素坐标: (\(pixelRect.origin.x), \(pixelRect.origin.y), \(pixelRect.width), \(pixelRect.height))")
        
        // 截取整个屏幕
        guard let fullScreenImage = CGDisplayCreateImage(displayID) else {
            print("❌ 无法截取屏幕")
            return nil
        }
        
        print("🖼️  全屏图片尺寸: \(fullScreenImage.width)x\(fullScreenImage.height)")
        
        // 裁剪出选中的区域
        guard let croppedImage = fullScreenImage.cropping(to: pixelRect) else {
            print("❌ 无法裁剪图片")
            return nil
        }
        
        let nsImage = NSImage(cgImage: croppedImage, size: rect.size)
        print("🖼️  裁剪后图片: \(croppedImage.width)x\(croppedImage.height) pixels")
        return nsImage
    }
    
    // 调试：保存截图到桌面
    private func saveDebugImage(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "OCR_Debug_\(dateFormatter.string(from: Date())).png"
        let fileURL = desktop.appendingPathComponent(filename)
        
        try? pngData.write(to: fileURL)
        lastDebugImagePath = fileURL.path
        print("🔍 调试图片已保存到: \(fileURL.path)")
    }
    
    private func showNoTextAlert() {
        DispatchQueue.main.async {
            // 使用和识别成功一样的轻量级通知气泡
            // 关闭之前的通知窗口
            self.notificationWindow?.close()
            self.notificationWindow = nil
            
            // 获取菜单栏按钮位置
            guard let buttonFrame = self.statusBarController?.getStatusBarButtonFrame() else {
                return
            }
            
            // 创建轻量级通知窗口，和识别成功的样式一致
            let popoverWidth: CGFloat = 280
            let popoverHeight: CGFloat = 100
            
            let windowX = buttonFrame.origin.x + (buttonFrame.width - popoverWidth) / 2
            let windowY = buttonFrame.origin.y - popoverHeight - 8
            
            let window = NSPanel(
                contentRect: NSRect(x: windowX, y: windowY, width: popoverWidth, height: popoverHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            window.isFloatingPanel = true
            window.level = .statusBar
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = false
            
            window.contentView = NSHostingView(
                rootView: NoTextNotificationView(window: window)
            )
            window.orderFront(nil)
            
            self.notificationWindow = window
            
            // 3秒后自动关闭
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak window] in
                window?.close()
                if self?.notificationWindow === window {
                    self?.notificationWindow = nil
                }
            }
            
            LogManager.shared.log("未识别到文字，已显示通知", level: .warning)
        }
    }
    
    // 显示识别错误的轻量级通知
    private func showErrorNotification(message: String) {
        DispatchQueue.main.async {
            // 关闭之前的通知窗口
            self.notificationWindow?.close()
            self.notificationWindow = nil
            
            // 获取菜单栏按钮位置
            guard let buttonFrame = self.statusBarController?.getStatusBarButtonFrame() else {
                return
            }
            
            // 创建轻量级通知窗口
            let popoverWidth: CGFloat = 280
            let popoverHeight: CGFloat = 120  // 稍微高一点，显示错误信息
            
            let windowX = buttonFrame.origin.x + (buttonFrame.width - popoverWidth) / 2
            let windowY = buttonFrame.origin.y - popoverHeight - 8
            
            let window = NSPanel(
                contentRect: NSRect(x: windowX, y: windowY, width: popoverWidth, height: popoverHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            window.isFloatingPanel = true
            window.level = .statusBar
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = false
            
            window.contentView = NSHostingView(
                rootView: ErrorNotificationView(message: message, window: window)
            )
            window.orderFront(nil)
            
            self.notificationWindow = window
            
            // 4秒后自动关闭（错误信息稍长，多给1秒阅读时间）
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self, weak window] in
                window?.close()
                if self?.notificationWindow === window {
                    self?.notificationWindow = nil
                }
            }
            
            LogManager.shared.log("识别失败，已显示通知", level: .error)
        }
    }
    
    private var processingAlert: NSAlert?
    private var processingWindow: NSWindow?
    
    private func showProcessingAlert() {
        DispatchQueue.main.async {
            // 关闭之前的通知窗口
            self.notificationWindow?.close()
            self.notificationWindow = nil
            
            // 获取菜单栏按钮的位置
            guard let buttonFrame = self.statusBarController?.getStatusBarButtonFrame() else {
                return
            }
            
            // 创建轻量级加载通知
            let popoverWidth: CGFloat = 280
            let popoverHeight: CGFloat = 100
            
            let windowX = buttonFrame.origin.x + (buttonFrame.width - popoverWidth) / 2
            let windowY = buttonFrame.origin.y - popoverHeight - 8
            
            let window = NSPanel(
                contentRect: NSRect(x: windowX, y: windowY, width: popoverWidth, height: popoverHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            window.isFloatingPanel = true
            window.level = .statusBar
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = false
            
            // 显示加载视图
            window.contentView = NSHostingView(rootView: ProcessingNotificationView())
            window.orderFront(nil)
            
            self.notificationWindow = window
        }
    }
    
    private func hideProcessingAlert() {
        // 关闭加载通知窗口
        DispatchQueue.main.async {
            self.notificationWindow?.close()
            self.notificationWindow = nil
        }
    }
    
    private func showResultWindow(text: String) {
        // 保存到历史记录
        HistoryManager.shared.saveHistory(text: text)
        
        // 复制到剪贴板（根据用户设置）
        let autoCopy = UserDefaults.standard.bool(forKey: "AutoCopyToClipboard")
        if autoCopy {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        
        // 关闭/替换之前的通知窗口
        notificationWindow?.close()
        notificationWindow = nil
        
        // 获取菜单栏按钮的位置
        guard let buttonFrame = statusBarController?.getStatusBarButtonFrame() else {
            LogManager.shared.log("无法获取菜单栏按钮位置，使用默认位置", level: .warning)
            showDefaultNotification(text: text, autoCopied: autoCopy)
            return
        }
        
        // 创建轻量级通知窗口，显示在菜单栏图标下方
        let popoverWidth: CGFloat = 280
        let popoverHeight: CGFloat = 130  // 增加高度
        
        // 计算窗口位置（在按钮下方居中）
        let windowX = buttonFrame.origin.x + (buttonFrame.width - popoverWidth) / 2
        let windowY = buttonFrame.origin.y - popoverHeight - 8  // 按钮下方，留 8px 间距
        
        // 使用自定义的可激活 Panel，支持键盘输入
        let window = KeyablePanel(
            contentRect: NSRect(x: windowX, y: windowY, width: popoverWidth, height: popoverHeight),
            styleMask: [.borderless],  // 移除 nonactivatingPanel
            backing: .buffered,
            defer: false
        )
        
        // 设置为浮动面板
        window.isFloatingPanel = true
        window.level = .statusBar  // 使用 statusBar 级别，确保显示在菜单栏下方
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        // 允许窗口激活以支持键盘操作
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false  // 点击时立即成为 key window
        
        // 使用轻量级通知视图
        window.contentView = NSHostingView(rootView: NotificationPopoverView(text: text, window: window, autoCopied: autoCopy))
        
        // 显示窗口但不激活
        window.orderFront(nil)
        
        // 持有窗口引用，防止被释放
        self.notificationWindow = window
        
        LogManager.shared.log("通知气泡已显示在菜单栏下方", level: .success)
        
        // 5秒后自动关闭
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak window] in
            window?.close()
            if self?.notificationWindow === window {
                self?.notificationWindow = nil
            }
        }
    }
    
    // 备用方案：如果无法获取菜单栏位置，显示在屏幕右上角
    private func showDefaultNotification(text: String, autoCopied: Bool) {
        // 关闭之前的通知窗口（如果有）
        notificationWindow?.close()
        notificationWindow = nil
        
        guard let screen = NSScreen.main else { return }
        
        let popoverWidth: CGFloat = 280
        let popoverHeight: CGFloat = 130  // 增加高度
        let margin: CGFloat = 20
        
        let windowX = screen.frame.width - popoverWidth - margin
        let windowY = screen.frame.height - popoverHeight - margin
        
        let window = KeyablePanel(
            contentRect: NSRect(x: windowX, y: windowY, width: popoverWidth, height: popoverHeight),
            styleMask: [.borderless],  // 移除 nonactivatingPanel
            backing: .buffered,
            defer: false
        )
        
        window.isFloatingPanel = true
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        
        window.contentView = NSHostingView(rootView: NotificationPopoverView(text: text, window: window, autoCopied: autoCopied))
        window.orderFront(nil)
        
        self.notificationWindow = window
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak window] in
            window?.close()
            if self?.notificationWindow === window {
                self?.notificationWindow = nil
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    // 显示 API 配置错误提示（带设置引导）
    private func showAPIConfigAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "OCR 识别失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 打开设置窗口
            NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsWindow"), object: nil)
        }
    }
    
    // MARK: - 处理剪贴板图片
    func processClipboardImage(_ image: NSImage) {
        LogManager.shared.log("📋 收到剪贴板图片，尺寸: \(image.size.width)x\(image.size.height)", level: .info)
        
        // 执行 OCR 识别
        performOCR(on: image)
    }
}

// 自定义窗口类，确保正确接收所有事件
class ScreenshotWindow: NSWindow {
    override var canBecomeKey: Bool {
        print("❓ canBecomeKey: 返回 true")
        return true
    }
    
    override var canBecomeMain: Bool {
        print("❓ canBecomeMain: 返回 true")
        return true
    }
    
    override func sendEvent(_ event: NSEvent) {
        print("📨 窗口收到事件: type=\(event.type.rawValue)")
        super.sendEvent(event)
    }
}

// 纯 NSView 实现的截图覆盖层
class ScreenshotOverlayView: NSView {
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private let onComplete: (CGRect?) -> Void
    private var trackingArea: NSTrackingArea?
    
    init(frame: NSRect, onComplete: @escaping (CGRect?) -> Void) {
        self.onComplete = onComplete
        super.init(frame: frame)
        self.wantsLayer = true
        
        // 添加 tracking area 以接收鼠标事件
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [
            .activeAlways,
            .inVisibleRect,
            .mouseEnteredAndExited,
            .mouseMoved
        ]
        
        let area = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        
        addTrackingArea(area)
        trackingArea = area
        
        print("🎯 已设置 TrackingArea")
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }
        
        setupTrackingArea()
    }
    
    override var acceptsFirstResponder: Bool {
        print("❓ acceptsFirstResponder 被调用: 返回 true")
        return true
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        print("🪟 视图已添加到窗口")
        
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self)
            print("   FirstResponder设置完成: \(self.window?.firstResponder === self)")
            print("   视图bounds: \(self.bounds)")
            print("   视图frame: \(self.frame)")
            print("   视图在窗口中: \(self.window != nil)")
        }
        
        // 确认鼠标指针可见
        NSCursor.crosshair.set()
        print("   鼠标指针已设置为十字")
    }
    
    // 测试：点击视图的任何位置
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        print("🎯 hitTest(\(point)) -> \(result === self ? "self" : "other/nil")")
        return result
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        print("🎨 重绘视图区域: \(dirtyRect)")
        
        // 绘制半透明背景（使用更明显的颜色确认视图可见）
        NSColor.black.withAlphaComponent(0.4).setFill()
        bounds.fill()
        
        // 绘制选择框
        if let start = startPoint, let current = currentPoint {
            let rect = NSRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            
            print("🔲 绘制选择框: \(rect)")
            
            // 绘制选择区域（清除背景）
            NSColor.clear.setFill()
            rect.fill()
            
            NSColor.blue.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 3
            path.stroke()
        }
        
        // 绘制提示文字
        let text = "拖动鼠标选择要识别的区域 • 按 ESC 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: (bounds.width - size.width) / 2,
            y: bounds.height - size.height - 50,
            width: size.width + 32,
            height: size.height + 16
        )
        
        // 绘制文字背景
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: textRect, xRadius: 8, yRadius: 8).fill()
        
        // 绘制文字
        (text as NSString).draw(
            at: NSPoint(x: textRect.minX + 16, y: textRect.minY + 8),
            withAttributes: attributes
        )
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = event.locationInWindow
        startPoint = point
        currentPoint = point
        needsDisplay = true
        print("🖱️ [mouseDown] 事件接收成功! 位置: (\(point.x), \(point.y))")
        print("   事件类型: \(event.type.rawValue), clickCount: \(event.clickCount)")
    }
    
    override func mouseDragged(with event: NSEvent) {
        let point = event.locationInWindow
        currentPoint = point
        needsDisplay = true
        
        if let start = startPoint {
            let width = abs(point.x - start.x)
            let height = abs(point.y - start.y)
            print("🖱️ [mouseDragged] 位置: (\(point.x), \(point.y)), 区域: \(width)x\(height)")
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = event.locationInWindow
        print("🖱️ [mouseUp] 鼠标松开于: (\(point.x), \(point.y))")
        
        guard let start = startPoint, let end = currentPoint else {
            print("⚠️  起点或终点为空，取消截图")
            onComplete(nil)
            return
        }
        
        // 计算选择区域（窗口坐标系，原点在左下）
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        
        print("📏 选择区域: 宽=\(rect.width), 高=\(rect.height)")
        
        // 检查区域是否太小
        if rect.width < 5 || rect.height < 5 {
            print("⚠️  选择区域太小，取消截图")
            onComplete(nil)
            startPoint = nil
            currentPoint = nil
            return
        }
        
        // 转换为屏幕坐标系（原点在左上）
        // macOS窗口坐标Y轴向上，屏幕坐标Y轴向下
        guard let screen = NSScreen.main else {
            print("❌ 无法获取主屏幕")
            onComplete(nil)
            return
        }
        
        let screenHeight = screen.frame.height
        let screenRect = CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,  // 翻转Y坐标
            width: rect.width,
            height: rect.height
        )
        
        print("🔄 坐标转换: 窗口坐标(\(rect.origin.x), \(rect.origin.y)) -> 屏幕坐标(\(screenRect.origin.x), \(screenRect.origin.y))")
        print("✅ 有效的选择区域，开始截图")
        
        onComplete(screenRect)
        
        startPoint = nil
        currentPoint = nil
    }
    
    override func keyDown(with event: NSEvent) {
        print("⌨️ 按键事件: keyCode=\(event.keyCode)")
        
        if event.keyCode == 53 { // ESC
            print("🚫 用户按下 ESC，取消截图")
            onComplete(nil)
        } else {
            super.keyDown(with: event)
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        // 更新鼠标指针
        NSCursor.crosshair.set()
    }
    
    override func mouseEntered(with event: NSEvent) {
        print("👋 鼠标进入覆盖区域")
        NSCursor.crosshair.set()
    }
    
    override func mouseExited(with event: NSEvent) {
        print("👋 鼠标离开覆盖区域")
    }
    
    // 确保视图可以成为首响应者
    override func becomeFirstResponder() -> Bool {
        print("✅ 视图成为 FirstResponder")
        return true
    }
    
    override func resignFirstResponder() -> Bool {
        print("❌ 视图失去 FirstResponder")
        return true
    }
}

// 轻量级通知气泡视图（显示在菜单栏下方）
struct NotificationPopoverView: View {
    let text: String
    weak var window: NSWindow?
    let autoCopied: Bool
    @State private var isHovered = false
    @State private var fullTextWindow: NSWindow?  // 持有全文窗口引用
    
    var body: some View {
        VStack(spacing: 8) {
            // 顶部状态
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
                
                Text(autoCopied ? "已复制到剪贴板" : "识别完成")
                    .font(.system(size: 12, weight: .medium))
                
                Spacer()
                
                // 关闭按钮
                Button(action: {
                    window?.close()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0.6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            
            // 文本预览（使用可选择的文本视图）
            SelectableTextView(text: text)
                .frame(height: 50)
                .padding(.horizontal, 12)
            
            Divider()
                .padding(.horizontal, 8)
            
            // 操作按钮
            HStack(spacing: 8) {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("复制")
                    }
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: {
                    // 显示完整内容窗口
                    showFullTextWindow()
                    window?.close()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.alignleft")
                        Text("查看全文")
                    }
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 280, height: 130)  // 增加高度以适配滚动区域
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func showFullTextWindow() {
        // 关闭之前的全文窗口
        fullTextWindow?.close()
        
        // 使用 NSPanel 避免影响应用生命周期
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "识别结果"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 400, height: 300)  // 设置最小尺寸
        
        // 创建包装器来持有窗口引用
        let wrapper = FullTextViewWrapper(text: text, window: panel)
        panel.contentView = NSHostingView(rootView: wrapper)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        
        // 注意：这里不能持有引用，因为 View 是值类型
        // 窗口会由系统管理，关闭时自动释放
    }
}

// 加载通知视图（在识别过程中显示）
struct ProcessingNotificationView: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 16, height: 16)
                
                Text("正在识别...")
                    .font(.system(size: 12, weight: .medium))
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            Text("请稍候，OCR 识别中")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            
            Spacer()
        }
        .frame(width: 280, height: 100)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
    }
}

// 未识别到文字的轻量级通知视图
struct NoTextNotificationView: View {
    weak var window: NSWindow?
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                
                Text("未识别到文字")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            Text("图片中未检测到文字内容")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            
            Spacer()
        }
        .frame(width: 280, height: 100)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
    }
}

// 识别错误的轻量级通知视图
struct ErrorNotificationView: View {
    let message: String
    weak var window: NSWindow?
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                
                Text("识别失败")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            Text(simplifyErrorMessage(message))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            
            Spacer()
        }
        .frame(width: 280, height: 120)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
    }
    
    // 简化错误信息，只显示关键部分
    private func simplifyErrorMessage(_ message: String) -> String {
        // 如果是 API 返回的错误，提取 message 字段
        if message.contains("API 返回错误") {
            // 尝试提取 JSON 中的 message
            if let range = message.range(of: #""message":"#) {
                let start = range.upperBound
                if let endRange = message[start...].range(of: #""#) {
                    let errorMsg = String(message[start..<endRange.lowerBound])
                    // 返回简化的描述
                    if errorMsg.contains("OCR仅支持") || errorMsg.contains("文件大小限制") {
                        return "图片格式或大小不符合要求"
                    }
                    return errorMsg
                }
            }
        }
        
        // 其他常见错误的简化
        if message.contains("400") {
            return "请求参数错误，请检查图片格式"
        }
        if message.contains("401") || message.contains("403") {
            return "API 密钥无效或无权限"
        }
        if message.contains("429") {
            return "请求过于频繁，请稍后重试"
        }
        if message.contains("500") || message.contains("502") || message.contains("503") {
            return "OCR 服务暂时不可用"
        }
        
        // 如果消息太长，截取前80字符
        if message.count > 80 {
            return String(message.prefix(80)) + "..."
        }
        
        return message
    }
}


// 包装器：持有窗口引用防止提前释放
struct FullTextViewWrapper: View {
    let text: String
    let window: NSWindow
    
    var body: some View {
        FullTextView(text: text)
    }
}

// 完整文本查看窗口
struct FullTextView: View {
    let text: String
    @State private var copied = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack {
                Text("识别结果")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "已复制" : "复制")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 文本内容区域（使用可选择的文本视图）
            SelectableFullTextView(text: text)
                .background(Color(NSColor.textBackgroundColor))
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

// 紧凑的结果显示视图（轻量级）- 保留作为备用
struct CompactResultView: View {
    let text: String
    weak var window: NSWindow?
    @State private var showCopiedHint = false
    @State private var showFullText = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部状态栏
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 18))
                
                Text("已复制到剪贴板")
                    .font(.system(size: 13, weight: .medium))
                
                Spacer()
                
                // 查看完整内容按钮
                Button(action: {
                    showFullText = true
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("查看完整内容")
                
                // 关闭按钮
                Button(action: {
                    window?.close()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 文本预览区域
            VStack(spacing: 8) {
                ScrollView {
                    Text(text)
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .lineLimit(showFullText ? nil : nil)  // 移除行数限制，让滚动生效
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(maxHeight: showFullText ? .infinity : 60)  // 约2.5行高度（每行约24px）
                
                // 操作按钮
                HStack(spacing: 12) {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        showCopiedHint = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopiedHint = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: showCopiedHint ? "checkmark" : "doc.on.doc")
                            Text(showCopiedHint ? "已复制" : "再次复制")
                        }
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        window?.close()
                    }) {
                        Text("关闭")
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 320, height: showFullText ? 400 : 170)  // 调整总高度以适配新的文本区域高度
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// 原有的完整结果视图（保留用于扩展模式）
struct ResultView: View {
    let text: String
    @State private var copied = false
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("识别结果")
                    .font(.headline)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                }) {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            }
            .padding()
            
            ScrollView {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}

// 加载视图
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在识别...")
                .font(.headline)
            Text("请稍候")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(32)
        .frame(width: 300, height: 100)
    }
}

// MARK: - 可选择文本视图（使用 NSTextView 实现真正的文本选择）

// 自定义 NSTextView，支持在 Panel 中接收键盘事件
class SelectableNSTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        // 确保窗口可以接收键盘事件
        self.window?.makeKey()
        return super.becomeFirstResponder()
    }
    
    // 处理 Cmd+C 复制
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "c":
                if selectedRange().length > 0 {
                    copy(nil)
                    return true
                }
            case "a":
                selectAll(nil)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    // 确保可以显示右键菜单
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        
        if selectedRange().length > 0 {
            let copyItem = NSMenuItem(title: "复制", action: #selector(copy(_:)), keyEquivalent: "c")
            copyItem.keyEquivalentModifierMask = .command
            menu.addItem(copyItem)
        }
        
        let selectAllItem = NSMenuItem(title: "全选", action: #selector(selectAll(_:)), keyEquivalent: "a")
        selectAllItem.keyEquivalentModifierMask = .command
        menu.addItem(selectAllItem)
        
        return menu
    }
}

struct SelectableTextView: NSViewRepresentable {
    let text: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        let textView = SelectableNSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.allowsUndo = false
        
        // 设置字体和颜色
        textView.font = NSFont.systemFont(ofSize: 11)
        textView.textColor = NSColor.secondaryLabelColor
        
        // 设置段落样式（行间距）
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
        textView.typingAttributes = attributes
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        
        scrollView.documentView = textView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}

// MARK: - 全文窗口的可选择文本视图（更大的字体和内边距）
struct SelectableFullTextView: NSViewRepresentable {
    let text: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor
        
        let textView = SelectableNSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.allowsUndo = false
        
        // 设置字体和颜色（更大的字体用于全文窗口）
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor.labelColor
        
        // 设置段落样式（行间距）
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        textView.typingAttributes = attributes
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        
        scrollView.documentView = textView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}
