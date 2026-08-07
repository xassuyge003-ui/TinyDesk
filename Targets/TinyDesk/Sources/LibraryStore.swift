import Combine
import Foundation
import TinyDeskCore

/// 资料库侧边栏视图模式。
enum LibraryViewMode {
    case all
    case favorites
    case recent
    case trash
}

/// 全文搜索状态，区分“未搜索/搜索中/有结果/无结果/失败”。
enum LibrarySearchState: Equatable {
    case idle
    case searching
    case hasResults
    case empty
    case failed
}

/// 资料库主 Store。持有 SQLite 索引与 RTFD 文件管理器，向上暴露 UI 状态。
///
/// 只读写 `Library/library.db` 与 `Library/documents/`，不触碰
/// `workspace.json`，保证 v2.0 桌面数据零回归。
@MainActor
final class LibraryStore: ObservableObject {
    // MARK: 已发布状态

    @Published private(set) var categories: [LibraryCategory] = []
    @Published private(set) var tags: [LibraryTag] = []
    @Published private(set) var documents: [LibraryDocument] = []
    @Published private(set) var searchResults: [LibrarySearchResult] = []
    @Published private(set) var searchState: LibrarySearchState = .idle
    @Published private(set) var storageMessage: String?
    @Published var selectedDocumentID: UUID?
    @Published var activeCategoryFilter: UUID?
    @Published var activeTagFilters: [UUID] = []
    @Published var searchQuery: String = ""
    /// 侧边栏视图模式：全部 / 收藏 / 最近 / 回收站。
    @Published var viewMode: LibraryViewMode = .all

    /// 是否需要提示资料库已就绪。
    @Published private(set) var isReady = false

    private let indexer: FTSIndexer
    private let fileManager: LibraryFileManager
    let databaseURL: URL

    private var pendingSave: DispatchWorkItem?
    private var searchTask: Task<Void, Never>?

    init(databaseURL: URL? = nil) {
        let resolvedURL = databaseURL ?? Self.defaultDatabaseURL()
        self.databaseURL = resolvedURL
        let documentsDirectory = resolvedURL
            .deletingLastPathComponent()
            .appendingPathComponent(TinyDeskConst.libraryDocumentsDirectoryName, isDirectory: true)

        // 打开失败时退回临时目录的新库，避免资料库整体不可用。
        // 临时库必须与临时 documents 目录配套使用，正文不能写入正式目录，
        // 否则会出现“索引在临时库、文件在正式目录”的数据错位。
        var resolvedIndexer: FTSIndexer
        var resolvedDocumentsDirectory = documentsDirectory
        var openErrorMessage: String?
        do {
            resolvedIndexer = try FTSIndexer(url: resolvedURL)
        } catch {
            let fallbackDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("tinydesk-library-\(UUID().uuidString)", isDirectory: true)
            let fallbackURL = fallbackDirectory.appendingPathComponent("library.db")
            resolvedIndexer = (try? FTSIndexer(url: fallbackURL)) ?? .unavailable()
            resolvedDocumentsDirectory = fallbackDirectory
                .appendingPathComponent(TinyDeskConst.libraryDocumentsDirectoryName, isDirectory: true)
            openErrorMessage = "资料库打开失败，已使用临时数据目录（重启后重新读取正式库）：\(error.localizedDescription)"
        }
        indexer = resolvedIndexer
        fileManager = LibraryFileManager(documentsDirectory: resolvedDocumentsDirectory)
        if let openErrorMessage {
            storageMessage = openErrorMessage
        }

        reloadAll()
        repairIndexIfNeeded()
        purgeExpiredTrashIfNeeded()
        isReady = true
    }

    /// 报告一条用户可见的存储错误。
    func report(_ message: String) {
        storageMessage = message
    }

    /// 广播文档变更，驱动桌面摘要卡片同步。
    private func postDocumentSync(_ document: LibraryDocument, status: DesktopReferenceStatus? = nil) {
        let tagNames = document.tagIDs.compactMap { id in
            tags.first(where: { $0.id == id })?.name
        }
        LibraryDocumentSyncNotification.post(
            documentID: document.id,
            title: document.title,
            summary: document.summary,
            tags: tagNames,
            status: status
        )
    }

    // MARK: 派生数据

    var activeDocuments: [LibraryDocument] {
        documents.filter { $0.deletedAt == nil }
    }

    var trashedDocuments: [LibraryDocument] {
        documents.filter { $0.deletedAt != nil }
    }

    var favoriteDocuments: [LibraryDocument] {
        activeDocuments.filter(\.isFavorited)
    }

    var recentDocuments: [LibraryDocument] {
        activeDocuments
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(10)
            .map { $0 }
    }

    /// 按当前视图模式 + 筛选（目录 + 标签 + 搜索）过滤的文档。
    var filteredDocuments: [LibraryDocument] {
        let base: [LibraryDocument]
        switch viewMode {
        case .all:
            base = activeDocuments
        case .favorites:
            base = activeDocuments.filter(\.isFavorited)
        case .recent:
            base = recentDocuments
        case .trash:
            base = trashedDocuments
        }

        let byCategory: [LibraryDocument]
        if let activeCategoryFilter {
            byCategory = base.filter { $0.categoryID == activeCategoryFilter }
        } else {
            byCategory = base
        }

        let byTags: [LibraryDocument]
        if activeTagFilters.isEmpty {
            byTags = byCategory
        } else {
            byTags = byCategory.filter { document in
                activeTagFilters.allSatisfy(document.tagIDs.contains)
            }
        }

        // 搜索完成且无结果（或失败）时列表必须为空，不能回退显示全部文档。
        if searchState == .empty || searchState == .failed {
            return []
        }
        if searchResults.isEmpty {
            return byTags
        }
        let resultIDs = Set(searchResults.map(\.documentID))
        return byTags.filter { resultIDs.contains($0.id) }
    }

    /// 标题、标签、目录名、正文的索引文本。
    private func indexText(for document: LibraryDocument, attributedString: NSAttributedString?) -> (body: String, tags: [String], category: String) {
        let body = attributedString?.string ?? ""
        let tagNames = document.tagIDs.compactMap { id in
            tags.first(where: { $0.id == id })?.name
        }
        let categoryName = document.categoryID.flatMap { id in
            categories.first(where: { $0.id == id })?.name
        } ?? ""
        return (body, tagNames, categoryName)
    }

    // MARK: 文档操作

    /// 创建文档。持久化成功后返回文档；失败返回 nil 并保留错误提示，
    /// 不产生幽灵选中项。
    @discardableResult
    func createDocument(
        title: String = "未命名文档",
        attributedString: NSAttributedString = NSAttributedString()
    ) -> LibraryDocument? {
        let plain = attributedString.string
        let now = Date()
        let document = LibraryDocument(
            title: title,
            paperTheme: defaultPaperTheme,
            fontPreset: .fangSong,
            wordCount: plain.trimmingCharacters(in: .whitespacesAndNewlines).count,
            summary: Self.summary(from: plain),
            createdAt: now,
            updatedAt: now
        )
        do {
            try persist(document: document, attributedString: attributedString)
            selectedDocumentID = document.id
            return document
        } catch {
            storageMessage = "创建文档失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 摘要规则：去首尾空白、压缩换行、截取前 120 字。
    static func summary(from text: String) -> String {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isNewline })
            .joined(separator: " ")
        return String(cleaned.prefix(120))
    }

    /// 还原备份中的一篇文档，同时保留创建/修改时间和全部元数据。
    ///
    /// 新文档会使用新的 UUID；目录和标签由调用方提前映射，避免覆盖现有资料库。
    @discardableResult
    func restoreDocument(
        from source: LibraryDocument,
        categoryID: UUID?,
        tagIDs: [UUID],
        attributedString: NSAttributedString,
        rtfdFileWrapper: FileWrapper? = nil
    ) throws -> LibraryDocument {
        let document = LibraryDocument(
            title: source.title,
            categoryID: categoryID,
            tagIDs: tagIDs,
            isFavorited: source.isFavorited,
            paperTheme: source.paperTheme,
            fontPreset: source.fontPreset,
            wordCount: source.wordCount,
            summary: source.summary,
            customCoverColorHex: source.customCoverColorHex,
            createdAt: source.createdAt,
            updatedAt: source.updatedAt,
            deletedAt: source.deletedAt
        )

        do {
            if let rtfdFileWrapper {
                try fileManager.save(documentID: document.id, rtfdFileWrapper: rtfdFileWrapper)
            } else {
                try fileManager.save(documentID: document.id, attributedString: attributedString)
            }
            let tagNames = tagIDs.compactMap { id in
                tags.first(where: { $0.id == id })?.name
            }
            let categoryName = categoryID.flatMap { id in
                categories.first(where: { $0.id == id })?.name
            } ?? ""
            do {
                try indexer.withTransaction {
                    try indexer.insertDocument(document)
                    try indexer.index(
                        documentID: document.id,
                        title: document.title,
                        body: attributedString.string,
                        tags: tagNames,
                        category: categoryName
                    )
                }
            } catch {
                // 数据库写入失败时清理刚写入的正文文件，避免孤儿 RTFD。
                try? fileManager.delete(documentID: document.id)
                throw error
            }
            documents.append(document)
            selectedDocumentID = document.id
            return document
        } catch {
            storageMessage = "恢复文档失败：\(error.localizedDescription)"
            throw error
        }
    }

    /// 保存文档正文与元数据，并更新全文索引。
    func updateDocument(
        _ id: UUID,
        attributedString: NSAttributedString? = nil,
        mutate: ((inout LibraryDocument) -> Void)? = nil
    ) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        var document = documents[index]
        mutate?(&document)
        document.updatedAt = Date()

        let fileWasWritten: Bool
        if let attributedString {
            do {
                try fileManager.save(documentID: id, attributedString: attributedString)
                fileWasWritten = true
            } catch {
                storageMessage = "保存文档失败：\(error.localizedDescription)"
                fileWasWritten = false
            }
        } else {
            fileWasWritten = true
        }

        guard fileWasWritten else { return }
        documents[index] = document
        persistMetadata(document, bodyText: attributedString?.string)
        postDocumentSync(document)
        scheduleRefresh()
    }

    /// 仅更新元数据（标题、目录、标签、主题等），不动正文文件。
    func updateMetadata(_ id: UUID, _ mutate: (inout LibraryDocument) -> Void) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        var document = documents[index]
        mutate(&document)
        document.updatedAt = Date()
        documents[index] = document
        persistMetadata(document)
        postDocumentSync(document)
        scheduleRefresh()
    }

    func loadAttributedString(for id: UUID) -> NSAttributedString? {
        fileManager.load(documentID: id)
    }

    /// 读取正文；文件缺失或损坏时向用户报告，避免静默显示空白文档。
    func loadAttributedStringOrReport(for id: UUID) -> NSAttributedString? {
        guard let attributed = fileManager.load(documentID: id) else {
            storageMessage = "无法读取文档正文（文件缺失或已损坏）。"
            return nil
        }
        return attributed
    }

    func loadAttributedString(for document: LibraryDocument) -> NSAttributedString? {
        fileManager.load(documentID: document.id)
    }

    func document(withID id: UUID) -> LibraryDocument? {
        documents.first { $0.id == id }
    }

    /// 移入回收站（软删除）。
    func trashDocument(_ id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        var document = documents[index]
        document.deletedAt = Date()
        document.updatedAt = Date()
        documents[index] = document
        persistMetadata(document)
        postDocumentSync(document, status: .trashed)
        if selectedDocumentID == id {
            selectedDocumentID = nil
        }
        scheduleRefresh()
    }

    /// 从回收站恢复。
    func restoreDocument(_ id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        var document = documents[index]
        document.deletedAt = nil
        document.updatedAt = Date()
        documents[index] = document
        persistMetadata(document)
        postDocumentSync(document)
        scheduleRefresh()
    }

    /// 从回收站永久删除（物理删除文件 + 数据库行）。任一步失败都保留内存记录，
    /// 避免“文件已删但记录仍在”或“记录已删但文件仍在”的单侧状态。
    func purgeDocument(_ id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        var fileDeleted = false
        var dbDeleted = false
        do {
            try fileManager.delete(documentID: id)
            fileDeleted = true
        } catch {
            storageMessage = "删除文档文件失败：\(error.localizedDescription)"
        }
        do {
            try indexer.deleteDocument(id)
            dbDeleted = true
        } catch {
            storageMessage = "删除文档索引失败：\(error.localizedDescription)"
        }
        guard fileDeleted, dbDeleted else { return }
        postDocumentSync(documents[index], status: .missing)
        documents.remove(at: index)
        if selectedDocumentID == id {
            selectedDocumentID = nil
        }
        scheduleRefresh()
    }

    /// 清空回收站。
    func purgeAllTrash() {
        let trashed = trashedDocuments.map(\.id)
        for id in trashed {
            purgeDocument(id)
        }
    }

    private func purgeExpiredTrashIfNeeded() {
        let cutoff = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        do {
            let expired = try indexer.purgeExpiredTrash(before: cutoff)
            guard !expired.isEmpty else { return }
            var fileFailures = 0
            for id in expired {
                do {
                    try fileManager.delete(documentID: id)
                } catch {
                    fileFailures += 1
                }
            }
            if fileFailures > 0 {
                storageMessage = "回收站清理完成，但有 \(fileFailures) 个文档文件未能删除。"
            }
            reloadAll()
        } catch {
            storageMessage = "回收站清理失败：\(error.localizedDescription)"
        }
    }

    // MARK: 目录与标签

    @discardableResult
    func addCategory(name: String, iconName: String? = nil) -> LibraryCategory {
        let category = LibraryCategory(
            name: name,
            sortOrder: categories.count,
            iconName: iconName
        )
        try? indexer.upsertCategory(category)
        categories.append(category)
        return category
    }

    func renameCategory(_ id: UUID, to newName: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        var category = categories[index]
        category.name = newName
        categories[index] = category
        try? indexer.upsertCategory(category)
        for documentIndex in documents.indices where documents[documentIndex].categoryID == id {
            persistMetadata(documents[documentIndex])
        }
        scheduleRefresh()
    }

    func deleteCategory(_ id: UUID) {
        try? indexer.deleteCategory(id)
        categories.removeAll { $0.id == id }
        // 删除正在筛选的目录时清空筛选，避免列表悬空为空白。
        if activeCategoryFilter == id {
            activeCategoryFilter = nil
        }
        for index in documents.indices where documents[index].categoryID == id {
            documents[index].categoryID = nil
            persistMetadata(documents[index])
        }
        scheduleRefresh()
    }

    @discardableResult
    func addTag(name: String, colorHex: String = "#808080") -> LibraryTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = tags.first(where: { $0.name == trimmed }) {
            return existing
        }
        let tag = LibraryTag(name: trimmed, colorHex: colorHex)
        try? indexer.upsertTag(tag)
        tags.append(tag)
        return tag
    }

    func renameTag(_ id: UUID, to newName: String) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        var tag = tags[index]
        tag.name = newName
        tags[index] = tag
        try? indexer.upsertTag(tag)
        for documentIndex in documents.indices where documents[documentIndex].tagIDs.contains(id) {
            persistMetadata(documents[documentIndex])
        }
        scheduleRefresh()
    }

    func deleteTag(_ id: UUID) {
        try? indexer.deleteTag(id)
        tags.removeAll { $0.id == id }
        for index in documents.indices where documents[index].tagIDs.contains(id) {
            documents[index].tagIDs.removeAll { $0 == id }
            persistMetadata(documents[index])
        }
        activeTagFilters.removeAll { $0 == id }
        scheduleRefresh()
    }

    /// 为文档追加标签并返回文档是否变化。
    func assignTag(_ tagID: UUID, to documentID: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }),
              !documents[index].tagIDs.contains(tagID)
        else { return }
        documents[index].tagIDs.append(tagID)
        persistMetadata(documents[index])
        scheduleRefresh()
    }

    func removeTag(_ tagID: UUID, from documentID: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }),
              documents[index].tagIDs.contains(tagID)
        else { return }
        documents[index].tagIDs.removeAll { $0 == tagID }
        persistMetadata(documents[index])
        scheduleRefresh()
    }

    func toggleFavorite(_ documentID: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return }
        documents[index].isFavorited.toggle()
        persistMetadata(documents[index])
        scheduleRefresh()
    }

    // MARK: 全文搜索

    /// 触发防抖搜索；空查询清除搜索结果并恢复列表。
    func search(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchState = .idle
            return
        }
        searchState = .searching
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            await self.performSearch(trimmed)
        }
    }

    private func performSearch(_ query: String) async {
        do {
            let rows = try indexer.search(query: query, limit: 200)
            var results: [LibrarySearchResult] = []
            for (rowid, documentID) in rows {
                guard let document = documents.first(where: { $0.id == documentID }) else { continue }
                let snippet = try? indexer.snippet(for: rowid, query: query)
                results.append(
                    LibrarySearchResult(
                        documentID: document.id,
                        title: document.title,
                        snippet: snippet ?? document.summary,
                        categoryID: document.categoryID,
                        tagIDs: document.tagIDs,
                        updatedAt: document.updatedAt,
                        rank: 0
                    )
                )
            }
            searchResults = results
            searchState = results.isEmpty ? .empty : .hasResults
        } catch {
            searchResults = []
            searchState = .failed
            storageMessage = "全文搜索失败：\(error.localizedDescription)"
        }
    }

    /// 记录一次真实打开（“最近打开”视图按此排序）。
    func markOpened(_ id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        var document = documents[index]
        document.lastOpenedAt = Date()
        documents[index] = document
        persistMetadata(document)
        scheduleRefresh()
    }

    /// 清除当前存储错误提示。
    func dismissStorageMessage() {
        storageMessage = nil
    }

    // MARK: 持久化

    private func persist(document: LibraryDocument, attributedString: NSAttributedString) throws {
        try fileManager.save(documentID: document.id, attributedString: attributedString)
        try indexer.withTransaction {
            try indexer.insertDocument(document)
            let tagNames = document.tagIDs.compactMap { id in
                tags.first(where: { $0.id == id })?.name
            }
            let categoryName = document.categoryID.flatMap { id in
                categories.first(where: { $0.id == id })?.name
            } ?? ""
            try indexer.index(
                documentID: document.id,
                title: document.title,
                body: attributedString.string,
                tags: tagNames,
                category: categoryName
            )
        }
        documents.append(document)
    }

    private func persistMetadata(_ document: LibraryDocument, bodyText: String? = nil) {
        do {
            try indexer.withTransaction {
                try indexer.insertDocument(document)
                try indexer.replaceDocumentTags(documentID: document.id, tagIDs: document.tagIDs)
                let body = bodyText ?? fileManager.load(documentID: document.id)?.string ?? ""
                let tagNames = document.tagIDs.compactMap { id in
                    tags.first(where: { $0.id == id })?.name
                }
                let categoryName = document.categoryID.flatMap { id in
                    categories.first(where: { $0.id == id })?.name
                } ?? ""
                try indexer.index(
                    documentID: document.id,
                    title: document.title,
                    body: body,
                    tags: tagNames,
                    category: categoryName
                )
            }
        } catch {
            storageMessage = "保存文档元数据失败：\(error.localizedDescription)"
        }
    }

    /// 启动时修复历史版本遗留的索引不一致：清理孤儿 FTS 行，为缺失索引的文档重建。
    private func repairIndexIfNeeded() {
        do {
            let orphaned = try indexer.purgeOrphanedFTSRows()
            let missing = try indexer.documentsMissingFTSIndex()
            var rebuilt = 0
            for id in missing {
                guard let document = documents.first(where: { $0.id == id }) else { continue }
                let body = fileManager.load(documentID: id)?.string ?? ""
                let tagNames = document.tagIDs.compactMap { tagID in
                    tags.first(where: { $0.id == tagID })?.name
                }
                let categoryName = document.categoryID.flatMap { categoryID in
                    categories.first(where: { $0.id == categoryID })?.name
                } ?? ""
                try? indexer.index(
                    documentID: id,
                    title: document.title,
                    body: body,
                    tags: tagNames,
                    category: categoryName
                )
                rebuilt += 1
            }
            if orphaned > 0 || rebuilt > 0 {
                storageMessage = "已修复资料库全文索引（清理 \(orphaned) 个失效条目，重建 \(rebuilt) 篇文档）。"
            }
        } catch {
            storageMessage = "资料库索引修复失败：\(error.localizedDescription)"
        }
    }

    /// 备份恢复失败时回滚：删除本次创建的文档（文件+索引）与新增的目录、标签。
    func rollbackRestore(documentIDs: [UUID], categoryIDs: Set<UUID>, tagIDs: Set<UUID>) {
        for id in documentIDs {
            try? fileManager.delete(documentID: id)
            try? indexer.deleteDocument(id)
            documents.removeAll { $0.id == id }
            if selectedDocumentID == id {
                selectedDocumentID = nil
            }
        }
        for categoryID in categoryIDs where categories.contains(where: { $0.id == categoryID }) {
            try? indexer.deleteCategory(categoryID)
            categories.removeAll { $0.id == categoryID }
            for index in documents.indices where documents[index].categoryID == categoryID {
                documents[index].categoryID = nil
            }
        }
        for tagID in tagIDs where tags.contains(where: { $0.id == tagID }) {
            try? indexer.deleteTag(tagID)
            tags.removeAll { $0.id == tagID }
            for index in documents.indices {
                documents[index].tagIDs.removeAll { $0 == tagID }
            }
        }
        scheduleRefresh()
    }

    func reloadAll() {
        do {
            categories = try indexer.loadAllCategories()
            tags = try indexer.loadAllTags()
            documents = try indexer.loadAllDocuments()
        } catch {
            storageMessage = "加载资料库失败：\(error.localizedDescription)"
        }
    }

    private func scheduleRefresh() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.reloadAll()
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: 路径

    private static func defaultDatabaseURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(TinyDeskConst.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(TinyDeskConst.libraryDirectoryName, isDirectory: true)
            .appendingPathComponent(TinyDeskConst.libraryDatabaseName, isDirectory: false)
    }

    var defaultPaperTheme: PaperTheme {
        .suJian
    }
}
