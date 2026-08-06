import AppKit
import Foundation
import TinyDeskCore

/// 资料库备份包的打包与恢复。
///
/// ZIP 结构：
///   manifest.json      — 版本与统计信息
///   library.json       — 全部目录/标签/文档元数据
///   documents/<id>.rtfd — 每个文档的 RTFD 文件包
struct LibraryBackup {
    struct RestoredBody {
        let rtfdFileWrapper: FileWrapper?
        let legacyRTFData: Data?
    }

    struct Manifest: Codable {
        var version: String
        var createdAt: Date
        var documentCount: Int
        var schemaVersion: Int
        var appName: String

        static func current(documentCount: Int) -> Manifest {
            Manifest(
                version: "2.5.0",
                createdAt: Date(),
                documentCount: documentCount,
                schemaVersion: 1,
                appName: "TinyDesk"
            )
        }
    }

    struct Bundle: Codable {
        var schemaVersion: Int
        var categories: [LibraryCategory]
        var tags: [LibraryTag]
        var documents: [LibraryDocument]
    }

    /// 把资料库完整导出为 ZIP 数据。
    static func createArchive(
        categories: [LibraryCategory],
        tags: [LibraryTag],
        documents: [LibraryDocument],
        fileManager: LibraryFileManager
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try createArchive(
            categories: categories,
            tags: tags,
            documents: documents,
            fileManager: fileManager,
            encoder: encoder
        )
    }

    /// 把资料库完整导出为 ZIP 数据。
    static func createArchive(
        categories: [LibraryCategory],
        tags: [LibraryTag],
        documents: [LibraryDocument],
        fileManager: LibraryFileManager,
        encoder: JSONEncoder
    ) throws -> Data {
        let bundle = Bundle(
            schemaVersion: 1,
            categories: categories,
            tags: tags,
            documents: documents
        )
        let data = try encoder.encode(bundle)
        let manifest = Manifest.current(documentCount: documents.count)
        let manifestData = try encoder.encode(manifest)

        var entries: [LibraryBackupArchive.Entry] = [
            LibraryBackupArchive.Entry(path: TinyDeskConst.libraryBackupManifestName, data: manifestData),
            LibraryBackupArchive.Entry(path: TinyDeskConst.libraryBackupDataName, data: data),
        ]

        for document in documents {
            let url = fileManager.fileURL(forDocumentID: document.id)
            guard let wrapper = try? FileWrapper(url: url, options: []) else { continue }
            entries.append(contentsOf: archiveEntries(
                from: wrapper,
                at: "documents/\(document.id.uuidString).rtfd"
            ))
        }

        return LibraryBackupArchive.create(entries: entries)
    }

    /// 从 ZIP 数据恢复资料库。返回恢复的文档列表，由调用方写入数据库。
    static func extractArchive(data: Data, fileManager: LibraryFileManager) throws -> (bundle: Bundle, documents: [UUID: RestoredBody]) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try extractArchive(data: data, fileManager: fileManager, decoder: decoder)
    }

    /// 从 ZIP 数据恢复资料库。返回恢复的文档列表，由调用方写入数据库。
    static func extractArchive(
        data: Data,
        fileManager: LibraryFileManager,
        decoder: JSONDecoder
    ) throws -> (bundle: Bundle, documents: [UUID: RestoredBody]) {
        let entries = LibraryBackupArchive.extract(data)

        guard let manifestEntry = entries.first(where: { $0.path == TinyDeskConst.libraryBackupManifestName }),
              let bundleEntry = entries.first(where: { $0.path == TinyDeskConst.libraryBackupDataName })
        else {
            throw LibraryBackupError.invalidArchive
        }

        let manifest = try decoder.decode(Manifest.self, from: manifestEntry.data)
        guard manifest.schemaVersion <= 1 else {
            throw LibraryBackupError.unsupportedVersion(manifest.schemaVersion)
        }

        let bundle = try decoder.decode(Bundle.self, from: bundleEntry.data)
        var packageEntries: [UUID: [LibraryBackupArchive.Entry]] = [:]
        var legacyRTF: [UUID: Data] = [:]

        for entry in entries {
            let components = entry.path.split(separator: "/").map(String.init)
            guard components.first == "documents", components.count >= 2 else { continue }

            let packageName = components[1]
            if packageName.hasSuffix(".rtf"), components.count == 2,
               let id = UUID(uuidString: String(packageName.dropLast(4))) {
                legacyRTF[id] = entry.data
                continue
            }

            guard packageName.hasSuffix(".rtfd"),
                  let id = UUID(uuidString: String(packageName.dropLast(5)))
            else { continue }

            let relativePath = components.dropFirst(2).joined(separator: "/")
            guard !relativePath.isEmpty else { continue }
            packageEntries[id, default: []].append(
                LibraryBackupArchive.Entry(
                    path: relativePath,
                    data: entry.data,
                    isDirectory: entry.isDirectory
                )
            )
        }

        var documents: [UUID: RestoredBody] = legacyRTF.mapValues {
            RestoredBody(rtfdFileWrapper: nil, legacyRTFData: $0)
        }
        for (id, entries) in packageEntries {
            guard let wrapper = directoryWrapper(from: entries) else { continue }
            documents[id] = RestoredBody(rtfdFileWrapper: wrapper, legacyRTFData: nil)
        }

        return (bundle, documents)
    }

    // MARK: - RTFD 文件包

    private static func archiveEntries(from wrapper: FileWrapper, at path: String) -> [LibraryBackupArchive.Entry] {
        if wrapper.isDirectory {
            let directoryPath = path.hasSuffix("/") ? path : "\(path)/"
            var entries = [LibraryBackupArchive.Entry(path: directoryPath, data: Data(), isDirectory: true)]
            for (name, child) in (wrapper.fileWrappers ?? [:]).sorted(by: { $0.key < $1.key })
            where isSafePathComponent(name) {
                entries.append(contentsOf: archiveEntries(from: child, at: "\(directoryPath)\(name)"))
            }
            return entries
        }

        guard wrapper.isRegularFile else { return [] }
        return [LibraryBackupArchive.Entry(path: path, data: wrapper.regularFileContents ?? Data())]
    }

    /// 按归档路径建立纯内存 FileWrapper 树，拒绝路径穿越与冲突条目。
    private static func directoryWrapper(from entries: [LibraryBackupArchive.Entry]) -> FileWrapper? {
        var files: [String: Data] = [:]
        var descendants: [String: [LibraryBackupArchive.Entry]] = [:]

        for entry in entries {
            let components = entry.path.split(separator: "/").map(String.init)
            guard let name = components.first, isSafePathComponent(name) else { return nil }
            if components.count == 1 {
                if entry.isDirectory {
                    if descendants[name] == nil {
                        descendants[name] = []
                    }
                } else if descendants[name] == nil {
                    files[name] = entry.data
                } else {
                    return nil
                }
            } else {
                guard files[name] == nil else { return nil }
                descendants[name, default: []].append(
                    LibraryBackupArchive.Entry(
                        path: components.dropFirst().joined(separator: "/"),
                        data: entry.data,
                        isDirectory: entry.isDirectory
                    )
                )
            }
        }

        var children: [String: FileWrapper] = [:]
        for (name, data) in files {
            children[name] = FileWrapper(regularFileWithContents: data)
        }
        for (name, nestedEntries) in descendants {
            guard let child = directoryWrapper(from: nestedEntries) else { return nil }
            children[name] = child
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
    }
}

/// 资料库备份错误。
enum LibraryBackupError: LocalizedError {
    case invalidArchive
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "备份包格式无效。"
        case let .unsupportedVersion(version): return "备份包版本 \(version) 高于当前应用支持的版本。"
        }
    }
}
