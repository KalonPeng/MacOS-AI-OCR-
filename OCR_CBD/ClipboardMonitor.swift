import Foundation
import AppKit

// MARK: - 剪贴板监听管理器
class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "ClipboardMonitorEnabled")
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var lastImageHash: String? = nil
    private var ocrCallback: ((NSImage) -> Void)?
    
    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "ClipboardMonitorEnabled")
        self.lastChangeCount = NSPasteboard.general.changeCount
        
        LogManager.shared.log("剪贴板监听器初始化，启用状态: \(isEnabled)", level: .info)
        
        if isEnabled {
            startMonitoring()
        }
    }
    
    // MARK: - 设置 OCR 回调
    func setOCRCallback(_ callback: @escaping (NSImage) -> Void) {
        self.ocrCallback = callback
        LogManager.shared.log("已设置剪贴板 OCR 回调", level: .info)
    }
    
    // MARK: - 开始监听
    private func startMonitoring() {
        guard timer == nil else { return }
        
        // 每 0.5 秒检查一次剪贴板
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        
        // 初始化时获取当前的 changeCount
        lastChangeCount = NSPasteboard.general.changeCount
        
        LogManager.shared.log("✅ 剪贴板监听已启动", level: .info)
    }
    
    // MARK: - 停止监听
    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        LogManager.shared.log("⏸️ 剪贴板监听已停止", level: .info)
    }
    
    // MARK: - 检查剪贴板
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        
        // 检查 changeCount 是否变化
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }
        
        lastChangeCount = pasteboard.changeCount
        
        // 检查是否包含图片
        guard let image = getImageFromPasteboard(pasteboard) else {
            return
        }
        
        // 计算图片哈希，避免重复识别同一张图片
        let imageHash = calculateImageHash(image)
        
        // 如果是同一张图片，跳过
        if imageHash == lastImageHash {
            LogManager.shared.log("⚠️ 检测到相同图片，跳过识别", level: .info)
            return
        }
        
        lastImageHash = imageHash
        
        LogManager.shared.log("📋 检测到新图片，开始 OCR 识别", level: .info)
        
        // 执行 OCR 识别
        DispatchQueue.main.async { [weak self] in
            self?.ocrCallback?(image)
        }
    }
    
    // MARK: - 从剪贴板获取图片
    private func getImageFromPasteboard(_ pasteboard: NSPasteboard) -> NSImage? {
        // 优先尝试 PNG 格式
        if let imageData = pasteboard.data(forType: .png),
           let image = NSImage(data: imageData) {
            return image
        }
        
        // 尝试 TIFF 格式
        if let imageData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: imageData) {
            return image
        }
        
        // 尝试通用图片类型
        if pasteboard.canReadItem(withDataConformingToTypes: NSImage.imageTypes),
           let image = NSImage(pasteboard: pasteboard) {
            return image
        }
        
        return nil
    }
    
    // MARK: - 计算图片哈希（用于去重）
    private func calculateImageHash(_ image: NSImage) -> String {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return UUID().uuidString
        }
        
        // 使用图片数据的哈希值
        var hash = 0
        for byte in pngData.prefix(1024) {  // 只取前 1KB 数据计算哈希
            hash = hash &* 31 &+ Int(byte)
        }
        
        return "\(hash)_\(pngData.count)"
    }
    
    // MARK: - 手动触发检查（用于测试）
    func manualCheck() {
        checkClipboard()
    }
}
