import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class TinyDeskSettings: ObservableObject {
    @Published private(set) var launchesAtLogin = false
    @Published private(set) var launchAtLoginMessage: String?
    @Published var quickNotesStartPinned: Bool {
        didSet {
            UserDefaults.standard.set(quickNotesStartPinned, forKey: Self.quickNotesStartPinnedKey)
        }
    }
    @Published private(set) var quickNoteShortcut: GlobalShortcut
    @Published private(set) var shortcutMessage: String?

    private static let quickNotesStartPinnedKey = "quickNotesStartPinned"
    private static let quickNoteShortcutKeyCodeKey = "quickNoteShortcut.keyCode"
    private static let quickNoteShortcutModifiersKey = "quickNoteShortcut.modifiers"
    private static let quickNoteShortcutDisplayKey = "quickNoteShortcut.displayKey"

    init() {
        quickNotesStartPinned = UserDefaults.standard.object(forKey: Self.quickNotesStartPinnedKey) as? Bool ?? true
        quickNoteShortcut = Self.loadQuickNoteShortcut()
        refreshLaunchAtLoginStatus()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            launchAtLoginMessage = "无法更新开机自启：\(error.localizedDescription)"
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setQuickNoteShortcut(_ shortcut: GlobalShortcut) {
        guard GlobalShortcutManager.shared.register(shortcut) else {
            shortcutMessage = "该快捷键已被系统或其他应用占用，请换一个组合。"
            return
        }

        quickNoteShortcut = shortcut
        UserDefaults.standard.set(Int(shortcut.keyCode), forKey: Self.quickNoteShortcutKeyCodeKey)
        UserDefaults.standard.set(Int(shortcut.modifiers), forKey: Self.quickNoteShortcutModifiersKey)
        UserDefaults.standard.set(shortcut.keyDisplay, forKey: Self.quickNoteShortcutDisplayKey)
        shortcutMessage = nil
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func loadQuickNoteShortcut() -> GlobalShortcut {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: quickNoteShortcutKeyCodeKey) != nil else {
            return .defaultQuickNote
        }
        return GlobalShortcut(
            keyCode: UInt32(defaults.integer(forKey: quickNoteShortcutKeyCodeKey)),
            modifiers: UInt32(defaults.integer(forKey: quickNoteShortcutModifiersKey)),
            keyDisplay: defaults.string(forKey: quickNoteShortcutDisplayKey) ?? "N"
        )
    }
}

struct TinyDeskSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: TinyDeskSettings
    @EnvironmentObject private var calendarService: SystemCalendarService

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TinyDesk 设置")
                    .font(.headline)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            Form {
                Section("效率") {
                    Toggle(
                        "开机自动启动 TinyDesk",
                        isOn: Binding(
                            get: { settings.launchesAtLogin },
                            set: settings.setLaunchAtLogin
                        )
                    )
                    Text("关闭控制中心后，TinyDesk 仍驻留在菜单栏。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let message = settings.launchAtLoginMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Button("在系统设置中管理登录项", action: settings.openLoginItemsSettings)
                        .font(.caption)

                    LabeledContent("快速新建置顶便签") {
                        GlobalShortcutRecorder(
                            shortcut: Binding(
                                get: { settings.quickNoteShortcut },
                                set: settings.setQuickNoteShortcut
                            )
                        )
                        .frame(width: 150, height: 30)
                    }
                    Text("默认 ⌥⌘N；可在此录制新快捷键。便签会出现在鼠标所在屏幕顶部中央。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let message = settings.shortcutMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Toggle("快速便签默认置顶", isOn: $settings.quickNotesStartPinned)
                    Text("取消置顶后，便签会恢复到桌面图标上方、普通应用窗口下方。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("系统日历") {
                    LabeledContent("访问状态", value: calendarAccessText)
                    if calendarService.canRequestAccess {
                        Button("允许访问系统日历") {
                            Task { _ = await calendarService.requestFullAccess() }
                        }
                    } else if !calendarService.hasFullAccess {
                        Button("在系统设置中允许日历访问") {
                            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
                            NSWorkspace.shared.open(url)
                        }
                    } else {
                        Text("已发现 \(calendarService.calendars.count) 个可读取日历，其中 \(calendarService.writableCalendars.count) 个可写。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 520, minHeight: 500)
        .onAppear { calendarService.refreshCalendars() }
    }

    private var calendarAccessText: String {
        if calendarService.hasFullAccess { return "已允许完整访问" }
        if calendarService.canRequestAccess { return "尚未请求" }
        return "未允许"
    }
}
