import Foundation

// MARK: - 应用标识与本地存储契约

/// TinyDesk 的全局约定，避免本地存储路径和标识散落在 UI 中。
public enum TinyDeskConst {
    public static let mainBundleID = "com.kai.tinydesk"
    public static let applicationSupportDirectoryName = "TinyDesk"
    public static let workspaceFileName = "workspace.json"

    // MARK: 资料库（v2.5）

    /// 资料库在 Application Support 目录下的子目录名。
    public static let libraryDirectoryName = "Library"
    /// 资料库 SQLite 元数据与全文索引文件名。
    public static let libraryDatabaseName = "library.db"
    /// 资料库 RTFD 文档文件目录名。
    public static let libraryDocumentsDirectoryName = "documents"
    /// 资料库备份包内导出元数据文件名。
    public static let libraryBackupManifestName = "manifest.json"
    /// 资料库备份包内完整 JSON 导出文件名。
    public static let libraryBackupDataName = "library.json"
}
