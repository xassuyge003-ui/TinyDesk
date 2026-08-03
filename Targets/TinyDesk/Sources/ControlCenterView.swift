import AppKit
import SwiftUI
import TinyDeskCore

struct ControlCenterView: View {
    @EnvironmentObject private var store: DesktopWorkspaceStore
    @EnvironmentObject private var windowManager: DesktopWindowManager
    @EnvironmentObject private var settings: TinyDeskSettings
    @EnvironmentObject private var calendarService: SystemCalendarService
    @State private var pendingDeletion: DesktopCard?
    @State private var showsSettings = false

    private let columns = [
        GridItem(.adaptive(minimum: 245, maximum: 360), spacing: 14),
    ]

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero

                    if let message = store.storageMessage {
                        storageBanner(message)
                    }

                    addSection
                    cardsSection
                    privacyFooter
                }
                .padding(26)
            }
        }
        .frame(minWidth: 620, minHeight: 560)
        .confirmationDialog(
            "删除“\(pendingDeletion?.title ?? "卡片")”？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { card in
            Button("永久删除", role: .destructive) {
                store.deleteCard(card.id)
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: { card in
            Text("该\(card.kind.displayName)及其中内容会从本机工作区删除，此操作无法撤销。")
        }
        .sheet(isPresented: $showsSettings) {
            TinyDeskSettingsView()
                .environmentObject(settings)
                .environmentObject(calendarService)
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo, Color.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "rectangle.3.group.bubble.left.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 60, height: 60)
            .shadow(color: .indigo.opacity(0.25), radius: 14, y: 7)

            VStack(alignment: .leading, spacing: 4) {
                Text("TinyDesk")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("可直接编辑的桌面便签、重要日期与待办")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button("全部显示", systemImage: "eye") {
                    store.showAll()
                }
                Button("全部隐藏", systemImage: "eye.slash") {
                    store.hideAll()
                }
                Button("设置", systemImage: "gearshape") {
                    showsSettings = true
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("新建桌面卡片", subtitle: "可选择小号、中号、大号比例，也可自由缩放")

            HStack(spacing: 12) {
                AddCardButton(
                    title: "便签",
                    subtitle: "随手记录",
                    symbol: "note.text",
                    tint: .orange
                ) { windowManager.createCard(.sticky) }

                AddCardButton(
                    title: "重要日期",
                    subtitle: "生日、节日与纪念日",
                    symbol: "calendar.badge.clock",
                    tint: .pink
                ) { windowManager.createCard(.countdown) }

                AddCardButton(
                    title: "待办",
                    subtitle: "跟踪任务",
                    symbol: "checklist",
                    tint: .green
                ) { windowManager.createCard(.todo) }
            }
        }
    }

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("我的卡片", subtitle: "\(store.cards.count) 张卡片")

            if store.cards.isEmpty {
                ContentUnavailableView {
                    Label("还没有桌面卡片", systemImage: "rectangle.stack.badge.plus")
                } description: {
                    Text("从上方选择一种类型开始")
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 18))
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(store.cards) { card in
                        CardManagementTile(
                            card: card,
                            summary: card.summary(importantDates: store.importantDates),
                            focus: { windowManager.focus(card.id) },
                            toggleVisibility: {
                                store.setVisible(!card.isVisible, for: card.id)
                            },
                            resize: { preset in
                                windowManager.applySizePreset(preset, to: card.id)
                            },
                            setSurfaceStyle: { style in
                                store.updateCard(card.id) { $0.surfaceStyle = style }
                            },
                            setTheme: { theme in
                                store.updateCard(card.id) { $0.theme = theme }
                            },
                            setPositionLocked: { isLocked in
                                store.updateCard(card.id) { $0.isPositionLocked = isLocked }
                            },
                            resetPosition: { windowManager.resetPosition(card.id) },
                            delete: { pendingDeletion = card }
                        )
                    }
                }
            }
        }
    }

    private var privacyFooter: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("完全本地 · 无 App Group · 无付费能力")
                    .font(.caption.weight(.semibold))
                Text("便签、日期和待办写入本地 workspace.json；系统日历只在你主动关联后访问。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("在 Finder 中显示") {
                _ = store.persistNow()
                NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(14)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func storageBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("关闭") { store.dismissStorageMessage() }
                .buttonStyle(.borderless)
        }
        .padding(13)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct AddCardButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CardManagementTile: View {
    let card: DesktopCard
    let summary: String
    let focus: () -> Void
    let toggleVisibility: () -> Void
    let resize: (DesktopCardSizePreset) -> Void
    let setSurfaceStyle: (DesktopCardSurfaceStyle) -> Void
    let setTheme: (DesktopCardTheme) -> Void
    let setPositionLocked: (Bool) -> Void
    let resetPosition: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: card.kind.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(card.theme.palette.accent)
                    .frame(width: 34, height: 34)
                    .background(card.theme.palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title.isEmpty ? card.kind.displayName : card.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if card.resolvedIsPositionLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(card.theme.palette.accent)
                        .help("位置已锁定")
                }
                Circle()
                    .fill(card.isVisible ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .help(card.isVisible ? "正在桌面显示" : "已隐藏")
            }

            HStack(spacing: 7) {
                Button("定位", systemImage: "scope", action: focus)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(card.isVisible ? "隐藏" : "显示", systemImage: card.isVisible ? "eye.slash" : "eye", action: toggleVisibility)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Menu {
                    Menu("卡片尺寸", systemImage: "aspectratio") {
                        ForEach(DesktopCardSizePreset.allCases) { preset in
                            Button {
                                resize(preset)
                            } label: {
                                Label(
                                    "\(preset.displayName)  \(preset.dimensions)",
                                    systemImage: selectedSizePreset == preset ? "checkmark" : preset.symbolName
                                )
                            }
                        }
                    }
                    Menu("背景风格", systemImage: card.resolvedSurfaceStyle.symbolName) {
                        ForEach(DesktopCardSurfaceStyle.allCases, id: \.self) { style in
                            Button {
                                setSurfaceStyle(style)
                            } label: {
                                Label(
                                    style.displayName,
                                    systemImage: card.resolvedSurfaceStyle == style ? "checkmark" : style.symbolName
                                )
                            }
                        }
                    }
                    Menu("卡片颜色", systemImage: "paintpalette") {
                        ForEach(DesktopCardTheme.allCases, id: \.self) { theme in
                            Button {
                                setTheme(theme)
                            } label: {
                                Label(
                                    theme.displayName,
                                    systemImage: card.theme == theme ? "checkmark.circle.fill" : "circle.fill"
                                )
                            }
                        }
                    }
                    Button(
                        card.resolvedIsPositionLocked ? "允许移动" : "锁定位置",
                        systemImage: card.resolvedIsPositionLocked ? "lock.open" : "lock"
                    ) {
                        setPositionLocked(!card.resolvedIsPositionLocked)
                    }
                    Button("恢复默认位置", systemImage: "arrow.counterclockwise", action: resetPosition)
                    Divider()
                    Button("删除卡片", systemImage: "trash", role: .destructive, action: delete)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 24, height: 20)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
    }

    private var selectedSizePreset: DesktopCardSizePreset? {
        guard let frame = card.frame else { return nil }
        let size = NSSize(width: frame.width, height: frame.height)
        return DesktopCardSizePreset.allCases.first { $0.matches(size) }
    }
}

extension DesktopCardKind {
    var displayName: String {
        switch self {
        case .sticky: return "便签"
        case .countdown: return "重要日期"
        case .todo: return "待办"
        }
    }
}

private extension DesktopCard {
    func summary(importantDates: [ImportantDateEvent]) -> String {
        switch kind {
        case .sticky:
            let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "空白便签" : text.replacingOccurrences(of: "\n", with: " ")
        case .countdown:
            guard let event = importantDates.sorted(by: importantDateOrder).first,
                  let days = event.daysUntilOccurrence()
            else { return "还没有重要日期" }
            if days == 0 { return "\(event.title) · 就是今天" }
            if event.recurrence == .once && days < 0 {
                return "\(event.title) · 已过去 \(abs(days)) 天"
            }
            return "\(event.title) · 还有 \(days) 天"
        case .todo:
            return "已完成 \(completedTodoCount) / \(todoItems.count)"
        }
    }

    private func importantDateOrder(_ lhs: ImportantDateEvent, _ rhs: ImportantDateEvent) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        let lhsDays = lhs.daysUntilOccurrence() ?? Int.max
        let rhsDays = rhs.daysUntilOccurrence() ?? Int.max
        let lhsPast = lhs.recurrence == .once && lhsDays < 0
        let rhsPast = rhs.recurrence == .once && rhsDays < 0
        if lhsPast != rhsPast { return !lhsPast }
        return lhsDays < rhsDays
    }
}
