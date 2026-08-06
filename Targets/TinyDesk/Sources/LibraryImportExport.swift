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
    @discardableResult
    static func importFiles(_ urls: [URL], store: LibraryStore) throws -> Int {
        var imported = 0
        for url in urls {
            if let document = try importFile(url, store: store) {
                imported += 1
                store.selectedDocumentID = document.id
            }
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
            let text = try String(contentsOf: url, encoding: .utf8)
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
        return store.createDocument(title: title, attributedString: attributed)
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
            try data.write(to: url)
        case "rtfd":
            let wrapper = try attributed.fileWrapper(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
            try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        case "txt":
            try attributed.string.data(using: .utf8)?.write(to: url)
        case "md", "markdown":
            notifyStyleLoss(for: ext)
            let md = markdown(from: attributed)
            try md.data(using: .utf8)?.write(to: url)
        case "pdf":
            let data = try LibraryPDFRenderer.render(
                attributedString: attributed,
                paperTheme: document.paperTheme
            )
            try data.write(to: url)
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
        try data.write(to: url)
    }

    /// 从备份 ZIP 恢复资料库。返回恢复的文档数量。
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

        // 目录与标签均在本地重新分配 ID，随后映射文档引用，避免与现有库冲突。
        var categoryIDs: [UUID: UUID] = [:]
        for category in bundle.categories {
            let restored = store.addCategory(name: category.name, iconName: category.iconName)
            categoryIDs[category.id] = restored.id
        }
        var tagIDs: [UUID: UUID] = [:]
        for tag in bundle.tags {
            if let restored = store.addTag(name: tag.name, colorHex: tag.colorHex) {
                tagIDs[tag.id] = restored.id
            }
        }

        // 文档正文
        var restored = 0
        for document in bundle.documents {
            guard let body = bodies[document.id] else { continue }
            let references = LibraryRestoreReferenceMapping.remap(
                categoryID: document.categoryID,
                tagIDs: document.tagIDs,
                categoryIDs: categoryIDs,
                tagIDsBySourceID: tagIDs
            )
            if let wrapper = body.rtfdFileWrapper {
                var attributes: NSDictionary?
                guard let attributed = NSAttributedString(
                    rtfdFileWrapper: wrapper,
                    documentAttributes: &attributes
                ) else { continue }
                try store.restoreDocument(
                    from: document,
                    categoryID: references.categoryID,
                    tagIDs: references.tagIDs,
                    attributedString: attributed,
                    rtfdFileWrapper: wrapper
                )
            } else if let rtf = body.legacyRTFData,
                      let attributed = try? NSAttributedString(
                          data: rtf,
                          options: [.documentType: NSAttributedString.DocumentType.rtf],
                          documentAttributes: nil
                      ) {
                try store.restoreDocument(
                    from: document,
                    categoryID: references.categoryID,
                    tagIDs: references.tagIDs,
                    attributedString: attributed
                )
            } else {
                continue
            }
            restored += 1
        }
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

/// 导入导出错误。
enum LibraryImportExportError: LocalizedError {
    case unsupportedFormat(String)
    case documentMissing

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(ext):
            return "不支持的文件格式：.\(ext)"
        case .documentMissing:
            return "找不到文档正文。"
        }
    }
}
