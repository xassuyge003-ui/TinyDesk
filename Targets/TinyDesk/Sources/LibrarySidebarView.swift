import AppKit
import SwiftUI
import TinyDeskCore

/// 资料库左侧边栏：目录、标签、收藏、最近、回收站。
struct LibrarySidebarView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.libraryPaperTheme) private var theme
    @State private var showsAddCategory = false
    @State private var newCategoryName = ""
    @State private var showsAddTag = false
    @State private var newTagName = ""
    @State private var pendingDeleteCategory: LibraryCategory?
    @State private var pendingDeleteTag: LibraryTag?

    private var chrome: LibraryChrome { LibraryChrome(theme: theme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                smartLists
                Divider().overlay(chrome.separator)
                categoriesSection
                tagsSection
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .background(PaperBackground(theme: theme, showsOrnament: false))
        .foregroundStyle(chrome.primaryText)
        .frame(minWidth: 200)
        .alert("新建目录", isPresented: $showsAddCategory) {
            TextField("目录名称", text: $newCategoryName)
            Button("创建") { createCategory() }
            Button("取消", role: .cancel) {}
        }
        .alert("新建标签", isPresented: $showsAddTag) {
            TextField("标签名称", text: $newTagName)
            Button("创建") { createTag() }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "删除目录“\(pendingDeleteCategory?.name ?? "")”？",
            isPresented: Binding(
                get: { pendingDeleteCategory != nil },
                set: { if !$0 { pendingDeleteCategory = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除目录", role: .destructive) {
                if let category = pendingDeleteCategory {
                    store.deleteCategory(category.id)
                }
                pendingDeleteCategory = nil
            }
            Button("取消", role: .cancel) { pendingDeleteCategory = nil }
        } message: {
            if let category = pendingDeleteCategory {
                let count = store.documents.filter { $0.categoryID == category.id }.count
                Text(count > 0
                    ? "该目录下的 \(count) 篇文档会变为“未分类”，目录本身将被删除。"
                    : "目录本身将被删除。")
            }
        }
        .confirmationDialog(
            "删除标签“\(pendingDeleteTag?.name ?? "")”？",
            isPresented: Binding(
                get: { pendingDeleteTag != nil },
                set: { if !$0 { pendingDeleteTag = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除标签", role: .destructive) {
                if let tag = pendingDeleteTag {
                    store.deleteTag(tag.id)
                }
                pendingDeleteTag = nil
            }
            Button("取消", role: .cancel) { pendingDeleteTag = nil }
        } message: {
            if let tag = pendingDeleteTag {
                let count = store.documents.filter { $0.tagIDs.contains(tag.id) }.count
                Text(count > 0
                    ? "\(count) 篇文档将不再带有该标签，标签本身将被删除。"
                    : "标签本身将被删除。")
            }
        }
    }

    private var smartLists: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("资料库 · \(theme.displayName)")
            navigationRow(
                "全部文档",
                systemImage: "tray.full",
                isActive: isModeActive(.all),
                count: store.activeDocuments.count
            ) {
                showMode(.all)
            }
            navigationRow(
                "收藏",
                systemImage: "star",
                isActive: isModeActive(.favorites),
                count: store.favoriteDocuments.count
            ) {
                showMode(.favorites)
            }
            navigationRow(
                "最近打开",
                systemImage: "clock",
                isActive: isModeActive(.recent),
                count: nil
            ) {
                showMode(.recent)
            }
            navigationRow(
                "回收站",
                systemImage: "trash",
                isActive: isModeActive(.trash),
                count: store.trashedDocuments.isEmpty ? nil : store.trashedDocuments.count,
                iconColor: isModeActive(.trash) ? .red : chrome.secondaryText
            ) {
                showMode(.trash)
            }
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("目录") {
                newCategoryName = ""
                showsAddCategory = true
            }
            if store.categories.isEmpty {
                emptyHint("尚无目录")
            }
            ForEach(store.categories) { category in
                navigationRow(
                    category.name,
                    systemImage: category.iconName ?? "folder",
                    isActive: store.viewMode == .all && store.activeCategoryFilter == category.id,
                    count: nil
                ) {
                    store.viewMode = .all
                    store.activeCategoryFilter = category.id
                }
                .contextMenu {
                    Button("重命名") { rename(category) }
                    Button("删除", role: .destructive) { pendingDeleteCategory = category }
                }
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("标签") {
                newTagName = ""
                showsAddTag = true
            }
            if store.tags.isEmpty {
                emptyHint("尚无标签")
            }
            ForEach(store.tags) { tag in
                navigationRow(
                    tag.name,
                    systemImage: "tag.fill",
                    isActive: store.activeTagFilters.contains(tag.id),
                    count: nil,
                    iconColor: Color(hex: tag.colorHex)
                ) {
                    store.viewMode = .all
                    toggleTagFilter(tag.id)
                }
                .contextMenu {
                    Button("重命名") { renameTag(tag) }
                    Button("删除", role: .destructive) { pendingDeleteTag = tag }
                }
            }
        }
    }

    private func navigationRow(
        _ title: String,
        systemImage: String,
        isActive: Bool,
        count: Int?,
        iconColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? chrome.accent : (iconColor ?? chrome.secondaryText))
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isActive ? chrome.accent.opacity(0.82) : chrome.secondaryText)
                }
            }
            .font(LibraryTypography.label(13))
            .fontWeight(isActive ? .semibold : .regular)
            .foregroundStyle(isActive ? chrome.accent : chrome.primaryText)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isActive ? chrome.selectionFill : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isActive ? chrome.selectionBorder : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func sectionHeader(_ title: String, action: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title)
                .font(LibraryTypography.label(12))
                .fontWeight(.semibold)
                .foregroundStyle(chrome.secondaryText)
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(chrome.secondaryText)
                .help("新建\(title)")
            }
        }
        .padding(.horizontal, 8)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(chrome.tertiaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
    }

    private func isModeActive(_ mode: LibraryViewMode) -> Bool {
        store.viewMode == mode
            && store.activeCategoryFilter == nil
            && store.activeTagFilters.isEmpty
            && store.searchQuery.isEmpty
    }

    private func showMode(_ mode: LibraryViewMode) {
        store.viewMode = mode
        store.activeCategoryFilter = nil
        store.activeTagFilters = []
        store.search("")
    }

    private func createCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let category = store.addCategory(name: name)
        store.activeCategoryFilter = category.id
    }

    private func createTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = store.addTag(name: name)
    }

    private func toggleTagFilter(_ id: UUID) {
        if store.activeTagFilters.contains(id) {
            store.activeTagFilters.removeAll { $0 == id }
        } else {
            store.activeTagFilters.append(id)
        }
    }

    private func rename(_ category: LibraryCategory) {
        let alert = NSAlert()
        alert.messageText = "重命名目录"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = category.name
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                store.renameCategory(category.id, to: name)
            }
        }
    }

    private func renameTag(_ tag: LibraryTag) {
        let alert = NSAlert()
        alert.messageText = "重命名标签"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = tag.name
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                store.renameTag(tag.id, to: name)
            }
        }
    }
}
