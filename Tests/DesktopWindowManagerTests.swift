import AppKit
import Foundation
import TinyDeskCore

@main
struct DesktopWindowManagerTests {
    @MainActor
    static func main() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TinyDesk-DesktopWindowManagerTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let store = DesktopWorkspaceStore(fileURL: workspaceURL)
        let card = store.addCard(kind: .sticky)
        let manager = DesktopWindowManager(
            store: store,
            settings: TinyDeskSettings(),
            calendarService: SystemCalendarService()
        )
        manager.show(card.id)
        defer { manager.closePanels() }

        guard let panel = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == card.id.uuidString
        }) else {
            throw TestError.missingCardWindow
        }

        try require(
            !panel.collectionBehavior.contains(.fullScreenAuxiliary),
            "桌面卡片不应进入其他应用的全屏空间"
        )
        try require(
            panel.collectionBehavior.contains(.fullScreenNone),
            "桌面卡片必须显式禁止加入其他应用的全屏空间"
        )

        print("DesktopWindowManagerTests: passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestError.failed(message) }
    }

    private enum TestError: Error {
        case missingCardWindow
        case failed(String)
    }
}
