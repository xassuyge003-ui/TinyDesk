import AppKit
import SwiftUI
import TinyDeskCore

/// 资料库中间列：当前筛选下的文档列表。
struct LibraryDocumentListView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.libraryPaperTheme) private var theme
    @State private var sortOrder: SortOrder = .recent
    @State private var pendingPurge: UUID?
    @State private var confirmsPurgeAllTrash = false

    private var chrome: LibraryChrome { LibraryChrome(theme: theme) }
    enum SortOrder: String, CaseIterable, Identifiable {
        case recent
        case created
        case title

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .recent: return "最近修改"
            case .created: return "创建时间"
            case .title: return "标题 A–Z"
            }
        }
    }

    private var documents: [LibraryDocument] {
        let filtered = store.filteredDocuments
        switch sortOrder {
        case .recent: return filtered.sorted { $0.updatedAt > $1.updatedAt }
        case .created: return filtered.sorted { $0.createdAt > $1.createdAt }
        case .title: return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(chrome.separator)
            if hasActiveFilters {
                filterChips
                Divider().overlay(chrome.separator)
            }
            if documents.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(PaperBackground(theme: theme, showsOrnament: false))
        .foregroundStyle(chrome.primaryText)
        .confirmationDialog(
            "永久删除这篇文档？",
            isPresented: Binding(
                get: { pendingPurge != nil },
                set: { if !$0 { pendingPurge = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("永久删除", role: .destructive) {
                if let id = pendingPurge {
                    store.purgeDocument(id)
                }
                pendingPurge = nil
            }
            Button("取消", role: .cancel) { pendingPurge = nil }
        } message: {
            Text("正文文件与全部索引都会被删除，此操作无法撤销。")
        }
        .confirmationDialog(
            "清空回收站？",
            isPresented: $confirmsPurgeAllTrash,
            titleVisibility: .visible
        ) {
            Button("清空回收站", role: .destructive) {
                store.purgeAllTrash()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("回收站中的 \(store.trashedDocuments.count) 篇文档将被永久删除，此操作无法撤销。")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(headerTitle)
                .font(LibraryTypography.title(17))
            if store.viewMode == .trash, !store.trashedDocuments.isEmpty {
                Button("清空回收站", role: .destructive) {
                    confirmsPurgeAllTrash = true
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.red)
                .help("永久删除回收站中所有文档")
            }
            Spacer()
            Menu {
                ForEach(SortOrder.allCases) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        Label(
                            order.displayName,
                            systemImage: order == sortOrder ? "checkmark" : "arrow.up.arrow.down"
                        )
                    }
                }
            } label: {
                Label(sortOrder.displayName, systemImage: "arrow.up.arrow.down")
                    .font(LibraryTypography.label(12))
                    .foregroundStyle(chrome.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .help("排序方式")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(chrome.headerBackground)
    }

    private var headerTitle: String {
        if store.viewMode == .trash {
            return "回收站 · \(store.trashedDocuments.count)"
        }
        if store.viewMode == .favorites {
            return "收藏 · \(store.favoriteDocuments.count)"
        }
        if store.viewMode == .recent {
            return "最近打开"
        }
        if let categoryID = store.activeCategoryFilter,
           let category = store.categories.first(where: { $0.id == categoryID }) {
            return "\(category.name) · \(documents.count)"
        }
        if !store.searchQuery.isEmpty {
            return "搜索结果 · \(documents.count)"
        }
        return "文档 · \(documents.count)"
    }

    private var emptyState: some View {
        Group {
            switch store.searchState {
            case .searching:
                emptyView("正在搜索…", systemImage: "magnifyingglass")
            case .empty, .failed:
                emptyView(
                    "没有匹配结果",
                    systemImage: "magnifyingglass",
                    description: store.searchState == .failed ? "搜索失败，请重试" : "试试其他关键词",
                    actionTitle: "清除搜索",
                    action: { store.search("") }
                )
            default:
                emptyStateByMode
            }
        }
    }

    @ViewBuilder
    private var emptyStateByMode: some View {
        switch store.viewMode {
        case .trash:
            emptyView("回收站是空的", systemImage: "trash")
        case .favorites:
            emptyView("还没有收藏", systemImage: "star", description: "在文档上右键选择收藏")
        case .recent:
            emptyView("还没有打开过文档", systemImage: "clock")
        default:
            if store.activeCategoryFilter != nil || !store.activeTagFilters.isEmpty {
                emptyView(
                    "该筛选下没有文档",
                    systemImage: "line.3.horizontal.decrease.circle",
                    actionTitle: "清除筛选",
                    action: clearFilters
                )
            } else {
                emptyView(
                    "还没有文档",
                    systemImage: "doc.richtext",
                    description: "新建一篇，或从左侧选择其他分类",
                    actionTitle: "新建文档",
                    action: { _ = store.createDocument() }
                )
            }
        }
    }

    private func emptyView(
        _ title: String,
        systemImage: String,
        description: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let description {
                Text(description)
            }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .foregroundStyle(chrome.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 当前生效的筛选胶囊：目录、标签、搜索词。
    private var hasActiveFilters: Bool {
        store.activeCategoryFilter != nil || !store.activeTagFilters.isEmpty || !store.searchQuery.isEmpty
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let categoryID = store.activeCategoryFilter,
                   let category = store.categories.first(where: { $0.id == categoryID }) {
                    filterChip(label: "目录：\(category.name)") {
                        store.activeCategoryFilter = nil
                    }
                }
                ForEach(store.activeTagFilters, id: \.self) { tagID in
                    if let tag = store.tags.first(where: { $0.id == tagID }) {
                        filterChip(label: "标签：\(tag.name)") {
                            store.activeTagFilters.removeAll { $0 == tagID }
                        }
                    }
                }
                if !store.searchQuery.isEmpty {
                    filterChip(label: "搜索：\(store.searchQuery)") {
                        store.search("")
                    }
                }
                if hasActiveFilters {
                    Button("清除全部", action: clearFilters)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(chrome.accent)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    private func filterChip(label: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(chrome.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(chrome.controlBackground, in: Capsule())
        .accessibilityLabel("移除\(label)")
    }

    private func clearFilters() {
        store.activeCategoryFilter = nil
        store.activeTagFilters = []
        store.search("")
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 3) {
                ForEach(documents) { document in
                    LibraryDocumentRow(
                        document: document,
                        tags: store.tags,
                        isSelected: store.selectedDocumentID == document.id,
                        snippet: snippet(for: document.id)
                    ) {
                        store.selectedDocumentID = document.id
                    }
                    .contextMenu {
                        contextMenu(for: document)
                    }
                }
            }
            .padding(8)
        }
    }

    private func snippet(for documentID: UUID) -> String? {
        guard store.searchState == .hasResults else { return nil }
        return store.searchResults.first { $0.documentID == documentID }?.snippet
    }

    @ViewBuilder
    private func contextMenu(for document: LibraryDocument) -> some View {
        if document.isTrashed {
            Button("恢复") { store.restoreDocument(document.id) }
            Button("永久删除", role: .destructive) { pendingPurge = document.id }
        } else {
            Button("新建文档", systemImage: "doc.badge.plus") { _ = store.createDocument() }
            Button("添加到桌面", systemImage: "desktopcomputer") {
                addToDesktop(document)
            }
            Button("刷新桌面摘要卡", systemImage: "arrow.triangle.2.circlepath") {
                refreshDeskRef(document)
            }
            Button(document.isFavorited ? "取消收藏" : "收藏", systemImage: "star") {
                store.toggleFavorite(document.id)
            }
            Menu("移动到目录") {
                Button("未分类", systemImage: "folder") {
                    store.updateMetadata(document.id) { $0.categoryID = nil }
                }
                ForEach(store.categories) { category in
                    Button {
                        store.updateMetadata(document.id) { $0.categoryID = category.id }
                    } label: {
                        Label(
                            category.name,
                            systemImage: document.categoryID == category.id ? "checkmark" : "folder"
                        )
                    }
                }
            }
            Menu("添加标签", systemImage: "tag") {
                ForEach(store.tags) { tag in
                    Button {
                        if document.tagIDs.contains(tag.id) {
                            store.removeTag(tag.id, from: document.id)
                        } else {
                            store.assignTag(tag.id, to: document.id)
                        }
                    } label: {
                        Label(
                            tag.name,
                            systemImage: document.tagIDs.contains(tag.id) ? "checkmark" : "tag"
                        )
                    }
                }
                if store.tags.isEmpty {
                    Text("还没有标签")
                }
            }
            Menu("纸张主题", systemImage: "paintpalette") {
                ForEach(PaperTheme.allCases, id: \.self) { theme in
                    Button {
                        store.updateMetadata(document.id) { $0.paperTheme = theme }
                    } label: {
                        Label(
                            theme.displayName,
                            systemImage: document.paperTheme == theme ? "checkmark" : "square"
                        )
                    }
                }
            }
            Divider()
            Button("移到回收站", systemImage: "trash", role: .destructive) {
                store.trashDocument(document.id)
            }
        }
    }

    private func addToDesktop(_ document: LibraryDocument) {
        let tags = document.tagIDs.compactMap { id in
            store.tags.first(where: { $0.id == id })?.name
        }
        NotificationCenter.default.post(
            name: LibraryDeskCardRequest.notificationName,
            object: nil,
            userInfo: [
                LibraryDeskCardRequest.documentIDKey: document.id,
                LibraryDeskCardRequest.titleKey: document.title,
                LibraryDeskCardRequest.summaryKey: document.summary,
                LibraryDeskCardRequest.tagsKey: tags,
            ]
        )
    }

    /// 重新同步桌面摘要卡片（已有卡片则聚焦，缺失则创建）。
    private func refreshDeskRef(_ document: LibraryDocument) {
        let tags = document.tagIDs.compactMap { id in
            store.tags.first(where: { $0.id == id })?.name
        }
        NotificationCenter.default.post(
            name: LibraryDeskCardRequest.notificationName,
            object: nil,
            userInfo: [
                LibraryDeskCardRequest.documentIDKey: document.id,
                LibraryDeskCardRequest.titleKey: document.title,
                LibraryDeskCardRequest.summaryKey: document.summary,
                LibraryDeskCardRequest.tagsKey: tags,
            ]
        )
    }
}

/// 请求把资料库文档创建为桌面摘要卡片。
enum LibraryDeskCardRequest {
    static let notificationName = Notification.Name("TinyDeskAddLibraryDeskCard")
    static let documentIDKey = "documentID"
    static let titleKey = "title"
    static let summaryKey = "summary"
    static let tagsKey = "tags"
}

/// 文档列表单行。
private struct LibraryDocumentRow: View {
    @Environment(\.libraryPaperTheme) private var theme
    let document: LibraryDocument
    let tags: [LibraryTag]
    let isSelected: Bool
    /// 搜索命中片段（带 <b> 标记）；非搜索状态为 nil。
    let snippet: String?
    let action: () -> Void

    private var chrome: LibraryChrome { LibraryChrome(theme: theme) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                PaperThemeSwatch(theme: document.paperTheme)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(document.title.isEmpty ? "未命名文档" : document.title)
                            .font(LibraryTypography.title(15))
                            .fontWeight(.semibold)
                            .foregroundStyle(chrome.primaryText)
                            .lineLimit(1)
                        if document.isFavorited {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                        }
                        if document.isTrashed {
                            Text("回收站")
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                    if let snippet {
                        Text(highlightedSnippet(snippet))
                            .font(.caption)
                            .foregroundStyle(chrome.secondaryText)
                            .lineLimit(2)
                    } else {
                        Text(summaryText)
                            .font(.caption)
                            .foregroundStyle(chrome.secondaryText)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        ForEach(document.tagIDs.prefix(3), id: \.self) { tagID in
                            if let tag = tags.first(where: { $0.id == tagID }) {
                                Text(tag.name)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color(hex: tag.colorHex))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color(hex: tag.colorHex).opacity(0.12), in: Capsule())
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(document.updatedAt.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(chrome.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? chrome.selectionFill : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? chrome.selectionBorder : .clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var summaryText: String {
        let summary = document.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? "空白文档" : summary
    }

    /// 把 FTS5 snippet 的 <b></b> 高亮转换为 AttributedString 加粗。
    private func highlightedSnippet(_ raw: String) -> AttributedString {
        var result = AttributedString()
        let parts = raw.components(separatedBy: "<b>")
        for (index, part) in parts.enumerated() {
            let segments = part.components(separatedBy: "</b>")
            for (segmentIndex, segment) in segments.enumerated() {
                var attributed = AttributedString(segment)
                if index > 0 && segmentIndex == 0 {
                    attributed.font = .caption.bold()
                    attributed.foregroundColor = chrome.accent
                }
                result += attributed
            }
        }
        return result
    }
}
