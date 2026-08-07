import AppKit
import Foundation
import TinyDeskCore
import UniformTypeIdentifiers

/// 资料库文档的导入导出与备份包。
@MainActor
enum LibraryImportExport {
    static let markdownContentType = UTType(filenameExtension: "md") ?? .plainText

    static var supportedImportContentTypes: [UTType] {
        [.plainText, .rtf, .rtfd, markdownContentType]
    }

    static var supportedExportContentTypes: [UTType] {
        [.rtf, .rtfd, .plainText, markdownContentType, .pdf]
    }

    /// 把多个文件导入资料库。返回成功导入的文档数。
    /// 任一文件失败都继续处理其余文件，最后汇总失败并抛出错误，
    /// 由调用方决定是否显示结果而不是关闭界面。
    @discardableResult
    static func importFiles(_ urls: [URL], store: LibraryStore) throws -> Int {
        var imported = 0
        var failures: [String] = []
        for url in urls {
            do {
                if let document = try importFile(url, store: store) {
                    imported += 1
                    store.selectedDocumentID = document.id
                }
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            throw LibraryImportExportError.partialImport(imported: imported, failures: failures)
        }
        return imported
    }

    /// 导入单个文件。返回新建的文档；不支持的格式返回 nil 并抛出错误。
    static func importFile(_ url: URL, store: LibraryStore) throws -> LibraryDocument? {
        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let ext = url.pathExtension.lowercased()
        let attributed: NSAttributedString
        switch ext {
        case "rtf":
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? NSAttributedString(
                      data: data,
                      options: [.documentType: NSAttributedString.DocumentType.rtf],
                      documentAttributes: nil
                  )
            else { throw LibraryImportExportError.unsupportedFormat(ext) }
            attributed = decoded
        case "rtfd":
            guard let wrapper = try? FileWrapper(url: url, options: []),
                  let decoded = NSAttributedString(rtfdFileWrapper: wrapper, documentAttributes: nil)
            else { throw LibraryImportExportError.unsupportedFormat(ext) }
            attributed = decoded
        case "txt", "md", "markdown":
            let text = try Self.stringContents(of: url)
            attributed = NSAttributedString(
                string: text,
                attributes: [.font: RichTextDefaults.font(size: 16, preset: .fangSong)]
            )
        default:
            throw LibraryImportExportError.unsupportedFormat(ext)
        }

        // Markdown 提示富文本样式可能丢失。
        if ["md", "markdown"].contains(ext) {
            notifyStyleLoss(for: ext)
        }

        let title = url.deletingPathExtension().lastPathComponent
        guard let document = store.createDocument(title: title, attributedString: attributed) else {
            throw LibraryImportExportError.importFailed(url.lastPathComponent)
        }
        return document
    }

    /// 读取文本文件，依次尝试 UTF-8（含 BOM）、UTF-16、GB18030 等常见中文编码。
    private static func stringContents(of url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        if let text = try? String(contentsOf: url, encoding: .utf16) {
            return text
        }
        let gbEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let text = try? String(contentsOf: url, encoding: gbEncoding) {
            return text
        }
        throw LibraryImportExportError.unreadableText(url.lastPathComponent)
    }

    /// 导出单个文档。按目标文件扩展名选择格式。
    static func export(_ document: LibraryDocument, to url: URL, store: LibraryStore) throws {
        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let attributed = store.loadAttributedString(for: document) else {
            throw LibraryImportExportError.documentMissing
        }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "rtf":
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            try data.write(to: url, options: .atomic)
        case "rtfd":
            let wrapper = try attributed.fileWrapper(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
            try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        case "txt":
            guard let data = attributed.string.data(using: .utf8) else {
                throw LibraryImportExportError.encodingFailed
            }
            try data.write(to: url, options: .atomic)
        case "md", "markdown":
            notifyStyleLoss(for: ext)
            let md = markdown(from: attributed)
            guard let data = md.data(using: .utf8) else {
                throw LibraryImportExportError.encodingFailed
            }
            try data.write(to: url, options: .atomic)
        case "pdf":
            let data = try LibraryPDFRenderer.render(
                attributedString: attributed,
                paperTheme: document.paperTheme
            )
            try data.write(to: url, options: .atomic)
        default:
            throw LibraryImportExportError.unsupportedFormat(ext)
        }
    }

    /// 导出整个资料库为备份 ZIP。
    static func exportBackup(store: LibraryStore, to url: URL) throws {
        let data = try LibraryBackup.createArchive(
            categories: store.categories,
            tags: store.tags,
            documents: store.documents,
            fileManager: LibraryFileManager(documentsDirectory: backupDocumentsDirectory(for: store))
        )
        try data.write(to: url, options: .atomic)
    }

    /// 从备份 ZIP 恢复资料库。返回恢复的文档数量。
    /// 先完成全部校验（元数据、正文可解码、路径安全），再按内存映射写入；
    /// 任何一步失败都回滚本次恢复产生的目录、标签、文档与索引。
    @discardableResult
    static func importBackup(from url: URL, store: LibraryStore) throws -> Int {
        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        let (bundle, bodies) = try LibraryBackup.extractArchive(
            data: data,
            fileManager: LibraryFileManager(documentsDirectory: backupDocumentsDirectory(for: store))
        )

        // 预校验：全部正文必须可解码，否则整体失败。
        var decodedBodies: [UUID: (attributed: NSAttributedString, wrapper: FileWrapper?)] = [:]
        for document in bundle.documents {
            guard let body = bodies[document.id] else {
                throw LibraryImportExportError.missingBody(document.id)
            }
            if let wrapper = body.rtfdFileWrapper {
                guard let attributed = NSAttributedString(
                    rtfdFileWrapper: wrapper,
                    documentAttributes: nil
                ) else {
                    throw LibraryImportExportError.undecodableBody(document.id)
                }
                decodedBodies[document.id] = (attributed, wrapper)
            } else if let rtf = body.legacyRTFData {
                guard let attributed = try? NSAttributedString(
                    data: rtf,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                ) else {
                    throw LibraryImportExportError.undecodableBody(document.id)
                }
                decodedBodies[document.id] = (attributed, nil)
            } else {
                throw LibraryImportExportError.missingBody(document.id)
            }
        }

        // 目录/标签按名称复用已有项；回滚时只能删除本次创建的对象，
        // 绝不允许删除复用（原本就存在）的目录或标签。
        var createdCategoryIDs: Set<UUID> = []
        let categoryIDs: [UUID: UUID] = Dictionary(
            uniqueKeysWithValues: bundle.categories.compactMap { category in
                if let existing = store.categories.first(where: { $0.name == category.name }) {
                    return (category.id, existing.id)
                }
                let created = store.addCategory(name: category.name, iconName: category.iconName)
                createdCategoryIDs.insert(created.id)
                return (category.id, created.id)
            }
        )
        var createdTagIDs: Set<UUID> = []
        var tagIDs: [UUID: UUID] = [:]
        for tag in bundle.tags {
            if let existing = store.tags.first(where: { $0.name == tag.name }) {
                tagIDs[tag.id] = existing.id
                continue
            }
            guard let restored = store.addTag(name: tag.name, colorHex: tag.colorHex) else { continue }
            createdTagIDs.insert(restored.id)
            tagIDs[tag.id] = restored.id
        }

        var createdDocumentIDs: [UUID] = []
        var restored = 0
        do {
            for document in bundle.documents {
                guard let decoded = decodedBodies[document.id] else {
                    throw LibraryImportExportError.missingBody(document.id)
                }
                let references = LibraryRestoreReferenceMapping.remap(
                    categoryID: document.categoryID,
                    tagIDs: document.tagIDs,
                    categoryIDs: categoryIDs,
                    tagIDsBySourceID: tagIDs
                )
                let restoredDocument = try store.restoreDocument(
                    from: document,
                    categoryID: references.categoryID,
                    tagIDs: references.tagIDs,
                    attributedString: decoded.attributed,
                    rtfdFileWrapper: decoded.wrapper
                )
                createdDocumentIDs.append(restoredDocument.id)
                restored += 1
            }
        } catch {
            store.rollbackRestore(
                documentIDs: createdDocumentIDs,
                categoryIDs: createdCategoryIDs,
                tagIDs: createdTagIDs
            )
            throw error
        }

        store.reloadAll()
        return restored
    }

    // MARK: - 私有

    private static func backupDocumentsDirectory(for store: LibraryStore) -> URL {
        store.databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent(TinyDeskConst.libraryDocumentsDirectoryName, isDirectory: true)
    }

    private static func markdown(from attributed: NSAttributedString) -> String {
        // 最小 Markdown 转换：正文 + 换行，标题与样式不转换。
        // 避免承诺格式无损，UI 层已提示。
        attributed.string
    }

    private static func notifyStyleLoss(for ext: String) {
        let message = ext == "docx"
            ? "DOCX 导入导出可能丢失部分富文本样式，建议使用 RTF 保存复杂文档。"
            : "Markdown 导入导出可能丢失富文本样式，建议使用 RTF 或 PDF 保存复杂文档。"
        let alert = NSAlert()
        alert.messageText = "格式提示"
        alert.informativeText = message
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}

/// 资料库导入导出错误。
enum LibraryImportExportError: LocalizedError {
    case unsupportedFormat(String)
    case documentMissing
    case unreadableText(String)
    case encodingFailed
    case missingBody(UUID)
    case undecodableBody(UUID)
    case importFailed(String)
    case partialImport(imported: Int, failures: [String])

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(ext):
            return "不支持的文件格式：.\(ext)"
        case .documentMissing:
            return "找不到文档正文。"
        case let .unreadableText(name):
            return "无法识别文本编码（\(name)）。"
        case .encodingFailed:
            return "文本编码失败。"
        case let .missingBody(id):
            return "备份包缺少文档正文（\(id.uuidString)）。"
        case let .undecodableBody(id):
            return "备份包中的文档正文无法读取（\(id.uuidString)）。"
        case let .importFailed(name):
            return "导入失败（\(name)）。"
        case let .partialImport(imported, failures):
            let detail = failures.prefix(3).joined(separator: "\n")
            return "成功导入 \(imported) 个，失败 \(failures.count) 个：\n\(detail)"
        }
    }
}

/// 导出/备份前通知编辑器同步保存未落盘的正文。
enum LibraryExportWillBeginNotification {
    static let name = Notification.Name("TinyDeskLibraryExportWillBegin")
    static func post() {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
