import SwiftUI
import AppKit

// MARK: - 历史记录主视图
struct HistoryView: View {
    @ObservedObject var manager = HistoryManager.shared
    @State private var searchText = ""
    @State private var selectedItem: HistoryItem? = nil
    @State private var showingClearAlert = false
    @State private var textViewKey: UUID = UUID()
    @State private var leftPanelWidth: CGFloat = 280  // 初始宽度
    
    var filteredItems: [HistoryItem] {
        if searchText.isEmpty {
            return manager.items
        }
        return manager.search(keyword: searchText)
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // 左侧：列表
                VStack(spacing: 0) {
                    // 工具栏
                    HStack {
                        // 搜索框
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("搜索历史记录...", text: $searchText)
                                .textFieldStyle(.plain)
                            
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        
                        Spacer()
                        
                        // 统计信息
                        Text("\(filteredItems.count)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .monospacedDigit()
                    }
                    .padding()
                    
                    Divider()
                    
                    // 历史记录列表
                    if filteredItems.isEmpty {
                        EmptyStateView(isSearching: !searchText.isEmpty)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredItems) { item in
                                    HistoryItemRow(
                                        item: item,
                                        isSelected: selectedItem?.id == item.id,
                                        onSelect: {
                                            selectedItem = item
                                        }
                                    )
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .frame(width: leftPanelWidth)
                
                // 分隔条
                Divider()
                
                // 拖动手柄
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .cursor(NSCursor.resizeLeftRight)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newWidth = leftPanelWidth + value.translation.width
                                leftPanelWidth = min(max(newWidth, 280), 500)
                            }
                    )
                
                // 右侧：详情
                VStack(spacing: 0) {
                    // 详情工具栏
                    HStack {
                    if let item = selectedItem {
                        Text(item.formattedTime)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("未选择")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if selectedItem != nil {
                        Button(action: copySelectedText) {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        
                        Button(action: deleteSelectedItem) {
                            Label("删除", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    Button(action: exportAllHistory) {
                        Label("导出全部", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    
                    Button(action: { showingClearAlert = true }) {
                        Label("清空", systemImage: "trash.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(manager.items.isEmpty)
                    }
                    .padding()
                    
                    Divider()
                    
                    // 详情内容
                    if let item = selectedItem {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.text)
                                    .font(.system(size: 13))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                
                                // 空白区域
                                Color.clear
                                    .frame(height: max(0, geometry.size.height - 200))
                            }
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded { _ in
                                    // 点击时重建视图清除选中
                                    textViewKey = UUID()
                                }
                        )
                        .id(textViewKey)
                        .onChange(of: selectedItem?.id) { _ in
                            textViewKey = UUID()
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("选择一条记录查看详情")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .alert("清空历史记录", isPresented: $showingClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                selectedItem = nil
                manager.clearAll()
            }
        } message: {
            Text("确定要清空所有历史记录吗？此操作不可恢复。")
        }
    }
    
    // 复制选中的文本
    private func copySelectedText() {
        guard let item = selectedItem else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        LogManager.shared.log("已复制历史记录", level: .info)
    }
    
    // 删除选中的项目
    private func deleteSelectedItem() {
        guard let item = selectedItem else { return }
        manager.deleteItem(id: item.id)
        selectedItem = nil
    }
    
    // 导出全部历史记录
    private func exportAllHistory() {
        let savePanel = NSSavePanel()
        savePanel.title = "导出历史记录"
        savePanel.nameFieldStringValue = "OCR历史记录_全部_\(Date().timeIntervalSince1970).txt"
        savePanel.allowedContentTypes = [.plainText]
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                let text = manager.exportAsText()
                do {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    LogManager.shared.log("历史记录已导出到: \(url.path)", level: .info)
                } catch {
                    LogManager.shared.log("导出失败: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }
}

// MARK: - 历史记录单行视图
struct HistoryItemRow: View {
    let item: HistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 时间
            Text(item.formattedTime)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // 文本预览
            Text(item.preview(maxLength: 100))
                .font(.system(size: 13))
                .lineLimit(2)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.gray.opacity(0.05) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - 空状态视图
struct EmptyStateView: View {
    let isSearching: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isSearching ? "magnifyingglass" : "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(isSearching ? "没有找到匹配的记录" : "暂无历史记录")
                .font(.title3)
                .foregroundColor(.secondary)
            
            if !isSearching {
                Text("识别的文本会自动保存在这里")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 窗口包装器（用于从 ContentView 打开）
struct HistoryViewWrapper: View {
    let window: NSWindow?
    
    var body: some View {
        HistoryView()
            .onAppear {
                LogManager.shared.log("历史记录视图已加载", level: .info)
            }
    }
}

// MARK: - View 扩展：鼠标指针
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { isHovered in
            if isHovered {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
