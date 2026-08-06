import AppKit

enum DesktopCardWindowPolicy {
    // Cards remain visible across regular desktop spaces, but must not cover another app in full screen.
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenNone,
        .stationary,
    ]

    /// 桌面图标之上、普通应用窗口之下的层级。
    static let desktopLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    )

    static func windowLevel(isAlwaysOnTop: Bool) -> NSWindow.Level {
        isAlwaysOnTop ? .floating : desktopLevel
    }

    /// `isFloatingPanel` 可能会改写 panel 的 level，必须先设置它，再恢复目标层级。
    static func applyWindowLevel(to panel: NSPanel, isAlwaysOnTop: Bool) {
        panel.isFloatingPanel = isAlwaysOnTop
        panel.level = windowLevel(isAlwaysOnTop: isAlwaysOnTop)
    }
}
