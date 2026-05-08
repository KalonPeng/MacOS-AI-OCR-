import Foundation
import AppKit

class StatusBarIconManager: ObservableObject {
    static let shared = StatusBarIconManager()
    
    @Published var currentIcon: StatusBarIcon {
        didSet {
            saveCurrentIcon()
            NotificationCenter.default.post(name: .statusBarIconDidChange, object: nil)
        }
    }
    
    private init() {
        // 从 UserDefaults 加载保存的图标
        if let savedIconName = UserDefaults.standard.string(forKey: "StatusBarIcon"),
           let icon = StatusBarIcon.allIcons.first(where: { $0.systemName == savedIconName }) {
            self.currentIcon = icon
        } else {
            self.currentIcon = .default
        }
    }
    
    private func saveCurrentIcon() {
        UserDefaults.standard.set(currentIcon.systemName, forKey: "StatusBarIcon")
    }
    
    // 获取状态栏图标
    func getStatusBarImage() -> NSImage? {
        // 如果是自定义图片，尝试从文件加载
        if currentIcon.isCustom, let customPath = getCustomIconPath(), FileManager.default.fileExists(atPath: customPath) {
            return NSImage(contentsOfFile: customPath)
        }
        
        // 使用系统图标
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        return NSImage(systemSymbolName: currentIcon.systemName, accessibilityDescription: "OCR")?
            .withSymbolConfiguration(config)
    }
    
    // 设置自定义图标
    func setCustomIcon(from url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url) else {
            return false
        }
        
        // 保存到应用支持目录
        guard let destPath = getCustomIconPath() else {
            return false
        }
        
        // 创建目录
        let destURL = URL(fileURLWithPath: destPath)
        try? FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        // 保存图片（转为 PNG）
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }
        
        do {
            try pngData.write(to: destURL)
            currentIcon = .custom
            LogManager.shared.log("自定义图标已保存: \(destPath)", level: .success)
            return true
        } catch {
            LogManager.shared.log("保存自定义图标失败: \(error.localizedDescription)", level: .error)
            return false
        }
    }
    
    // 获取自定义图标路径
    private func getCustomIconPath() -> String? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let appFolder = appSupport.appendingPathComponent("OCR_CBD")
        return appFolder.appendingPathComponent("custom_icon.png").path
    }
}

// 预定义的图标
struct StatusBarIcon: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let systemName: String
    let isCustom: Bool
    
    static let `default` = StatusBarIcon(name: "文档扫描", systemName: "doc.text.viewfinder", isCustom: false)
    static let text = StatusBarIcon(name: "文字识别", systemName: "textformat.abc", isCustom: false)
    static let camera = StatusBarIcon(name: "相机", systemName: "camera.viewfinder", isCustom: false)
    static let eye = StatusBarIcon(name: "眼睛", systemName: "eye.fill", isCustom: false)
    static let scan = StatusBarIcon(name: "扫描", systemName: "qrcode.viewfinder", isCustom: false)
    static let rectangle = StatusBarIcon(name: "矩形选择", systemName: "rectangle.dashed", isCustom: false)
    static let sparkle = StatusBarIcon(name: "魔法", systemName: "sparkles", isCustom: false)
    static let document = StatusBarIcon(name: "文档", systemName: "doc.text.fill", isCustom: false)
    static let magnifier = StatusBarIcon(name: "放大镜", systemName: "text.magnifyingglass", isCustom: false)
    static let viewfinder = StatusBarIcon(name: "取景框", systemName: "viewfinder.circle.fill", isCustom: false)
    static let scissors = StatusBarIcon(name: "剪刀", systemName: "scissors", isCustom: false)
    static let crop = StatusBarIcon(name: "裁剪", systemName: "crop", isCustom: false)
    static let custom = StatusBarIcon(name: "自定义", systemName: "custom", isCustom: true)
    
    static let allIcons: [StatusBarIcon] = [
        .default, .text, .camera, .eye, .scan, .rectangle, 
        .sparkle, .document, .magnifier, .viewfinder, .scissors, .crop
    ]
    
    static func == (lhs: StatusBarIcon, rhs: StatusBarIcon) -> Bool {
        return lhs.systemName == rhs.systemName
    }
}

// 通知名称
extension Notification.Name {
    static let statusBarIconDidChange = Notification.Name("statusBarIconDidChange")
}
