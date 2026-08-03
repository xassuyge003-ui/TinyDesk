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

        print("DesktopCardWindowPolicyTests: passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestError.failed(message) }
    }

    private enum TestError: Error {
        case failed(String)
    }
}
