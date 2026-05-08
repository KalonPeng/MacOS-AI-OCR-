import Foundation
import SwiftUI

// MARK: - 历史记录数据模型
struct HistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
    
    init(text: String) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
    }
    
    // 格式化时间显示
    var formattedTime: String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(timestamp) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "今天 \(formatter.string(from: timestamp))"
        } else if calendar.isDateInYesterday(timestamp) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "昨天 \(formatter.string(from: timestamp))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd HH:mm"
            return formatter.string(from: timestamp)
        }
    }
    
    // 预览文本（最多显示指定字符数）
    func preview(maxLength: Int = 100) -> String {
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "..."
    }
}

// MARK: - 历史记录管理器
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    
    @Published private(set) var items: [HistoryItem] = []
    
    private let maxHistoryCount = 50  // 最多保存50条记录
    private let userDefaultsKey = "OCR_History"
    
    private init() {
        loadHistory()
    }
    
    // MARK: - 保存历史记录
    func saveHistory(text: String) {
        // 忽略空文本
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        // 创建新记录
        let newItem = HistoryItem(text: text)
        
        // 添加到列表开头
        items.insert(newItem, at: 0)
        
        // 限制历史记录数量
        if items.count > maxHistoryCount {
            items = Array(items.prefix(maxHistoryCount))
        }
        
        // 持久化
        persistHistory()
        
        LogManager.shared.log("已保存历史记录，当前总数: \(items.count)", level: .info)
    }
    
    // MARK: - 删除单条记录
    func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        persistHistory()
        LogManager.shared.log("已删除历史记录 ID: \(id)", level: .info)
    }
    
    // MARK: - 删除多条记录
    func deleteItems(ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        persistHistory()
        LogManager.shared.log("已删除 \(ids.count) 条历史记录", level: .info)
    }
    
    // MARK: - 清空所有历史
    func clearAll() {
        items.removeAll()
        persistHistory()
        LogManager.shared.log("已清空所有历史记录", level: .info)
    }
    
    // MARK: - 搜索历史记录
    func search(keyword: String) -> [HistoryItem] {
        guard !keyword.isEmpty else {
            return items
        }
        
        return items.filter { item in
            item.text.localizedCaseInsensitiveContains(keyword)
        }
    }
    
    // MARK: - 持久化存储
    private func persistHistory() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(items)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            LogManager.shared.log("保存历史记录失败: \(error.localizedDescription)", level: .error)
        }
    }
    
    // MARK: - 加载历史记录
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            LogManager.shared.log("没有找到历史记录", level: .info)
            return
        }
        
        do {
            let decoder = JSONDecoder()
            items = try decoder.decode([HistoryItem].self, from: data)
            LogManager.shared.log("已加载 \(items.count) 条历史记录", level: .info)
        } catch {
            LogManager.shared.log("加载历史记录失败: \(error.localizedDescription)", level: .error)
            items = []
        }
    }
    
    // MARK: - 导出历史记录为文本
    func exportAsText() -> String {
        var result = "OCR 识别历史记录\n"
        result += "导出时间: \(Date())\n"
        result += "共 \(items.count) 条记录\n"
        result += String(repeating: "=", count: 50) + "\n\n"
        
        for (index, item) in items.enumerated() {
            result += "[\(index + 1)] \(item.formattedTime)\n"
            result += item.text
            result += "\n\n" + String(repeating: "-", count: 50) + "\n\n"
        }
        
        return result
    }
}
