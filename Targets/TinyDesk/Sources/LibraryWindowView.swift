import AppKit
import SwiftUI
import TinyDeskCore

/// 左侧导航、中间列表、右侧编辑器共用同一花笺色系。
struct LibraryChrome {
    let theme: PaperTheme

    private var style: PaperThemeStyle { .style(for: theme) }

    var navigationBackground: Color { style.backgroundColorSwiftUI }
    var listBackground: Color { style.backgroundColorSwiftUI }
    var headerBackground: Color { style.textColorSwiftUI.opacity(style.isDark ? 0.075 : 0.035) }
    var controlBackground: Color { style.textColorSwiftUI.opacity(style.isDark ? 0.12 : 0.07) }
    var primaryText: Color { style.textColorSwiftUI }
    var secondaryText: Color { style.textColorSwiftUI.opacity(0.66) }
    var tertiaryText: Color { style.textColorSwiftUI.opacity(0.42) }
    var accent: Color { style.accentColorSwiftUI }
    var selectionFill: Color { accent.opacity(style.isDark ? 0.24 : 0.14) }
    var selectionBorder: Color { accent.opacity(style.isDark ? 0.55 : 0.34) }
    var separator: Color { style.textColorSwiftUI.opacity(0.12) }
    var colorScheme: ColorScheme { style.isDark ? .dark : .light }
}

/// 桌面摘要卡片请求打开资料库某文档的通知。
enum LibraryDocumentOpenRequest {
    static let notificationName = Notification.Name("TinyDeskOpenLibraryDocument")
    static let documentIDKey = "documentID"
}

/// 应用级打开协调器：资料库窗口未打开时也能先开窗再选中文档。
/// 仅主线程访问。
enum LibraryOpenCoordinator {
    static var pendingDocumentID: UUID?

    static func consumePending() -> UUID? {
        let id = pendingDocumentID
        pendingDocumentID = nil
        return id
    }
}

/// 资料库文档变更通知：驱动桌面摘要卡片同步标题、摘要、标签和生命周期状态。
enum LibraryDocumentSyncNotification {
    static let notificationName = Notification.Name("TinyDeskLibraryDocumentDidChange")
    static let documentIDKey = "documentID"
    static let titleKey = "title"
    static let summaryKey = "summary"
    static let tagsKey = "tags"
    static let statusKey = "status"

    static func post(
        documentID: UUID,
        title: String,
        summary: String,
        tags: [String],
        status: DesktopReferenceStatus?
    ) {
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: [
                documentIDKey: documentID,
                titleKey: title,
                summaryKey: summary,
                tagsKey: tags,
                statusKey: status?.rawValue as Any,
            ]
        )
    }
}

/// 资料库主窗口：三栏布局 + 工具栏。
struct LibraryWindowView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var searchText = ""
    @State private var showsInfoPanel = false
    @State private var importDocument: ImportContext?
    @State private var isWritingFocus = false

    var body: some View {
        VStack(spacing: 0) {
            if let message = store.storageMessage {
                libraryErrorBanner(message)
            }
            HSplitView {
                if !isWritingFocus {
                    LibrarySidebarView()
                        .frame(minWidth: 200, idealWidth: 236, maxWidth: 280)
                    LibraryDocumentListView()
                        .frame(minWidth: 280, idealWidth: 340, maxWidth: 440)
                }
                if isWritingFocus {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        LibraryEditorView()
                            .frame(maxWidth: 800)
                        Spacer(minLength: 0)
                    }
                } else {
                    LibraryEditorView()
                        .frame(minWidth: 480)
                }
                if !isWritingFocus, showsInfoPanel {
                    LibraryInfoPanel()
                        .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
                }
            }
        }
        .background(PaperBackground(theme: activeTheme, showsOrnament: false))
        .environment(\.libraryPaperTheme, activeTheme)
        .tint(chrome.accent)
        .preferredColorScheme(chrome.colorScheme)
        .frame(minWidth: 980, minHeight: 620)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isWritingFocus.toggle()
                    }
                } label: {
                    Label(
                        isWritingFocus ? "退出专注写作" : "专注写作",
                        systemImage: isWritingFocus ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
                    )
                }
                .help(isWritingFocus ? "退出专注写作" : "隐藏导航栏，专注写作")
            }

            ToolbarItem(placement: .automatic) {
                LibrarySearchField(theme: activeTheme, text: $searchText) { query in
                    store.search(query)
                }
                .frame(width: 240)
                .help("全文搜索标题、正文、标签、目录")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    _ = store.createDocument()
                } label: {
                    Label("新建", systemImage: "square.and.pencil")
                }
                .help("新建资料文档（⌘N）")

                Button {
                    importDocument = ImportContext()
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .help("导入 RTF、RTFD、TXT 或 Markdown")

                Button {
                    exportDocument()
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .disabled(selectedDocument == nil)
                .help("导出当前文档")

                if selectedDocument != nil {
                    Menu {
                        paperThemeMenu
                        Divider()
                        Button {
                            showsInfoPanel.toggle()
                        } label: {
                            Label(
                                showsInfoPanel ? "隐藏文档信息" : "显示文档信息",
                                systemImage: "info.circle"
                            )
                        }
                    } label: {
                        Label("更多文档操作", systemImage: "ellipsis.circle")
                    }
                    .help("纸张主题与文档信息")
                }
            }
        }
        .sheet(item: $importDocument) { _ in
            DocumentImporterView()
                .environmentObject(store)
        }
        .onAppear {
            // 优先处理来自桌面摘要卡的打开请求（窗口关闭期间积压）。
            if let pending = LibraryOpenCoordinator.consumePending() {
                selectDocument(pending)
            } else if store.selectedDocumentID == nil, let first = store.activeDocuments.first {
                store.selectedDocumentID = first.id
                store.markOpened(first.id)
            }
        }
        .onChange(of: store.searchQuery) { _, newValue in
            if searchText != newValue {
                searchText = newValue
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: LibraryDocumentOpenRequest.notificationName)
        ) { notification in
            guard let id = notification.userInfo?[LibraryDocumentOpenRequest.documentIDKey] as? UUID else { return }
            LibraryOpenCoordinator.pendingDocumentID = nil
            selectDocument(id)
        }
    }

    /// 资料库存储错误的统一横幅。
    private func libraryErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([store.databaseURL])
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Button("关闭") { store.dismissStorageMessage() }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func selectDocument(_ id: UUID) {
        guard store.document(withID: id) != nil else {
            store.report("找不到关联文档（可能已被删除）。")
            return
        }
        store.viewMode = .all
        store.activeCategoryFilter = nil
        store.activeTagFilters = []
        store.search("")
        store.selectedDocumentID = id
        store.markOpened(id)
        // 前置并激活资料库窗口，避免“点了没反应”。
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private var selectedDocument: LibraryDocument? {
        guard let id = store.selectedDocumentID else { return nil }
        return store.document(withID: id)
    }

    private var activeTheme: PaperTheme {
        selectedDocument?.paperTheme ?? .suJian
    }

    private var chrome: LibraryChrome {
        LibraryChrome(theme: activeTheme)
    }

    @ViewBuilder
    private var paperThemeMenu: some View {
        ForEach(PaperTheme.allCases, id: \.self) { theme in
            Button {
                if let document = selectedDocument {
                    store.updateMetadata(document.id) { $0.paperTheme = theme }
                }
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(nsColor: PaperThemeStyle.style(for: theme).backgroundColor))
                        .frame(width: 26, height: 18)
                        .overlay {
                            Circle()
                                .fill(Color(nsColor: PaperThemeStyle.style(for: theme).accentColor))
                                .frame(width: 5, height: 5)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(.separator.opacity(0.4), lineWidth: 1)
                        }
                    Text("\(theme.displayName) · \(theme.materialDescription)")
                        .foregroundStyle(Color(nsColor: PaperThemeStyle.style(for: theme).textColor))
                    if selectedDocument?.paperTheme == theme {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    private func exportDocument() {
        guard let document = selectedDocument else { return }
        // 先同步保存编辑器中的未落盘正文，再读取文件导出。
        LibraryExportWillBeginNotification.post()
        let panel = NSSavePanel()
        panel.title = "导出文档"
        panel.allowedContentTypes = LibraryImportExport.supportedExportContentTypes
        panel.nameFieldStringValue = "\(document.title).rtf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try LibraryImportExport.export(document, to: url, store: store)
            } catch {
                let alert = NSAlert()
                alert.messageText = "导出失败"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    private struct ImportContext: Identifiable {
        let id = UUID()
    }
}

/// 导入文档的 sheet。
struct DocumentImporterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: LibraryStore
    @State private var importError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Text("导入文档")
                    .font(.headline)
                Spacer()
                Button("选择文件…", action: chooseFile)
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("支持 RTF、RTFD、TXT、Markdown")
                    .font(.callout)
                Text("导入后原文件不会被修改；正文以本地 RTFD 保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Markdown 会保留纯文本，复杂富文本样式请使用 RTF 或 RTFD。")
                    .font(.caption)
                    .foregroundStyle(.orange)
                if let importError {
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 480, minHeight: 220)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "导入文档"
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = LibraryImportExport.supportedImportContentTypes
        panel.begin { response in
            guard response == .OK else { return }
            do {
                let imported = try LibraryImportExport.importFiles(panel.urls, store: store)
                importError = nil
                if imported > 0 {
                    dismiss()
                } else {
                    importError = "没有导入任何文档。"
                }
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

/// 信息面板：当前文档的元数据。
struct LibraryInfoPanel: View {
    @EnvironmentObject private var store: LibraryStore

    private var document: LibraryDocument? {
        guard let id = store.selectedDocumentID else { return nil }
        return store.document(withID: id)
    }

    var body: some View {
        if let document {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label("文档信息", systemImage: "info.circle")
                        .font(.headline)
                    LabeledContent("创建", value: document.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("修改", value: document.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("字数", value: "\(document.wordCount)")
                    LabeledContent("纸张", value: document.paperTheme.displayName)
                    LabeledContent("字体", value: document.fontPreset.displayName)
                    Divider()
                    Picker("目录", selection: categoryBinding(for: document)) {
                        Text("未分类").tag(nil as UUID?)
                        ForEach(store.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    .pickerStyle(.menu)
                    Text("标签")
                        .font(.subheadline.weight(.semibold))
                    ForEach(document.tagIDs, id: \.self) { tagID in
                        if let tag = store.tags.first(where: { $0.id == tagID }) {
                            HStack {
                                Circle().fill(Color(hex: tag.colorHex)).frame(width: 8, height: 8)
                                Text(tag.name)
                            }
                            .font(.caption)
                        }
                    }
                    if document.tagIDs.isEmpty {
                        Text("暂无标签")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Menu("编辑标签", systemImage: "tag") {
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
                            Text("请先在左侧创建标签")
                        }
                    }
                    .menuStyle(.borderlessButton)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 220)
            .background(PaperBackground(theme: document.paperTheme, showsOrnament: false))
        }
    }

    private func categoryBinding(for document: LibraryDocument) -> Binding<UUID?> {
        Binding(
            get: { document.categoryID },
            set: { categoryID in
                store.updateMetadata(document.id) { $0.categoryID = categoryID }
            }
        )
    }
}

/// 资料库搜索输入框。
private struct LibrarySearchField: View {
    let theme: PaperTheme
    @Binding var text: String
    var onSubmit: (String) -> Void

    private var chrome: LibraryChrome { LibraryChrome(theme: theme) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(chrome.secondaryText)
            TextField("搜索资料库…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(chrome.primaryText)
                .onSubmit { onSubmit(text) }
                .onChange(of: text) { _, newValue in
                    onSubmit(newValue)
                }
            if !text.isEmpty {
                Button {
                    text = ""
                    onSubmit("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(chrome.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(chrome.controlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(chrome.selectionBorder.opacity(0.55), lineWidth: 0.7)
        }
    }
}
