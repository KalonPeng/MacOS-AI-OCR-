import Foundation
import AppKit
import Carbon

// 快捷键管理器
class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()
    
    @Published var currentHotkey: Hotkey
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "GlobalHotkeyEnabled")
            UserDefaults.standard.synchronize()
            
            if isEnabled {
                if let callback = callback {
                    register(callback: callback)
                }
            } else {
                unregister()
            }
            
            // 通知菜单更新
            NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        }
    }
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var callback: (() -> Void)?
    
    init() {
        // 从 UserDefaults 加载快捷键设置
        if let data = UserDefaults.standard.data(forKey: "GlobalHotkey"),
           let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data) {
            self.currentHotkey = hotkey
        } else {
            // 默认快捷键: Command+Shift+R
            self.currentHotkey = Hotkey(
                keyCode: 15, // R
                modifiers: [.command, .shift],
                displayString: "⌘⇧R"
            )
        }
        
        // 加载快捷键启用状态（默认启用）
        self.isEnabled = UserDefaults.standard.object(forKey: "GlobalHotkeyEnabled") as? Bool ?? true
    }
    
    // 注册全局快捷键
    func register(callback: @escaping () -> Void) {
        self.callback = callback
        
        // 如果未启用,不注册
        guard isEnabled else {
            print("⚠️ 全局快捷键未启用")
            return
        }
        
        // 先移除旧的监听
        unregister()
        
        // 检查辅助功能权限
        let trusted = AXIsProcessTrusted()
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let bundlePath = Bundle.main.bundleURL.path
        
        print("🔍 全局快捷键注册检查:")
        print("   Bundle ID: \(bundleID)")
        print("   Bundle Path: \(bundlePath)")
        print("   辅助功能权限: \(trusted ? "✅ 已授权" : "❌ 未授权")")
        
        if !trusted {
            print("⚠️ 需要辅助功能权限才能使用全局快捷键")
            print("💡 请在 系统设置 > 隐私与安全性 > 辅助功能 中授权此应用")
            
            // 尝试请求权限
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options)
            return
        }
        
        // 使用 CGEvent.tapCreate 监听全局快捷键
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                
                // 检查是否匹配当前快捷键
                if type == .keyDown {
                    let flags = event.flags
                    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                    
                    if manager.matchesHotkey(flags: flags, keyCode: keyCode) {
                        DispatchQueue.main.async {
                            manager.callback?()
                        }
                        // 返回 nil 阻止事件继续传播
                        return nil
                    }
                }
                
                return Unmanaged.passRetained(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("❌ 无法创建 Event Tap - 可能需要辅助功能权限")
            return
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        
        print("✅ 全局快捷键已注册: \(currentHotkey.displayString)")
    }
    
    // 移除快捷键监听
    func unregister() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        
        print("🔕 全局快捷键已注销")
    }
    
    // 检查是否匹配快捷键
    private func matchesHotkey(flags: CGEventFlags, keyCode: Int) -> Bool {
        // 检查按键码是否匹配
        guard keyCode == currentHotkey.keyCode else {
            return false
        }
        
        // 检查修饰键
        let hasCommand = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)
        let hasOption = flags.contains(.maskAlternate)
        let hasControl = flags.contains(.maskControl)
        
        let needsCommand = currentHotkey.modifiers.contains(.command)
        let needsShift = currentHotkey.modifiers.contains(.shift)
        let needsOption = currentHotkey.modifiers.contains(.option)
        let needsControl = currentHotkey.modifiers.contains(.control)
        
        return hasCommand == needsCommand &&
               hasShift == needsShift &&
               hasOption == needsOption &&
               hasControl == needsControl
    }
    
    // 更新快捷键
    func updateHotkey(_ hotkey: Hotkey) {
        self.currentHotkey = hotkey
        
        // 保存到 UserDefaults
        if let data = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(data, forKey: "GlobalHotkey")
            UserDefaults.standard.synchronize()
        }
        
        // 重新注册
        if let callback = callback, isEnabled {
            register(callback: callback)
        }
        
        // 通知菜单更新
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }
    
    // 检测快捷键冲突
    static func detectConflicts(for hotkey: Hotkey) -> [String] {
        var conflicts: [String] = []
        
        // 检查常见应用的快捷键
        let commonShortcuts: [(String, Hotkey)] = [
            ("系统截图", Hotkey(keyCode: 21, modifiers: [.command, .shift], displayString: "⌘⇧4")),
            ("系统截图(全屏)", Hotkey(keyCode: 19, modifiers: [.command, .shift], displayString: "⌘⇧3")),
            ("Spotlight", Hotkey(keyCode: 49, modifiers: [.command], displayString: "⌘Space")),
            ("刷新页面", Hotkey(keyCode: 15, modifiers: [.command], displayString: "⌘R")),
            ("强制刷新", Hotkey(keyCode: 15, modifiers: [.command, .shift], displayString: "⌘⇧R")),
            ("录屏", Hotkey(keyCode: 21, modifiers: [.command, .shift, .control], displayString: "⌘⇧⌃4")),
        ]
        
        for (name, shortcut) in commonShortcuts {
            if hotkey.keyCode == shortcut.keyCode && 
               hotkey.modifiers == shortcut.modifiers {
                conflicts.append(name)
            }
        }
        
        return conflicts
    }
}

// 快捷键数据结构
struct Hotkey: Codable, Equatable {
    let keyCode: Int
    let modifiers: Set<ModifierKey>
    let displayString: String
    
    enum CodingKeys: String, CodingKey {
        case keyCode, modifiers, displayString
    }
    
    init(keyCode: Int, modifiers: Set<ModifierKey>, displayString: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayString = displayString
    }
    
    // 自定义编码
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(Array(modifiers.map { $0.rawValue }), forKey: .modifiers)
        try container.encode(displayString, forKey: .displayString)
    }
    
    // 自定义解码
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(Int.self, forKey: .keyCode)
        let modifierRawValues = try container.decode([String].self, forKey: .modifiers)
        modifiers = Set(modifierRawValues.compactMap { ModifierKey(rawValue: $0) })
        displayString = try container.decode(String.self, forKey: .displayString)
    }
}

// 修饰键枚举
enum ModifierKey: String, Codable, CaseIterable, Hashable {
    case command = "command"
    case shift = "shift"
    case option = "option"
    case control = "control"
    
    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .shift: return "⇧"
        case .option: return "⌥"
        case .control: return "⌃"
        }
    }
    
    var displayName: String {
        switch self {
        case .command: return "Command"
        case .shift: return "Shift"
        case .option: return "Option"
        case .control: return "Control"
        }
    }
}

// 键码到字符的映射
extension Int {
    var keyCharacter: String {
        let keyMap: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3",
            21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]",
            31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 49: "Space",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            36: "↩︎", 48: "⇥", 51: "⌫", 53: "⎋", 71: "⎋", 76: "↩︎"
        ]
        return keyMap[self] ?? "?"
    }
}

// 通知名称扩展
extension Notification.Name {
    static let hotkeyDidChange = Notification.Name("hotkeyDidChange")
}
