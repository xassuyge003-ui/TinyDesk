import Foundation
import SQLite3

// MARK: - SQLite 错误

/// 资料库 SQLite 操作错误。
public enum LibraryStorageError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case notOpen

    public var errorDescription: String? {
        switch self {
        case let .openFailed(message): return "无法打开资料库：\(message)"
        case let .prepareFailed(message): return "无法准备资料库语句：\(message)"
        case let .stepFailed(message): return "资料库操作失败：\(message)"
        case let .bindFailed(message): return "资料库参数绑定失败：\(message)"
        case .notOpen: return "资料库尚未打开。"
        }
    }
}

// MARK: - FTS 索引器

/// SQLite FTS5 全文索引的 Swift 封装。
///
/// 在 `TinyDeskCore` 中持有对 `libsqlite3` 的 C 接口调用，保持纯 Foundation 依赖。
/// 一个实例负责一个数据库文件，提供资料库建表、索引同步与全文搜索。
public final class FTSIndexer: @unchecked Sendable {
    /// 日期写入 SQLite 使用的 ISO8601 编码。
    public static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        return formatter
    }()

    private var db: OpaquePointer?
    private var transactionDepth = 0

    /// 打开（或创建）位于 `url` 的数据库，并迁移到最新 schema。
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw LibraryStorageError.openFailed(String(cString: sqlite3_errmsg(handle)))
        }
        db = handle
        try migrate()
    }

    /// 构造一个未打开数据库的兜底实例；任何数据库操作都会抛 `notOpen`。
    /// 用于极端初始化失败路径，保证上层不崩溃。
    public static func unavailable() -> FTSIndexer {
        FTSIndexer(db: nil)
    }

    private init(db: OpaquePointer?) {
        self.db = db
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Schema 迁移

    private static let schemaVersion = 1

    private func migrate() throws {
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try execute("PRAGMA user_version=\(Self.schemaVersion);")

        try execute("""
        CREATE TABLE IF NOT EXISTS categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            icon_name TEXT,
            created_at TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS tags (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            color_hex TEXT NOT NULL DEFAULT '#808080',
            created_at TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS documents (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL DEFAULT '未命名文档',
            category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
            is_favorited INTEGER NOT NULL DEFAULT 0,
            paper_theme TEXT NOT NULL DEFAULT 'suJian',
            font_preset TEXT NOT NULL DEFAULT 'fangSong',
            word_count INTEGER NOT NULL DEFAULT 0,
            summary TEXT NOT NULL DEFAULT '',
            custom_cover_color_hex TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT
        );
        """)
        // 旧库补充 last_opened_at 列；已存在时忽略错误。
        try? execute("ALTER TABLE documents ADD COLUMN last_opened_at TEXT;")
        try execute("""
        CREATE TABLE IF NOT EXISTS document_tags (
            document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
            PRIMARY KEY (document_id, tag_id)
        );
        """)
        try execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
            title,
            body,
            tags,
            category,
            tokenize='unicode61 remove_diacritics 2'
        );
        """)
        // FTS 行由 Swift 侧统一维护：插入 documents 时写入占位行，
        // index() 覆盖正文等，deleteDocument() 先删 FTS 行。
    }

    // MARK: - 索引写入

    /// 更新某文档的标题、正文、标签名与目录名索引。正文为空时清空对应词条。
    /// 普通 FTS5 表内部存储词条，用 INSERT OR REPLACE 覆盖。
    public func index(
        documentID: UUID,
        title: String,
        body: String,
        tags: [String],
        category: String
    ) throws {
        guard let db else { throw LibraryStorageError.notOpen }
        guard let rowid = try fetchRowID(forDocumentID: documentID) else { return }
        let body = body.replacingOccurrences(of: "\0", with: "")

        let statement = try prepare(
            in: db,
            """
            INSERT OR REPLACE INTO documents_fts(rowid, title, body, tags, category)
            VALUES (?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(statement, index: 1, int: rowid)
        try bind(statement, index: 2, text: Self.segmentedForFTS(title))
        try bind(statement, index: 3, text: Self.segmentedForFTS(body))
        try bind(statement, index: 4, text: Self.segmentedForFTS(tags.joined(separator: " ")))
        try bind(statement, index: 5, text: Self.segmentedForFTS(category))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryStorageError.stepFailed(lastErrorMessage(db))
        }
    }

    // MARK: - 全文搜索

    /// 在标题、正文、标签、目录中搜索 `query`，按 bm25 相关度排序。
    /// 返回行 id 列表；调用方结合 documents 表解析元数据。
    public func searchIDs(query: String, limit: Int = 200) throws -> [Int64] {
        guard let db else { throw LibraryStorageError.notOpen }
        guard !query.isEmpty else { return [] }

        // 分词后构造 MATCH：每个词用双引号包裹。纯标点输入会得到空词条，直接返回空结果。
        let terms = Self.segmentedForFTS(query)
            .split(separator: " ")
            .map { "\"\($0)\"" }
            .joined(separator: " ")
        guard !terms.isEmpty else { return [] }

        let statement = try prepare(
            in: db,
            """
            SELECT rowid FROM documents_fts
            WHERE documents_fts MATCH ?
            ORDER BY bm25(documents_fts)
            LIMIT ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(statement, index: 1, text: terms)
        try bind(statement, index: 2, int: Int64(limit))

        var ids: [Int64] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW {
                ids.append(sqlite3_column_int64(statement, 0))
            } else if code == SQLITE_DONE {
                break
            } else {
                throw LibraryStorageError.stepFailed(lastErrorMessage(db))
            }
        }
        return ids
    }

    /// 搜索并一次性关联文档 ID（JOIN documents），避免调用方逐条反查 rowid。
    public func search(query: String, limit: Int = 200) throws -> [(rowid: Int64, documentID: UUID)] {
        guard let db else { throw LibraryStorageError.notOpen }
        guard !query.isEmpty else { return [] }

        let terms = Self.segmentedForFTS(query)
            .split(separator: " ")
            .map { "\"\($0)\"" }
            .joined(separator: " ")
        guard !terms.isEmpty else { return [] }

        let statement = try prepare(
            in: db,
            """
            SELECT f.rowid, d.id
            FROM (SELECT rowid FROM documents_fts WHERE documents_fts MATCH ? ORDER BY bm25(documents_fts) LIMIT ?) f
            JOIN documents d ON d.rowid = f.rowid;
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(statement, index: 1, text: terms)
        try bind(statement, index: 2, int: Int64(limit))

        var results: [(rowid: Int64, documentID: UUID)] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW {
                let rowid = sqlite3_column_int64(statement, 0)
                if let raw = sqlite3_column_text(statement, 1),
                   let uuid = UUID(uuidString: String(cString: raw)) {
                    results.append((rowid, uuid))
                }
            } else if code == SQLITE_DONE {
                break
            } else {
                throw LibraryStorageError.stepFailed(lastErrorMessage(db))
            }
        }
        return results
    }

    /// 取某文档在当前查询下命中的 snippet（带 <b> 高亮标记）。
    /// 优先取 body 列（索引 1）片段，body 无命中时回退到 title 列（索引 0）。
    public func snippet(
        for rowid: Int64,
        query: String
    ) throws -> String? {
        guard let db else { throw LibraryStorageError.notOpen }
        let terms = Self.segmentedForFTS(query)
            .split(separator: " ")
            .map { "\"\($0)\"" }
            .joined(separator: " ")
        guard !terms.isEmpty else { return nil }

        for column in [1, 0] {
            let statement = try prepare(
                in: db,
                """
                SELECT snippet(documents_fts, \(column), '<b>', '</b>', '…', 12)
                FROM documents_fts
                WHERE documents_fts MATCH ? AND rowid = ?;
                """
            )
            defer { sqlite3_finalize(statement) }

            try bind(statement, index: 1, text: terms)
            try bind(statement, index: 2, int: rowid)

            if sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) {
                let value = String(cString: raw)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    // MARK: - 元数据表

    public func fetchRowID(forDocumentID documentID: UUID) throws -> Int64? {
        guard let db else { throw LibraryStorageError.notOpen }
        let statement = try prepare(
            in: db,
            "SELECT rowid FROM documents WHERE id = ?;"
        )
        defer { sqlite3_finalize(statement) }

        try bind(statement, index: 1, text: documentID.uuidString)

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    public func insertDocument(_ document: LibraryDocument) throws {
        guard let db else { throw LibraryStorageError.notOpen }
        // 使用 UPSERT 保留既有 rowid：REPLACE 会先删旧行再插新行，
        // 改变 rowid 并级联清空 document_tags，还会让旧 rowid 的 FTS 行成为孤儿。
        let statement = try prepare(
            in: db,
            """
            INSERT INTO documents (
                id, title, category_id, is_favorited, paper_theme, font_preset,
                word_count, summary, custom_cover_color_hex, created_at, updated_at, deleted_at, last_opened_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                category_id = excluded.category_id,
                is_favorited = excluded.is_favorited,
                paper_theme = excluded.paper_theme,
                font_preset = excluded.font_preset,
                word_count = excluded.word_count,
                summary = excluded.summary,
                custom_cover_color_hex = excluded.custom_cover_color_hex,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                last_opened_at = excluded.last_opened_at;
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(statement, index: 1, text: document.id.uuidString)
        try bind(statement, index: 2, text: document.title)
        try bind(statement, index: 3, optionalText: document.categoryID?.uuidString)
        try bind(statement, index: 4, int: document.isFavorited ? 1 : 0)
        try bind(statement, index: 5, text: document.paperTheme.rawValue)
        try bind(statement, index: 6, text: document.fontPreset.rawValue)
        try bind(statement, index: 7, int: Int64(document.wordCount))
        try bind(statement, index: 8, text: document.summary)
        try bind(statement, index: 9, optionalText: document.customCoverColorHex)
        try bind(statement, index: 10, text: Self.dateFormatter.string(from: document.createdAt))
        try bind(statement, index: 11, text: Self.dateFormatter.string(from: document.updatedAt))
        try bind(statement, index: 12, optionalText: document.deletedAt.map(Self.dateFormatter.string(from:)))
        try bind(statement, index: 13, optionalText: document.lastOpenedAt.map(Self.dateFormatter.string(from:)))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryStorageError.stepFailed(lastErrorMessage(db))
        }

        // 写入 FTS 占位行（标题已分割），正文由 index() 覆盖。
        // 不能用 sqlite3_last_insert_rowid：UPSERT 冲突更新是 UPDATE，
        // last_insert_rowid 不会刷新（会残留 document_tags 等表的旧值），
        // 导致占位行写错 rowid、覆盖其他文档的 FTS 行。
        guard let rowid = try fetchRowID(forDocumentID: document.id) else {
            throw LibraryStorageError.stepFailed("documents 行写入后无法取得 rowid")
        }
        let fts = try prepare(
            in: db,
            "INSERT OR REPLACE INTO documents_fts(rowid, title, body, tags, category) VALUES (?, ?, '', '', '');"
        )
        defer { sqlite3_finalize(fts) }
        try bind(fts, index: 1, int: rowid)
        try bind(fts, index: 2, text: Self.segmentedForFTS(document.title))
        guard sqlite3_step(fts) == SQLITE_DONE else {
            throw LibraryStorageError.stepFailed(lastErrorMessage(db))
        }
    }

    // MARK: - 事务

    /// 在单个 SQLite 事务内执行一组写入，保证元数据、标签关系和 FTS 行的一致性。
    /// 失败时回滚全部写入；支持嵌套调用。
    public func withTransaction<T>(_ body: () throws -> T) throws -> T {
        transactionDepth += 1
        let isOuter = transactionDepth == 1
        if isOuter {
            do {
                try execute("BEGIN IMMEDIATE;")
            } catch {
                transactionDepth -= 1
                throw error
            }
        }
        defer {
            if isOuter {
                transactionDepth = 0
            }
        }

        do {
            let value = try body()
            if isOuter {
                try execute("COMMIT;")
            }
            return value
        } catch {
            if isOuter {
                do {
                    try execute("ROLLBACK;")
                } catch {
                    // 回滚失败保留原错误
                }
            }
            throw error
        }
    }

    /// 删除 FTS 中已无 documents 行对应的孤儿词条，返回清理数量。
    public func purgeOrphanedFTSRows() throws -> Int {
        guard let db else { throw LibraryStorageError.notOpen }
        let statement = try prepare(
            in: db,
            "DELETE FROM documents_fts WHERE rowid NOT IN (SELECT rowid FROM documents);"
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryStorageError.stepFailed(lastErrorMessage(db))
        }
        return Int(sqlite3_changes(db))
    }

    /// 返回缺少 FTS 索引行的文档 ID（例如历史版本 REPLACE 后遗留）。
    public func documentsMissingFTSIndex() throws -> [UUID] {
        guard let db else { throw LibraryStorageError.notOpen }
        let statement = try prepare(
            in: db,
            "SELECT id FROM documents WHERE rowid NOT IN (SELECT rowid FROM documents_fts);"
        )
        defer { sqlite3_finalize(statement) }

        var ids: [UUID] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) {
                if let uuid = UUID(uuidString: String(cString: raw)) {
                    ids.append(uuid)
                }
            } else if code == SQLITE_DONE {
                break
            } else {
                throw LibraryStorageError.stepFailed(lastErrorMessage(db))
            }
        }
        return ids
    }

    public func replaceDocumentTags(documentID: UUID, tagIDs: [UUID]) throws {
        guard let db else { throw LibraryStorageError.notOpen }

        try execute("DELETE FROM document_tags WHERE document_id = '\(documentID.uuidString)';")
        for tagID in tagIDs {
            let statement = try prepare(
                in: db,
                "INSERT OR IGNORE INTO document_tags (document_id, tag_id) VALUES (?, ?);"
            )
            defer { sqlite3_finalize(statement) }
            try bind(statement, index: 1, text: documentID.uuidString)
            try bind(statement, index: 2, text: tagID.uuidString)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LibraryStorageError.stepFailed(lastErrorMessage(db))
            }
        }
    }

    public func deleteDocument(_ documentID: UUID) throws {
        guard let db else { throw LibraryStorageError.notOpen }

        // 先删 FTS 词条，再删 documents 行，避免 content='' 表残留。
        if let rowid = try fetchRowID(forDocumentID: documentID) {
            let fts = try prepare(in: db, "DELETE FROM documents_fts WHERE rowid = ?;")
            defer { sqlite3_finalize(fts) }
            try bind(fts, index: 1, int: rowid)
            guard sqlite3_step(fts) == SQLITE_DONE else {
                throw LibraryStorageError.stepFailed(lastErrorMessage(db))
            }
        }

        let statement = try prepare(in: db, "DELETE FROM documents WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        try bind(statement, index: 1, text: documentID.uuidString)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryStorageError.stepFailed(lastErrorMessage(db))
        }
    }

    public func purgeExpiredTrash(before cutoffDate: Date) throws -> [UUID] {
        guard let db else { throw LibraryStorageError.notOpen }
        let cutoff = Self.dateFormatter.string(from: cutoffDate)
        let statement = try prepare(
            in: db,
            "SELECT id FROM documents WHERE deleted_at IS NOT NULL AND deleted_at < ?;"
        )
        defer { sqlite3_finalize(statement) }
        try bind(statement, index: 1, text: cutoff)

        var ids: [UUID] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) {
                let id = String(cString: raw)
                if let uuid = UUID(uuidString: id) {
                    ids.append(uuid)
                }
            } else if code == SQLITE_DONE {
                break
            } else {
                throw LibraryStorageError.stepFailed(lastErrorMessage(db))
            }
        }
        for id in ids {
            try deleteDocument(id)
        }
        return ids
    }

    // MARK: - 查询

    /// 读取所有文档（含回收站）。正文不在此读取。
    public func loadAllDocuments() throws -> [LibraryDocument] {
        guard let db else { throw LibraryStorageError.notOpen }
        let statement = try prepare(
            in: db,
            """
            SELECT d.id, d.title, d.category_id, d.is_favorited, d.paper_theme, d.font_preset,
                   d.word_count, d.summary, d.custom_cover_color_hex, d.created_at, d.updated_at, d.deleted_at,
                   GROUP_CONCAT(dt.tag_id, ',') AS tag_ids, d.last_opened_at
            FROM documents d
            LEFT JOIN document_tags dt ON dt.document_id = d.id
            GROUP BY d.id
            ORDER BY d.updated_at DESC;
            """
        )
        defer { sqlite3_finalize(statement) }

        var results: [LibraryDocument] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW {
                if let document = readDocumentRow(statement) {
                    results.append(document)
                }
            } else if code == SQLITE_DONE {
                break
            } else {
                throw LibraryStorageError.stepFailed(lastErrorMessage(db))
            }
        }
        return results
    }

    public func loadAllCategories() throws -> [LibraryCategory] {
        guard let db else { throw LibraryStorageError.notOpen }
        let statement = try prepare(
            in: db,
            "SELECT id, name, sort_order, icon_name, created_at FROM categories ORDER BY sort_order, name;"
        )
        defer { sqlite3_finalize(statement) }

        var results: [LibraryCategory] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW {
                guard let rawID = sqlite3_column_text(statement, 0),
                      let id = UUID(uuidString: String(cString: rawID))
                else { continue }
                let name = String(cString: sqlite3_column_text(statement, 1))
                let sortOrder = Int(sqlite3_column_int64(statement, 2))
                let iconName = sqlite3_column_text(statement, 3).map { String(cString: $0) }
                let createdAt = Self.date(from: sqlite3_column_text(statement, 4).map { String(cString: $0) }) ?? Date()
                results.append(
                    LibraryCategory(
                        id: id,
                        name: name,
                        sortOrder: sortOrder,
                        iconName: iconName,
                        createdAt: createdAt
                    )
                )
            } else if code == SQLITE_DONE {
                break
            } else {
                throw LibraryStorageError.stepFailed(lastErrorMessage(db))
            }
        }
        return results
    }

    public func loadAllTags() throws -> [LibraryTag] {
        guard let db else { throw LibraryStorageError.notOpen }
        let statement = try prepare(
            in: db,
            "SELECT id, name, color_hex, created_at FROM tags ORDER BY name;"
        )
        defer { sqlite3_finalize(statement) }

        var results: [LibraryTag] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW {
                guard let rawID = sqlite3_column_text(statement, 0),
                      let id = UUID(uuidString: String(cString: rawID))
                else { continue }
                let name = String(cString: sqlite3_column_text(statement, 1))
                let colorHex = String(cString: sqlite3_column_text(statement, 2))
                let createdAt = Self.date(from: sqlite3_column_text(statement, 3).map { String(cString: $0) }) ?? Date()
                results.append(
                    LibraryTag(id: id, name: name, colorHex: colorHex, createdAt: createdAt)
                )
            } else if code == SQLITE_DONE {
                break
            } else {
                throw LibraryStorageError.stepFailed(lastErrorMessage(db))
            }
        }
        return results
    }

    public func upsertCategory(_ category: LibraryCategory) throws {
        guard let db else { throw LibraryStorageError.notOpen }
        let statement = try prepare(
            in: db,
            """
            INSERT OR REPLACE INTO categories (id, name, sort_order, icon_name, created_at)
            VALUES (?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(statement, index: 1, text: category.id.uuidString)
        try bind(statement, index: 2, text: category.name)
        try bind(statement, index: 3, int: Int64(category.sortOrder))
        try bind(statement, index: 4, optionalText: category.iconName)
        try bind(statement, index: 5, text: Self.dateFormatter.string(from: category.createdAt))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryStorageError.stepFailed(lastErrorMessage(db))
        }
    }

    public func deleteCategory(_ id: UUID) throws {
        try execute("DELETE FROM categories WHERE id = '\(id.uuidString)';")
    }

    public func upsertTag(_ tag: LibraryTag) throws {
        guard let db else { throw LibraryStorageError.notOpen }
        let statement = try prepare(
            in: db,
            "INSERT OR REPLACE INTO tags (id, name, color_hex, created_at) VALUES (?, ?, ?, ?);"
        )
        defer { sqlite3_finalize(statement) }
        try bind(statement, index: 1, text: tag.id.uuidString)
        try bind(statement, index: 2, text: tag.name)
        try bind(statement, index: 3, text: tag.colorHex)
        try bind(statement, index: 4, text: Self.dateFormatter.string(from: tag.createdAt))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryStorageError.stepFailed(lastErrorMessage(db))
        }
    }

    public func deleteTag(_ id: UUID) throws {
        try execute("DELETE FROM tags WHERE id = '\(id.uuidString)';")
    }

    // MARK: - 内部工具

    private func readDocumentRow(_ statement: OpaquePointer) -> LibraryDocument? {
        func text(_ index: Int32) -> String? {
            sqlite3_column_text(statement, index).map { String(cString: $0) }
        }
        func int(_ index: Int32) -> Int64 {
            sqlite3_column_int64(statement, index)
        }

        guard let rawID = text(0), let id = UUID(uuidString: rawID) else { return nil }
        let tagIDs = (text(12) ?? "")
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }

        return LibraryDocument(
            id: id,
            title: text(1) ?? "未命名文档",
            categoryID: text(2).flatMap(UUID.init(uuidString:)),
            isFavorited: int(3) != 0,
            paperTheme: PaperTheme(rawValue: text(4) ?? "") ?? .suJian,
            fontPreset: FontPreset(rawValue: text(5) ?? "") ?? .fangSong,
            wordCount: Int(int(6)),
            summary: text(7) ?? "",
            customCoverColorHex: text(8),
            createdAt: Self.date(from: text(9)) ?? Date(),
            updatedAt: Self.date(from: text(10)) ?? Date(),
            deletedAt: text(11).flatMap { Self.date(from: $0) },
            lastOpenedAt: text(13).flatMap { Self.date(from: $0) }
        ).withTagIDs(tagIDs)
    }

    private func execute(_ sql: String) throws {
        guard let db else { throw LibraryStorageError.notOpen }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(db, sql, nil, nil, &errorPointer)
        if code != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) }
                ?? lastErrorMessage(db)
            sqlite3_free(errorPointer)
            throw LibraryStorageError.stepFailed(message)
        }
    }

    private func prepare(in db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryStorageError.prepareFailed(lastErrorMessage(db))
        }
        return statement
    }

    private func bind(_ statement: OpaquePointer, index: Int32, text: String) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, index, text, -1, transient) == SQLITE_OK else {
            throw LibraryStorageError.bindFailed("参数 \(index) 文本绑定失败")
        }
    }

    private func bind(_ statement: OpaquePointer, index: Int32, optionalText: String?) throws {
        if let optionalText {
            try bind(statement, index: index, text: optionalText)
        } else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw LibraryStorageError.bindFailed("参数 \(index) 空值绑定失败")
            }
        }
    }

    private func bind(_ statement: OpaquePointer, index: Int32, int: Int64) throws {
        guard sqlite3_bind_int64(statement, index, int) == SQLITE_OK else {
            throw LibraryStorageError.bindFailed("参数 \(index) 整数绑定失败")
        }
    }

    private func lastErrorMessage(_ db: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(db))
    }

    /// 把 CJK 连续文本切分为单字并保留英文单词，使 FTS5 unicode61
    /// 分词器可以对中文按单字建立索引。CJK 单字之间用空格分隔，
    /// 英文/数字原样保留，非索引字符丢弃。
    static func segmentedForFTS(_ text: String) -> String {
        var segments: [String] = []
        var latinBuffer = ""

        func flushLatin() {
            if !latinBuffer.isEmpty {
                segments.append(latinBuffer)
                latinBuffer = ""
            }
        }

        for scalar in text.unicodeScalars {
            switch CharacterSet.cjkSegmentable.contains(scalar) {
            case true:
                flushLatin()
                segments.append(String(scalar))
            case false:
                if CharacterSet.alphanumerics.contains(scalar) {
                    latinBuffer.append(String(scalar))
                } else {
                    flushLatin()
                }
            }
        }
        flushLatin()
        return segments.joined(separator: " ")
    }

    private static func date(from raw: UnsafePointer<CChar>?) -> Date? {
        guard let raw else { return nil }
        return dateFormatter.date(from: String(cString: raw))
    }
}

// MARK: - LibraryDocument + tagIDs 回填

private extension LibraryDocument {
    func withTagIDs(_ tagIDs: [UUID]) -> LibraryDocument {
        var copy = self
        copy.tagIDs = tagIDs
        return copy
    }
}

// MARK: - CJK 分词辅助

private extension CharacterSet {
    /// 需要按单字分割的 CJK 相关码位。覆盖基本汉字、扩展区、
    /// 部首、兼容表意文字、平假名/片假名与谚文。
    static let cjkSegmentable = CharacterSet(
        charactersIn: UnicodeScalar(0x2E80)!...UnicodeScalar(0x9FFF)!
    ).union(
        CharacterSet(charactersIn: UnicodeScalar(0xF900)!...UnicodeScalar(0xFAFF)!)
    ).union(
        CharacterSet(charactersIn: UnicodeScalar(0x3000)!...UnicodeScalar(0x303F)!)
    ).union(
        CharacterSet(charactersIn: UnicodeScalar(0x3040)!...UnicodeScalar(0x30FF)!)
    ).union(
        CharacterSet(charactersIn: UnicodeScalar(0xAC00)!...UnicodeScalar(0xD7AF)!)
    )
}
