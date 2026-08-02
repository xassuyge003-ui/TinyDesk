import Foundation

// MARK: - 应用标识与本地存储契约

/// TinyDesk 的全局约定，避免本地存储路径和标识散落在 UI 中。
public enum TinyDeskConst {
    public static let mainBundleID = "com.kai.tinydesk"
    public static let applicationSupportDirectoryName = "TinyDesk"
    public static let workspaceFileName = "workspace.json"
}
