import AppKit
import Foundation
import TinyDeskCore

/// 资料库文档正文的 RTFD 文件读写。
///
/// 每个文档对应 `<documents>/<uuid>.rtfd` 文件包（目录），内部包含 TXT.rtf
/// 与嵌入图片附件，Apple 生态可直接识别。正文以 NSAttributedString 往返，
/// 保证粗体、斜体、颜色、下划线、图片等格式可完整保留。
struct LibraryFileManager {
    let documentsDirectory: URL

    init(documentsDirectory: URL) {
        self.documentsDirectory = documentsDirectory
    }

    /// 文档正文文件包的 URL。
    func fileURL(forDocumentID id: UUID) -> URL {
        documentsDirectory
            .appendingPathComponent(id.uuidString, isDirectory: false)
            .appendingPathExtension("rtfd")
    }

    /// 保存文档正文为 RTFD 文件包。空文本仍写入，保证文件与元数据始终成对。
    @discardableResult
    func save(documentID: UUID, attributedString: NSAttributedString) throws -> URL {
        try FileManager.default.createDirectory(
            at: documentsDirectory,
            withIntermediateDirectories: true
        )

        let url = fileURL(forDocumentID: documentID)
        let attributes: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtfd,
        ]
        let wrapper: FileWrapper
        do {
            wrapper = try attributedString.fileWrapper(
                from: NSRange(location: 0, length: attributedString.length),
                documentAttributes: attributes
            )
        } catch {
            throw LibraryFileError.rtfdEncodingFailed
        }
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        return url
    }

    /// 直接保存已验证的 RTFD 文件包（资料库备份恢复用）。
    ///
    /// 不能先转成 RTF 数据，否则包内的附件会丢失。
    @discardableResult
    func save(documentID: UUID, rtfdFileWrapper: FileWrapper) throws -> URL {
        guard rtfdFileWrapper.isDirectory else {
            throw LibraryFileError.rtfDecodingFailed
        }
        try FileManager.default.createDirectory(
            at: documentsDirectory,
            withIntermediateDirectories: true
        )
        let url = fileURL(forDocumentID: documentID)
        try rtfdFileWrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        return url
    }

    /// 读取文档正文。文件缺失或损坏时返回 nil，由调用方决定兜底行为。
    func load(documentID: UUID) -> NSAttributedString? {
        let url = fileURL(forDocumentID: documentID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let wrapper = try? FileWrapper(url: url, options: []) else { return nil }
        var attributes: NSDictionary?
        return NSAttributedString(
            rtfdFileWrapper: wrapper,
            documentAttributes: &attributes
        )
    }

    /// 从 RTF 数据创建正文文件包（导入用）。
    @discardableResult
    func save(documentID: UUID, rtfData: Data) throws -> URL {
        guard let attributed = try? NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else {
            throw LibraryFileError.rtfDecodingFailed
        }
        return try save(documentID: documentID, attributedString: attributed)
    }

    /// 物理删除文档正文文件包。
    func delete(documentID: UUID) throws {
        let url = fileURL(forDocumentID: documentID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

/// 资料库文件错误。
enum LibraryFileError: LocalizedError {
    case rtfdEncodingFailed
    case rtfDecodingFailed

    var errorDescription: String? {
        switch self {
        case .rtfdEncodingFailed: return "无法将富文本编码为 RTFD。"
        case .rtfDecodingFailed: return "无法读取该 RTF 文档。"
        }
    }
}
