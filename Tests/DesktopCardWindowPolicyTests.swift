import AppKit

@main
struct DesktopCardWindowPolicyTests {
    static func main() throws {
        let behavior = DesktopCardWindowPolicy.collectionBehavior

        try require(
            !behavior.contains(.fullScreenAuxiliary),
            "桌面卡片不应进入其他应用的全屏空间"
        )
        try require(
            behavior.contains(.fullScreenNone),
            "桌面卡片必须显式禁止加入其他应用的全屏空间"
        )
        try require(
            behavior.contains(.canJoinAllSpaces),
            "桌面卡片应继续显示在所有普通桌面空间"
        )
        try require(
            behavior.contains(.stationary),
            "桌面卡片应继续在调度中心保持固定位置"
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        DesktopCardWindowPolicy.applyWindowLevel(to: panel, isAlwaysOnTop: false)
        try require(!panel.isFloatingPanel, "未置顶卡片不应使用 floating panel")
        try require(
            panel.level == DesktopCardWindowPolicy.desktopLevel,
            "未置顶卡片在获得焦点后必须回到桌面层"
        )

        DesktopCardWindowPolicy.applyWindowLevel(to: panel, isAlwaysOnTop: true)
        try require(panel.isFloatingPanel, "显式置顶卡片应使用 floating panel")
        try require(panel.level == .floating, "显式置顶卡片应使用 floating 层")

        print("DesktopCardWindowPolicyTests: passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestError.failed(message) }
    }

    private enum TestError: Error {
        case failed(String)
    }
}
