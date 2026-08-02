import AppKit
import SwiftUI
import TinyDeskCore

@main
struct TinyDeskApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: DesktopWorkspaceStore
    @StateObject private var windowManager: DesktopWindowManager
    @StateObject private var settings: TinyDeskSettings
    @StateObject private var calendarService: SystemCalendarService

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
}

private struct TinyDeskMenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: DesktopWorkspaceStore
    @EnvironmentObject private var windowManager: DesktopWindowManager

    var body: some View {
        Button("打开 TinyDesk 控制中心", systemImage: "macwindow") {
            openControlCenter()
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

        Button("打开控制中心设置", systemImage: "gearshape") {
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
