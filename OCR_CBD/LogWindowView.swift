import SwiftUI

// 日志管理器（单例）
class LogManager: ObservableObject {
    static let shared = LogManager()
    
    @Published var logs: [LogEntry] = []
    private let maxLogs = 100  // 限制为100条，避免内存占用过多
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let level: LogLevel
        
        enum LogLevel {
            case info, success, warning, error
            
            var color: Color {
                switch self {
                case .info: return .primary
                case .success: return .green
                case .warning: return .orange
                case .error: return .red
                }
            }
            
            var icon: String {
                switch self {
                case .info: return "ℹ️"
                case .success: return "✅"
                case .warning: return "⚠️"
                case .error: return "❌"
                }
            }
        }
    }
    
    private init() {
        log("日志系统已启动", level: .info)
    }
    
    func log(_ message: String, level: LogEntry.LogLevel = .info) {
        DispatchQueue.main.async {
            let entry = LogEntry(timestamp: Date(), message: message, level: level)
            self.logs.append(entry)
            
            // 限制日志数量
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
            
            // 同时输出到控制台
            print("[\(level.icon)] \(message)")
        }
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
            self.log("日志已清空", level: .info)
        }
    }
}

// 日志窗口视图
struct LogWindowView: View {
    @ObservedObject var logManager = LogManager.shared
    @State private var autoScroll = true
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("📋 调试日志")
                    .font(.headline)
                
                Spacer()
                
                Toggle(isOn: $autoScroll) {
                    Text("自动滚动")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                
                Button(action: {
                    logManager.clear()
                }) {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                
                Button(action: {
                    copyLogs()
                }) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 日志列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(logManager.logs) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: logManager.logs.count) { _ in
                    if autoScroll, let lastLog = logManager.logs.last {
                        withAnimation {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private func copyLogs() {
        let text = logManager.logs.map { entry in
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let time = formatter.string(from: entry.timestamp)
            return "[\(time)] \(entry.level.icon) \(entry.message)"
        }.joined(separator: "\n")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        logManager.log("日志已复制到剪贴板", level: .success)
    }
}

// 日志条目行
struct LogEntryRow: View {
    let entry: LogManager.LogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeString)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Text(entry.level.icon)
                .font(.caption)
            
            Text(entry.message)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(entry.level.color)
                .textSelection(.enabled)
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: entry.timestamp)
    }
}

// 预览
struct LogWindowView_Previews: PreviewProvider {
    static var previews: some View {
        LogWindowView()
    }
}
