import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var config = OCRConfig.load()
    @State private var showPassword = false
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var launchAtLogin = LaunchAtLoginHelper.isEnabled()
    @State private var autoCopyToClipboard: Bool = {
        // 默认开启自动复制
        if !UserDefaults.standard.bool(forKey: "AutoCopySettingInitialized") {
            UserDefaults.standard.set(true, forKey: "AutoCopyToClipboard")
            UserDefaults.standard.set(true, forKey: "AutoCopySettingInitialized")
            return true
        }
        return UserDefaults.standard.bool(forKey: "AutoCopyToClipboard")
    }()
    
    @StateObject private var hotkeyManager = HotkeyManager.shared
    @StateObject private var clipboardMonitor = ClipboardMonitor.shared
    @StateObject private var iconManager = StatusBarIconManager.shared
    @State private var isRecordingHotkey = false
    @State private var conflicts: [String] = []
    @State private var showUsageInstructions = false
    @State private var hasAccessibilityPermission = false
    @State private var showIconPicker = false
    
    // 统一的卡片背景色
    private var cardBackgroundColor: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.5)
    }
    
    var body: some View {
        TabView {
            // 通用设置
            ScrollView {
                VStack(spacing: 24) {
                    // 通用设置组
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "gear")
                                .font(.title2)
                                .foregroundColor(.blue)
                            Text("通用设置")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        
                        VStack(spacing: 10) {
                            SettingRow(
                                icon: "power",
                                title: "开机启动",
                                description: "登录时自动启动应用"
                            ) {
                                Toggle("", isOn: $launchAtLogin)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .labelsHidden()
                                    .onChange(of: launchAtLogin) { newValue in
                                        LaunchAtLoginHelper.setEnabled(newValue)
                                    }
                            }
                            
                            SettingRow(
                                icon: "doc.on.clipboard",
                                title: "自动复制",
                                description: "识别后自动复制到剪切板"
                            ) {
                                Toggle("", isOn: $autoCopyToClipboard)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .labelsHidden()
                                    .onChange(of: autoCopyToClipboard) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "AutoCopyToClipboard")
                                        UserDefaults.standard.synchronize()
                                    }
                            }
                            
                            SettingRow(
                                icon: "eye.circle",
                                title: "监听剪贴板图片",
                                description: "自动识别复制/截图到剪贴板的新图片"
                            ) {
                                Toggle("", isOn: $clipboardMonitor.isEnabled)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .labelsHidden()
                            }
                            
                            SettingRow(
                                icon: "photo",
                                title: "状态栏图标",
                                description: "自定义菜单栏图标样式"
                            ) {
                                Button(action: {
                                    showIconPicker = true
                                }) {
                                    HStack(spacing: 6) {
                                        if let image = iconManager.getStatusBarImage() {
                                            Image(nsImage: image)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 16, height: 16)
                                        }
                                        Text(iconManager.currentIcon.name)
                                            .font(.system(size: 12))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .brightness(0.05)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                    }
                    
                    // 全局快捷键设置组
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "command")
                                .font(.title2)
                                .foregroundColor(.purple)
                            Text("全局快捷键")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            // 全局快捷键开关
                            Toggle("", isOn: $hotkeyManager.isEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }
                        
                        // 仅在启用时显示配置项
                        if hotkeyManager.isEnabled {
                            VStack(spacing: 10) {
                                // 辅助功能权限检查
                                if !hasAccessibilityPermission {
                                    VStack(spacing: 8) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "exclamationmark.shield.fill")
                                                .foregroundColor(.red)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("需要辅助功能权限")
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(.red)
                                                Text("授权后需要重启应用才能生效")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                        }
                                        
                                        HStack(spacing: 8) {
                                            Button("前往设置授权") {
                                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                                    NSWorkspace.shared.open(url)
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                            
                                            Button("刷新状态") {
                                                checkAccessibilityPermission()
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            
                                            Button("重启应用") {
                                                restartApp()
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            
                                            Spacer()
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                
                                // 快捷键配置
                                HStack {
                                    Image(systemName: "scissors")
                                        .foregroundColor(.purple)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("截图识别")
                                            .font(.body)
                                            .fontWeight(.medium)
                                        Text("点击右侧按钮自定义快捷键")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    // 快捷键录制按钮
                                    Button(action: {
                                        isRecordingHotkey = true
                                    }) {
                                        HotkeyDisplayView(hotkey: hotkeyManager.currentHotkey, isRecording: isRecordingHotkey)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                // 冲突警告
                                if !conflicts.isEmpty {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("快捷键冲突警告")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.orange)
                                            Text("与以下功能冲突: \(conflicts.joined(separator: "、"))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(18)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .brightness(0.05)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                            )
                            .onAppear {
                                checkAccessibilityPermission()
                            }
                        }
                    }
                    .sheet(isPresented: $isRecordingHotkey) {
                        HotkeyRecorderView(isPresented: $isRecordingHotkey) { newHotkey in
                            hotkeyManager.updateHotkey(newHotkey)
                            conflicts = HotkeyManager.detectConflicts(for: newHotkey)
                        }
                    }
                    .onAppear {
                        conflicts = HotkeyManager.detectConflicts(for: hotkeyManager.currentHotkey)
                    }
                    
                    Spacer()
                }
                .padding(24)
            }
            .tabItem {
                Label("通用", systemImage: "gear")
            }
            
            // OCR 设置
            ScrollView {
                VStack(spacing: 24) {
                    // API 配置
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "network")
                                .font(.title2)
                                .foregroundColor(.green)
                            Text("API 配置")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        
                        VStack(spacing: 16) {
                            // Base URL
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Base URL", systemImage: "link")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                TextField("API 服务地址", text: $config.baseURL)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                            
                            // API Key
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("API Key", systemImage: "key")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Button(action: { showPassword.toggle() }) {
                                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                if showPassword {
                                    TextField("请输入智谱 AI API Key", text: $config.apiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                } else {
                                    SecureField("请输入智谱 AI API Key", text: $config.apiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                            
                            // Model
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Model", systemImage: "cpu")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                TextField("deepseek-chat", text: $config.model)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .brightness(0.05)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                    }
                    
                    // Prompt 配置
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "text.bubble")
                                .font(.title2)
                                .foregroundColor(.orange)
                            Text("Prompt 配置")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        
                        VStack(spacing: 16) {
                            // System Message
                            VStack(alignment: .leading, spacing: 8) {
                                Label("System Message", systemImage: "gearshape.2")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Text("定义 AI 角色和行为")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextEditor(text: $config.systemMessage)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 100)
                                    .padding(4)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            
                            // User Message
                            VStack(alignment: .leading, spacing: 8) {
                                Label("User Message", systemImage: "person.bubble")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Text("发送给 API 的 OCR 指令")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("请识别这张图片中的文字", text: $config.userMessage)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .brightness(0.05)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                    }
                    
                    // 操作按钮和状态
                    VStack(spacing: 12) {
                        if let result = testResult {
                            HStack {
                                Image(systemName: result.contains("✅") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result.contains("✅") ? .green : .red)
                                Text(result)
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                (result.contains("✅") ? Color.green : Color.red)
                                    .opacity(0.1)
                            )
                            .cornerRadius(8)
                        }
                        
                        HStack(spacing: 12) {
                            Button(action: testConnection) {
                                HStack {
                                    if isTesting {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .frame(width: 16, height: 16)
                                    } else {
                                        Image(systemName: "network")
                                    }
                                    Text("测试连接")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isTesting || config.apiKey.isEmpty)
                            
            Button(action: {
                config.save()
                testResult = "✅ 配置保存成功"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    testResult = nil
                }
            }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("保存配置")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    Spacer()
                }
                .padding(24)
            }
            .tabItem {
                Label("OCR 配置", systemImage: "doc.text.viewfinder")
            }
            
            // 关于
            ScrollView {
                VStack(spacing: 16) {
                    Spacer()
                        .frame(height: 10)
                    
                    // 应用图标和基本信息（居中）
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        VStack(spacing: 4) {
                            Text("OCR 截图转文字工具")
                                .font(.title3)
                                .fontWeight(.bold)
                            
                            // 动态获取版本号
                            Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // 使用说明按钮（居中，中间层级）
                    Button(action: {
                        showUsageInstructions = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "book")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("查看使用说明")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showUsageInstructions) {
                        UsageInstructionsWindow(isPresented: $showUsageInstructions)
                    }
                    
                    // 功能介绍卡片（标题左对齐）
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundColor(.blue)
                            
                            Text("核心特性")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        
                        VStack(spacing: 10) {
                            FeatureRow(icon: "scissors", color: .blue, title: "快捷截图识别", description: "自定义全局快捷键，瞬间截图并识别文字")
                            FeatureRow(icon: "eye.circle", color: .purple, title: "智能剪贴板监听", description: "自动识别复制到剪贴板的新图片，无需手动操作")
                            FeatureRow(icon: "cpu.fill", color: .green, title: "高精度 OCR", description: "基于智谱 AI 技术，准确识别打印体、手写体")
                            FeatureRow(icon: "clock.arrow.circlepath", color: .orange, title: "识别历史", description: "自动保存所有识别记录，支持搜索和快速复制")
                            FeatureRow(icon: "doc.on.clipboard.fill", color: .cyan, title: "一键复制", description: "识别完成后自动复制到剪贴板，即识即用")
                            FeatureRow(icon: "paintpalette", color: .pink, title: "个性化定制", description: "自定义状态栏图标，打造专属的 OCR 工具")
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .brightness(0.05)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                    
                    Spacer()
                        .frame(height: 10)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .tabItem {
                Label("关于", systemImage: "info.circle")
            }
        }
        .frame(width: 650, height: 550)
        .sheet(isPresented: $showIconPicker) {
            IconPickerView(iconManager: iconManager)
        }
    }
    
    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        
        // 调试信息
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let bundlePath = Bundle.main.bundleURL.path
        print("🔍 检查辅助功能权限:")
        print("   Bundle ID: \(bundleID)")
        print("   Bundle Path: \(bundlePath)")
        print("   权限状态: \(hasAccessibilityPermission ? "✅ 已授权" : "❌ 未授权")")
    }
    
    func restartApp() {
        // 获取应用的实际 bundle 路径
        let bundlePath = Bundle.main.bundleURL.path
        print("🔄 重启应用: \(bundlePath)")
        
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [bundlePath]
        task.launch()
        
        // 延迟一点再退出，确保新进程启动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(self)
        }
    }
    
    func testConnection() {
        isTesting = true
        testResult = nil
        
        // 验证配置
        guard !config.apiKey.isEmpty else {
            testResult = "❌ 请先填写 API Key"
            isTesting = false
            return
        }
        
        guard let url = URL(string: config.baseURL) else {
            testResult = "❌ API 地址格式错误"
            isTesting = false
            return
        }
        
        // 创建一个1x1的纯白色测试图片
        let testImage = NSImage(size: NSSize(width: 100, height: 100))
        testImage.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 100, height: 100)).fill()
        testImage.unlockFocus()
        
        guard let base64Image = testImage.toBase64() else {
            testResult = "❌ 测试图片生成失败"
            isTesting = false
            return
        }
        
        // 构建OCR测试请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        
        let body: [String: Any] = [
            "model": config.model,
            "file": "data:image/png;base64,\(base64Image)",
            "return_crop_images": false,
            "need_layout_visualization": false
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isTesting = false
                
                if let error = error {
                    testResult = "❌ 网络连接失败: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    testResult = "❌ 服务器响应异常"
                    return
                }
                
                if httpResponse.statusCode == 200 {
                    testResult = "✅ 测试成功！OCR API 连接正常"
                } else {
                    let errorMsg = data.flatMap { String(data: $0, encoding: .utf8) } ?? "未知错误"
                    print("❌ API错误: \(errorMsg)")
                    testResult = "❌ API 返回错误 (状态码: \(httpResponse.statusCode))"
                }
            }
        }.resume()
    }
}

// 开机启动助手
class LaunchAtLoginHelper {
    static func isEnabled() -> Bool {
        // 检查是否已经添加到登录项
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // macOS 12 及以下使用旧方法
            return UserDefaults.standard.bool(forKey: "LaunchAtLogin")
        }
    }
    
    static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status == .enabled {
                        print("✅ 开机启动已启用")
                    } else {
                        try SMAppService.mainApp.register()
                        print("✅ 开机启动已设置")
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                        print("✅ 开机启动已取消")
                    }
                }
            } catch {
                print("❌ 设置开机启动失败: \(error.localizedDescription)")
            }
        } else {
            // macOS 12 及以下的处理
            UserDefaults.standard.set(enabled, forKey: "LaunchAtLogin")
            print("⚠️ macOS 12 及以下需要手动在系统设置中添加登录项")
        }
    }
}

// 快捷键显示视图
struct HotkeyDisplayView: View {
    let hotkey: Hotkey
    let isRecording: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            if isRecording {
                Text("按下新快捷键...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                // 解析显示字符串
                let components = parseHotkeyString(hotkey.displayString)
                ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                    if component == "+" {
                        Text(component)
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    } else {
                        KeyCapView(text: component)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isRecording ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func parseHotkeyString(_ string: String) -> [String] {
        // 简单解析，例如 "⌘⇧R" -> ["⌘", "+", "⇧", "+", "R"]
        var result: [String] = []
        for char in string {
            if !result.isEmpty {
                result.append("+")
            }
            result.append(String(char))
        }
        return result
    }
}

// 快捷键录制窗口
struct HotkeyRecorderView: View {
    @Binding var isPresented: Bool
    let onRecorded: (Hotkey) -> Void
    
    @State private var recordedModifiers: Set<ModifierKey> = []
    @State private var recordedKeyCode: Int?
    @State private var displayString = "按下快捷键..."
    @State private var isComplete = false
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?
    
    var body: some View {
        VStack(spacing: 24) {
            // 标题
            VStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 48))
                    .foregroundColor(.purple)
                
                Text("录制快捷键")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            // 显示区域
            VStack(spacing: 12) {
                Text(displayString)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                    .frame(minWidth: 200)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isComplete ? Color.green.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isComplete ? Color.green : Color.clear, lineWidth: 2)
                    )
                
                Text(isComplete ? "已录制完成,点击确定保存" : "提示:至少需要一个修饰键 (⌘⇧⌥⌃)")
                    .font(.caption)
                    .foregroundColor(isComplete ? .green : .secondary)
            }
            
            // 按钮
            HStack(spacing: 12) {
                Button("取消") {
                    cleanup()
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("重新录制") {
                    resetRecording()
                }
                .disabled(!isComplete)
                
                Button("确定") {
                    if let keyCode = recordedKeyCode, !recordedModifiers.isEmpty {
                        let hotkey = Hotkey(
                            keyCode: keyCode,
                            modifiers: recordedModifiers,
                            displayString: buildDisplayString()
                        )
                        onRecorded(hotkey)
                        cleanup()
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isComplete)
            }
        }
        .padding(32)
        .frame(width: 450, height: 320)
        .onAppear {
            startMonitoring()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func startMonitoring() {
        // 监听按键按下事件
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
            return nil // 阻止事件继续传播
        }
        
        // 监听修饰键变化事件（实时显示）
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handleFlagsChanged(event)
            return event // 允许修饰键事件继续传播
        }
    }
    
    private func cleanup() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            self.keyMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            self.flagsMonitor = nil
        }
    }
    
    private func resetRecording() {
        recordedModifiers = []
        recordedKeyCode = nil
        displayString = "按下快捷键..."
        isComplete = false
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        // 如果已经录制完成,忽略修饰键变化
        if isComplete {
            return
        }
        
        // 实时更新修饰键状态
        let flags = event.modifierFlags
        recordedModifiers = []
        
        if flags.contains(.command) {
            recordedModifiers.insert(.command)
        }
        if flags.contains(.shift) {
            recordedModifiers.insert(.shift)
        }
        if flags.contains(.option) {
            recordedModifiers.insert(.option)
        }
        if flags.contains(.control) {
            recordedModifiers.insert(.control)
        }
        
        // 实时更新显示
        if !recordedModifiers.isEmpty {
            displayString = buildDisplayString(withKey: false)
        } else {
            displayString = "按下快捷键..."
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        // 如果已经录制完成,忽略后续按键
        if isComplete {
            return
        }
        
        let keyCode = Int(event.keyCode)
        
        // 忽略 ESC 键
        if keyCode == 53 {
            return
        }
        
        // 记录修饰键状态
        let flags = event.modifierFlags
        recordedModifiers = []
        
        if flags.contains(.command) {
            recordedModifiers.insert(.command)
        }
        if flags.contains(.shift) {
            recordedModifiers.insert(.shift)
        }
        if flags.contains(.option) {
            recordedModifiers.insert(.option)
        }
        if flags.contains(.control) {
            recordedModifiers.insert(.control)
        }
        
        // 至少需要一个修饰键
        if !recordedModifiers.isEmpty {
            recordedKeyCode = keyCode
            displayString = buildDisplayString()
            isComplete = true
        }
    }
    
    private func buildDisplayString(withKey: Bool = true) -> String {
        var parts: [String] = []
        
        // 按照标准顺序添加修饰键
        if recordedModifiers.contains(.control) {
            parts.append("⌃")
        }
        if recordedModifiers.contains(.option) {
            parts.append("⌥")
        }
        if recordedModifiers.contains(.shift) {
            parts.append("⇧")
        }
        if recordedModifiers.contains(.command) {
            parts.append("⌘")
        }
        
        if withKey, let keyCode = recordedKeyCode {
            parts.append(keyCode.keyCharacter)
        }
        
        return parts.isEmpty ? "按下快捷键..." : parts.joined()
    }
}

// 辅助组件 - 设置行
struct SettingRow<Content: View>: View {
    let icon: String
    let title: String
    let description: String
    let content: Content
    
    init(icon: String, title: String, description: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.description = description
        self.content = content()
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            content
        }
    }
}

// 辅助组件 - 快捷键按键
struct KeyCapView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
            )
    }
}

// 辅助组件 - 功能行
struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                    .font(.body)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// 使用步骤卡片
struct UsageStepCard: View {
    let icon: String
    let color: Color
    let title: String
    let steps: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 14))
                }
                
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.subheadline)
                            .foregroundColor(color)
                            .fontWeight(.semibold)
                            .frame(width: 20, alignment: .trailing)
                        
                        Text(step)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.05))
        .cornerRadius(12)
    }
}

// 使用说明弹窗
struct UsageInstructionsWindow: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 可滚动内容区域
            ScrollView {
                VStack(spacing: 24) {
                    // 标题
                    HStack {
                        Image(systemName: "book.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                        
                        Text("使用说明")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    .padding(.top, 20)
                    
                    VStack(alignment: .leading, spacing: 20) {
                        // 配置步骤
                        UsageStepCard(
                            icon: "gearshape.2.fill",
                            color: .green,
                            title: "初次使用配置",
                            steps: [
                                "在「OCR 配置」标签页填写智谱 AI API Key",
                                "点击「测试连接」确保 API 配置正确",
                                "授予屏幕录制权限（首次使用时系统弹窗）",
                                "点击「保存配置」完成设置"
                            ]
                        )
                        
                        // 截图识别
                        UsageStepCard(
                            icon: "scissors",
                            color: .blue,
                            title: "方式一：快捷键截图识别",
                            steps: [
                                "按快捷键（默认 ⌘⇧R）启动截图模式",
                                "拖动鼠标框选要识别的文字区域",
                                "松开鼠标后自动开始识别",
                                "识别完成后自动复制并显示结果通知"
                            ]
                        )
                        
                        // 剪贴板识别
                        UsageStepCard(
                            icon: "eye.circle.fill",
                            color: .purple,
                            title: "方式二：剪贴板自动识别",
                            steps: [
                                "在「通用」标签页开启「监听剪贴板图片」",
                                "使用任意方式截图或复制图片",
                                "应用会自动检测并识别新图片",
                                "无需手动操作，解放双手"
                            ]
                        )
                        
                        // 快捷提示
                        HStack(spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.orange)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("快捷提示")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Text("• 按 Esc 可随时取消截图\n• 在「通用」标签页可自定义快捷键和图标\n• 点击菜单栏「查看历史」浏览所有识别记录\n• 识别结果通知 5 秒后自动消失")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 30)
            }
            
            // 固定在底部的关闭按钮
            Divider()
            
            Button(action: {
                isPresented = false
            }) {
                Text("关闭")
                    .font(.body)
                    .fontWeight(.medium)
                    .frame(width: 120)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .padding(.vertical, 16)
        }
        .frame(width: 550, height: 600)
    }
}

// MARK: - 图标选择器视图
struct IconPickerView: View {
    @ObservedObject var iconManager: StatusBarIconManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedIcon: StatusBarIcon
    
    init(iconManager: StatusBarIconManager) {
        self.iconManager = iconManager
        _selectedIcon = State(initialValue: iconManager.currentIcon)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("选择状态栏图标")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            // 图标网格
            ScrollView {
                VStack(spacing: 20) {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 80), spacing: 12)
                    ], spacing: 12) {
                        ForEach(StatusBarIcon.allIcons) { icon in
                            StatusBarIconButton(
                                icon: icon,
                                isSelected: selectedIcon == icon,
                                action: {
                                    selectedIcon = icon
                                }
                            )
                        }
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // 底部按钮
            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("应用") {
                    iconManager.currentIcon = selectedIcon
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIcon == iconManager.currentIcon)
            }
            .padding(20)
        }
        .frame(width: 480, height: 480)
    }
}

// 状态栏图标按钮
struct StatusBarIconButton: View {
    let icon: StatusBarIcon
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if let image = NSImage(systemSymbolName: icon.systemName, accessibilityDescription: nil) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundColor(isSelected ? .white : .primary)
                }
                
                Text(icon.name)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
            }
            .frame(width: 80, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.blue : (isHovered ? Color.gray.opacity(0.3) : Color.clear),
                        lineWidth: 2
                    )
            )
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
