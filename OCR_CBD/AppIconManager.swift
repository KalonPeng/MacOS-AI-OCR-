import Foundation
import AppKit

class AppIconManager: ObservableObject {
    static let shared = AppIconManager()
    
    @Published var currentAppIcon: String {
        didSet {
            saveCurrentIcon()
            updateDockIcon()
        }
    }
    
    private init() {
        // 从 UserDefaults 加载保存的图标
        self.currentAppIcon = UserDefaults.standard.string(forKey: "AppIcon") ?? "default"
        // 初始化时更新一次图标
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateDockIcon()
        }
    }
    
    private func saveCurrentIcon() {
        UserDefaults.standard.set(currentAppIcon, forKey: "AppIcon")
    }
    
    // 更新 Dock 图标
    private func updateDockIcon() {
        if currentAppIcon == "custom", let customImage = loadCustomIcon() {
            NSApplication.shared.applicationIconImage = customImage
            LogManager.shared.log("✅ 已应用自定义应用图标", level: .success)
        } else if currentAppIcon != "default" {
            // 使用系统图标
            if let systemImage = createSystemIconImage(systemName: currentAppIcon) {
                NSApplication.shared.applicationIconImage = systemImage
                LogManager.shared.log("✅ 已应用系统图标: \(currentAppIcon)", level: .success)
            }
        } else {
            // 使用默认图标
            if let defaultImage = createDefaultIcon() {
                NSApplication.shared.applicationIconImage = defaultImage
                LogManager.shared.log("✅ 已应用默认图标", level: .success)
            }
        }
    }
    
    // 创建默认图标（使用 SF Symbol）
    private func createDefaultIcon() -> NSImage? {
        return createSystemIconImage(systemName: "doc.text.viewfinder")
    }
    
    // 从系统符号创建图标
    private func createSystemIconImage(systemName: String) -> NSImage? {
        let size: CGFloat = 1024
        let image = NSImage(size: NSSize(width: size, height: size))
        
        image.lockFocus()
        
        // 绘制渐变背景
        let gradient = NSGradient(colors: [
            NSColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1.0),
            NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
        ])
        gradient?.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: 135)
        
        // 绘制圆角矩形遮罩
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let cornerRadius = size * 0.225 // macOS 应用图标圆角比例
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()
        
        // 绘制符号
        if let symbolImage = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) {
            let symbolSize = size * 0.55
            let symbolRect = NSRect(
                x: (size - symbolSize) / 2,
                y: (size - symbolSize) / 2,
                width: symbolSize,
                height: symbolSize
            )
            
            // 设置白色
            NSColor.white.setFill()
            
            // 绘制符号
            let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
            let configuredImage = symbolImage.withSymbolConfiguration(config)
            configuredImage?.draw(in: symbolRect)
        }
        
        image.unlockFocus()
        
        return image
    }
    
    // 设置自定义应用图标
    func setCustomAppIcon(from url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url) else {
            return false
        }
        
        // 保存到应用支持目录
        guard let destPath = getCustomAppIconPath() else {
            return false
        }
        
        // 创建目录
        let destURL = URL(fileURLWithPath: destPath)
        try? FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        // 调整大小到 1024x1024
        let resizedImage = resizeImage(image, to: NSSize(width: 1024, height: 1024))
        
        // 保存图片（转为 PNG）
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }
        
        do {
            try pngData.write(to: destURL)
            currentAppIcon = "custom"
            LogManager.shared.log("自定义应用图标已保存: \(destPath)", level: .success)
            return true
        } catch {
            LogManager.shared.log("保存自定义应用图标失败: \(error.localizedDescription)", level: .error)
            return false
        }
    }
    
    // 加载自定义图标
    private func loadCustomIcon() -> NSImage? {
        guard let path = getCustomAppIconPath(),
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return NSImage(contentsOfFile: path)
    }
    
    // 获取自定义应用图标路径
    private func getCustomAppIconPath() -> String? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let appFolder = appSupport.appendingPathComponent("OCR_CBD")
        return appFolder.appendingPathComponent("custom_app_icon.png").path
    }
    
    // 调整图片大小
    private func resizeImage(_ image: NSImage, to newSize: NSSize) -> NSImage {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        
        newImage.unlockFocus()
        return newImage
    }
    
    // 重置为默认图标
    func resetToDefault() {
        currentAppIcon = "default"
    }
    
    // 预设的系统图标选项
    static let presetIcons: [(name: String, systemName: String)] = [
        ("默认", "default"),
        ("文档扫描", "doc.text.viewfinder"),
        ("文字识别", "textformat.abc"),
        ("相机", "camera.fill"),
        ("眼睛", "eye.fill"),
        ("扫描", "qrcode.viewfinder"),
        ("魔法", "sparkles"),
        ("文档", "doc.text.fill"),
        ("放大镜", "magnifyingglass"),
        ("星星", "star.fill")
    ]
}
