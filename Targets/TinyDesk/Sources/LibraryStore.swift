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
        self.fileManager = LibraryFileManager(documentsDirectory: documentsDirectory)

        // 打开失败时退回临时目录的新库，避免资料库整体不可用；
        // 原错误保留在提示中，临时库数据会在下次正常启动时重新从正式库读取。
        do {
            indexer = try FTSIndexer(url: resolvedURL)
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("tinydesk-library-\(UUID().uuidString).db")
            indexer = (try? FTSIndexer(url: fallbackURL)) ?? .unavailable()
            storageMessage = "资料库打开失败：\(error.localizedDescription)"
        }
        reloadAll()
        purgeExpiredTrashIfNeeded()
        isReady = true
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
        activeDocuments.sorted { $0.updatedAt > $1.updatedAt }.prefix(10).map { $0 }
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

    @discardableResult
    func createDocument(
        title: String = "未命名文档",
        attributedString: NSAttributedString = NSAttributedString()
    ) -> LibraryDocument {
        let now = Date()
        let document = LibraryDocument(
            title: title,
            paperTheme: defaultPaperTheme,
            fontPreset: .fangSong,
            createdAt: now,
            updatedAt: now
        )
        persist(document: document, attributedString: attributedString)
        selectedDocumentID = document.id
        return document
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
            try indexer.insertDocument(document)
            let tagNames = tagIDs.compactMap { id in
                tags.first(where: { $0.id == id })?.name
            }
            let categoryName = categoryID.flatMap { id in
                categories.first(where: { $0.id == id })?.name
            } ?? ""
            try indexer.index(
                documentID: document.id,
                title: document.title,
                body: attributedString.string,
                tags: tagNames,
                category: categoryName
            )
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
        persistMetadata(document)
        reindex(document: document)
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
        reindex(document: document)
        scheduleRefresh()
    }

    func loadAttributedString(for id: UUID) -> NSAttributedString? {
        fileManager.load(documentID: id)
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
        scheduleRefresh()
    }

    /// 从回收站永久删除（物理删除文件 + 数据库行）。
    func purgeDocument(_ id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        do {
            try fileManager.delete(documentID: id)
        } catch {
            storageMessage = "删除文档文件失败：\(error.localizedDescription)"
        }
        do {
            try indexer.deleteDocument(id)
        } catch {
            storageMessage = "删除文档索引失败：\(error.localizedDescription)"
        }
        documents.remove(at: index)
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
            for id in expired {
                try? fileManager.delete(documentID: id)
            }
            reloadAll()
        } catch {
            // 清理失败不阻塞启动。
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
        reindexCategoryDocuments(categoryID: id)
        scheduleRefresh()
    }

    func deleteCategory(_ id: UUID) {
        try? indexer.deleteCategory(id)
        categories.removeAll { $0.id == id }
        for index in documents.indices where documents[index].categoryID == id {
            documents[index].categoryID = nil
            persistMetadata(documents[index])
        }
        reindexCategoryDocuments(categoryID: id)
        scheduleRefresh()
    }

    private func reindexCategoryDocuments(categoryID: UUID) {
        for document in documents where document.categoryID == categoryID {
            reindex(document: document)
        }
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
        reindexDocumentsUsingTag(tagID: id)
        scheduleRefresh()
    }

    func deleteTag(_ id: UUID) {
        try? indexer.deleteTag(id)
        tags.removeAll { $0.id == id }
        for index in documents.indices {
            if documents[index].tagIDs.contains(id) {
                documents[index].tagIDs.removeAll { $0 == id }
                persistMetadata(documents[index])
            }
        }
        activeTagFilters.removeAll { $0 == id }
        reindexDocumentsUsingTag(tagID: id)
        scheduleRefresh()
    }

    private func reindexDocumentsUsingTag(tagID: UUID) {
        for document in documents where document.tagIDs.contains(tagID) {
            reindex(document: document)
        }
    }

    /// 为文档追加标签并返回文档是否变化。
    func assignTag(_ tagID: UUID, to documentID: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }),
              !documents[index].tagIDs.contains(tagID)
        else { return }
        documents[index].tagIDs.append(tagID)
        persistMetadata(documents[index])
        reindex(document: documents[index])
        scheduleRefresh()
    }

    func removeTag(_ tagID: UUID, from documentID: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }),
              documents[index].tagIDs.contains(tagID)
        else { return }
        documents[index].tagIDs.removeAll { $0 == tagID }
        persistMetadata(documents[index])
        reindex(document: documents[index])
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
            return
        }
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            await self.performSearch(trimmed)
        }
    }

    private func performSearch(_ query: String) async {
        do {
            let ids = try indexer.searchIDs(query: query, limit: 200)
            var results: [LibrarySearchResult] = []
            for rowid in ids {
                guard let document = document(forRowID: rowid) else { continue }
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
        } catch {
            storageMessage = "全文搜索失败：\(error.localizedDescription)"
        }
    }

    private func document(forRowID rowid: Int64) -> LibraryDocument? {
        // rowid 与 documents 数组顺序不一定一致；直接用数据库行查。
        documents.first {
            guard let documentRowID = try? indexer.fetchRowID(forDocumentID: $0.id) else { return false }
            return documentRowID == rowid
        }
    }

    // MARK: 持久化

    private func persist(document: LibraryDocument, attributedString: NSAttributedString) {
        do {
            try fileManager.save(documentID: document.id, attributedString: attributedString)
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
            documents.append(document)
        } catch {
            storageMessage = "创建文档失败：\(error.localizedDescription)"
        }
    }

    private func persistMetadata(_ document: LibraryDocument) {
        do {
            try indexer.insertDocument(document)
            try indexer.replaceDocumentTags(documentID: document.id, tagIDs: document.tagIDs)
        } catch {
            storageMessage = "保存文档元数据失败：\(error.localizedDescription)"
        }
    }

    private func reindex(document: LibraryDocument) {
        let (body, tagNames, categoryName) = indexText(for: document, attributedString: nil)
        // 从文件读取正文。
        let actualBody: String
        if let attributed = fileManager.load(documentID: document.id) {
            actualBody = attributed.string
        } else {
            actualBody = body
        }
        do {
            try indexer.index(
                documentID: document.id,
                title: document.title,
                body: actualBody,
                tags: tagNames,
                category: categoryName
            )
        } catch {
            storageMessage = "更新文档索引失败：\(error.localizedDescription)"
        }
    }

    private func reloadAll() {
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
