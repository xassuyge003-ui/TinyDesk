import AppKit
import SwiftUI
import TinyDeskCore

/// SwiftUI 生命周期与 AppKit 生命周期之间的桥，确保所有退出路径都最终落盘。
enum AppLifecycleBridge {
    static var onBecomeActive: (() -> Void)?
    static var onTerminate: (() -> Void)?
}

/// 应用级委托：覆盖菜单退出、Dock 退出、系统终止等路径。
final class TinyDeskAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidBecomeActive(_ notification: Notification) {
        AppLifecycleBridge.onBecomeActive?()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppLifecycleBridge.onTerminate?()
        return .terminateNow
    }
}

@main
struct TinyDeskApp: App {
    @NSApplicationDelegateAdaptor(TinyDeskAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: DesktopWorkspaceStore
    @StateObject private var windowManager: DesktopWindowManager
    @StateObject private var settings: TinyDeskSettings
    @StateObject private var calendarService: SystemCalendarService
    @StateObject private var libraryStore: LibraryStore

    @MainActor
    init() {
        TinyDeskNotificationDelegate.install()
        let workspaceStore = DesktopWorkspaceStore()
        let settingsStore = TinyDeskSettings()
        let systemCalendarService = SystemCalendarService()
        _store = StateObject(wrappedValue: workspaceStore)
        _settings = StateObject(wrappedValue: settingsStore)
        _calendarService = StateObject(wrappedValue: systemCalendarService)
        _windowManager = StateObject(
            wrappedValue: DesktopWindowManager(
                store: workspaceStore,
                settings: settingsStore,
                calendarService: systemCalendarService
            )
        )
        _libraryStore = StateObject(wrappedValue: LibraryStore())

        // 应用回到前台时重排通知（覆盖系统设置中重新授予权限、跨日期边界等场景）。
        // SwiftUI 可能多次重建 App 结构体并重复执行 init：bridge 只接受第一次
        // 初始化（StateObject 持有的实例），避免闭包捕获到被丢弃的实例。
        if AppLifecycleBridge.onBecomeActive == nil {
            AppLifecycleBridge.onBecomeActive = { [weak workspaceStore] in
                workspaceStore?.refreshImportantDateNotifications()
            }
        }
        if AppLifecycleBridge.onTerminate == nil {
            AppLifecycleBridge.onTerminate = { [weak windowManager] in
                windowManager?.closePanels()
            }
        }
        // 注意：不要在 init 中调用 windowManager.start()。
        // SwiftUI 会多次重建 App 结构体并重新执行 init，每次都会新建一个
        // DesktopWindowManager 并为其创建整套桌面面板，被丢弃实例的面板
        // 会泄漏并叠加成重复卡片。start() 由控制中心/菜单栏视图的 onAppear
        // 在真正的实例上触发（didStart 保证只执行一次）。
    }

    var body: some Scene {
        Window("TinyDesk", id: "control-center") {
            ControlCenterView()
                .environmentObject(store)
                .environmentObject(windowManager)
                .environmentObject(settings)
                .environmentObject(calendarService)
                .onAppear {
                    windowManager.start()
                    calendarService.refreshCalendars()
                    Task { await store.synchronizeSystemCalendar(using: calendarService) }
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        calendarService.refreshCalendars()
                        Task { await store.synchronizeSystemCalendar(using: calendarService) }
                    } else {
                        _ = store.persistNow()
                    }
                }
        }
        .defaultSize(width: 820, height: 680)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("卡片") {
                Button("新建便签") { windowManager.createCard(.sticky) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("新建重要日期") { windowManager.createCard(.countdown) }
                Button("新建待办") { windowManager.createCard(.todo) }
                Divider()
                Button("显示全部卡片") { store.showAll() }
                Button("隐藏全部卡片") { store.hideAll() }
            }
            CommandGroup(replacing: .appTermination) {
                Button("退出 TinyDesk") {
                    windowManager.closePanels()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }

        Window("TinyDesk 资料库", id: "library") {
            LibraryWindowView()
                .environmentObject(libraryStore)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandMenu("资料库") {
                Button("新建文档") { libraryStore.createDocument() }
                    .keyboardShortcut("n", modifiers: .command)
                Divider()
                Button("导入…") {
                    openImportPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("导出…") {
                    openExportPanel()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("导出资料库备份…") {
                    openBackupPanel()
                }
                Button("恢复资料库备份…") {
                    openRestorePanel()
                }
            }
        }

        MenuBarExtra("TinyDesk", systemImage: "rectangle.3.group.bubble.left.fill") {
            TinyDeskMenuBarView()
                .environmentObject(store)
                .environmentObject(windowManager)
                .environmentObject(settings)
                .environmentObject(calendarService)
                .onAppear { windowManager.start() }
        }
        .menuBarExtraStyle(.menu)
    }

    // MARK: 资料库菜单动作

    private func openImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "导入文档到资料库"
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = LibraryImportExport.supportedImportContentTypes
        panel.begin { response in
            guard response == .OK else { return }
            do {
                try LibraryImportExport.importFiles(panel.urls, store: libraryStore)
                NSApplication.shared.activate(ignoringOtherApps: true)
            } catch {
                presentLibraryError(error)
            }
        }
    }

    private func openExportPanel() {
        guard let document = libraryStore.selectedDocumentID
            .flatMap({ libraryStore.document(withID: $0) })
        else { return }
        // 导出前先同步保存编辑器未落盘正文。
        LibraryExportWillBeginNotification.post()
        let panel = NSSavePanel()
        panel.title = "导出文档"
        panel.allowedContentTypes = LibraryImportExport.supportedExportContentTypes
        panel.nameFieldStringValue = "\(document.title).rtf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try LibraryImportExport.export(document, to: url, store: libraryStore)
            } catch {
                presentLibraryError(error)
            }
        }
    }

    private func openBackupPanel() {
        // 备份前先同步保存所有未落盘正文。
        LibraryExportWillBeginNotification.post()
        let panel = NSSavePanel()
        panel.title = "导出资料库备份"
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "TinyDesk 资料库备份"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try LibraryImportExport.exportBackup(store: libraryStore, to: url)
            } catch {
                presentLibraryError(error)
            }
        }
    }

    private func openRestorePanel() {
        let panel = NSOpenPanel()
        panel.title = "恢复资料库备份"
        panel.allowedContentTypes = [.zip]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let count = try LibraryImportExport.importBackup(from: url, store: libraryStore)
                let alert = NSAlert()
                alert.messageText = "恢复完成"
                alert.informativeText = "已恢复 \(count) 篇文档。"
                alert.runModal()
            } catch {
                presentLibraryError(error)
            }
        }
    }

    private func presentLibraryError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "资料库操作失败"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

private struct TinyDeskMenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: DesktopWorkspaceStore
    @EnvironmentObject private var windowManager: DesktopWindowManager

    var body: some View {
        Button("打开 TinyDesk 控制中心", systemImage: "macwindow") {
            openControlCenter()
        }
        Button("打开资料库", systemImage: "books.vertical") {
            openWindow(id: "library")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: LibraryDocumentOpenRequest.notificationName)) { notification in
            // 菜单栏视图常驻：资料库窗口关闭时也能先打开窗口，再由
            // LibraryWindowView.onAppear 消费 pending 文档 ID 完成选中。
            guard let id = notification.userInfo?[LibraryDocumentOpenRequest.documentIDKey] as? UUID else { return }
            LibraryOpenCoordinator.pendingDocumentID = id
            openWindow(id: "library")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("新建便签", systemImage: "note.text.badge.plus") {
            windowManager.createCard(.sticky)
        }
        Button("快速新建置顶便签", systemImage: "pin.fill") {
            windowManager.createQuickSticky()
        }
        Button("新建重要日期", systemImage: "calendar.badge.plus") {
            windowManager.createCard(.countdown)
        }
        Button("新建待办", systemImage: "checklist") {
            windowManager.createCard(.todo)
        }

        if !store.cards.isEmpty {
            Divider()
            Menu("我的卡片") {
                ForEach(store.cards) { card in
                    Button {
                        windowManager.focus(card.id)
                    } label: {
                        Label(
                            card.title.isEmpty ? card.kind.displayName : card.title,
                            systemImage: card.kind.symbolName
                        )
                    }
                }
            }
            Button("显示全部", systemImage: "eye") { store.showAll() }
            Button("隐藏全部", systemImage: "eye.slash") { store.hideAll() }
        }

        Divider()

        Button("打开控制中心", systemImage: "gearshape") {
            openControlCenter()
        }

        Button("退出 TinyDesk", systemImage: "power") {
            windowManager.closePanels()
            NSApplication.shared.terminate(nil)
        }
    }

    private func openControlCenter() {
        openWindow(id: "control-center")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
