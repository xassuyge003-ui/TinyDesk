import AppKit
import SwiftUI
import TinyDeskCore

struct DesktopCardHostView: View {
    @EnvironmentObject private var store: DesktopWorkspaceStore
    @EnvironmentObject private var windowManager: DesktopWindowManager
    @State private var isHovering = false

    let cardID: UUID

    var body: some View {
        Group {
            if let card = store.card(withID: cardID) {
                GeometryReader { proxy in
                    let compact = proxy.size.width < 270 || proxy.size.height < 220

                    VStack(spacing: 0) {
                        if card.kind != .countdown {
                            cardHeader(card: card, compact: compact)
                        }
                        cardContent(card: card, size: proxy.size)
                    }
                    .background(CardSurface(theme: card.theme, style: card.resolvedSurfaceStyle))
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: compact ? 18 : 24, style: .continuous)
                            .strokeBorder(.white.opacity(isHovering ? 0.28 : 0.14), lineWidth: 1)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        ResizeHint()
                            .opacity(isHovering ? 0.6 : 0)
                            .padding(7)
                    }
                    .padding(7)
                    .animation(.easeOut(duration: 0.18), value: isHovering)
                }
                .onHover { isHovering = $0 }
                .contextMenu {
                    Button("在桌面隐藏", systemImage: "eye.slash") {
                        windowManager.hide(cardID)
                    }
                    Button("恢复默认位置", systemImage: "arrow.counterclockwise") {
                        windowManager.resetPosition(cardID)
                    }
                    Button(
                        card.resolvedIsPositionLocked ? "允许移动" : "锁定位置",
                        systemImage: card.resolvedIsPositionLocked ? "lock.open" : "lock"
                    ) {
                        togglePositionLock(for: card)
                    }
                    Divider()
                    Menu("卡片尺寸") {
                        sizePresetButtons(for: card)
                    }
                    Menu("背景风格") {
                        surfaceStyleButtons(for: card)
                    }
                    Menu("卡片颜色") {
                        themeButtons(for: card)
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func cardContent(card: DesktopCard, size: CGSize) -> some View {
        let contentSize = card.kind == .countdown
            ? size
            : CGSize(width: size.width, height: max(0, size.height - 46))
        switch card.kind {
        case .sticky:
            StickyCardContent(card: card, availableSize: contentSize)
        case .countdown:
            CountdownCardContent(card: card, availableSize: contentSize)
        case .todo:
            TodoCardContent(card: card, availableSize: contentSize)
        }
    }

    private func cardHeader(card: DesktopCard, compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 10) {
            if card.resolvedIsPositionLocked {
                Button {
                    togglePositionLock(for: card)
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 17, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(card.theme.palette.accent)
                .help("位置已锁定，点击允许移动")
            } else {
                WindowDragHandle(isEnabled: true)
                    .frame(width: 17, height: 28)
                    .overlay {
                        Image(systemName: "circle.grid.2x2.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .allowsHitTesting(false)
                    }
                    .help("拖动卡片")
            }

            Image(systemName: card.kind.symbolName)
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .foregroundStyle(card.theme.palette.accent)

            TextField("标题", text: cardBinding(\.title, fallback: card.title))
                .textFieldStyle(.plain)
                .font(.system(size: compact ? 13 : 15, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Spacer(minLength: 0)

            Menu {
                sizePresetButtons(for: card)
            } label: {
                Image(systemName: "aspectratio")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("选择卡片尺寸")

            Menu {
                surfaceStyleButtons(for: card)
            } label: {
                Image(systemName: card.resolvedSurfaceStyle.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("选择背景风格")

            Menu {
                themeButtons(for: card)
            } label: {
                Circle()
                    .fill(card.theme.palette.accent)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更换颜色")

            Button {
                windowManager.hide(cardID)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("隐藏卡片（可在菜单栏重新显示）")
        }
        .padding(.leading, compact ? 10 : 14)
        .padding(.trailing, compact ? 8 : 10)
        .padding(.top, 8)
        .padding(.bottom, 5)
    }

    private func cardBinding<Value>(
        _ keyPath: WritableKeyPath<DesktopCard, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { store.card(withID: cardID)?[keyPath: keyPath] ?? fallback },
            set: { value in
                store.updateCard(cardID) { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func togglePositionLock(for card: DesktopCard) {
        store.updateCard(card.id) {
            $0.isPositionLocked = !card.resolvedIsPositionLocked
        }
    }

    @ViewBuilder
    private func sizePresetButtons(for card: DesktopCard) -> some View {
        let selected = windowManager.selectedSizePreset(for: card.id)
        ForEach(DesktopCardSizePreset.allCases) { preset in
            Button {
                windowManager.applySizePreset(preset, to: card.id)
            } label: {
                Label(
                    "\(preset.displayName)  \(preset.dimensions)",
                    systemImage: selected == preset ? "checkmark" : preset.symbolName
                )
            }
        }
        Divider()
        Text("仍可拖动卡片边缘自由缩放")
    }

    @ViewBuilder
    private func surfaceStyleButtons(for card: DesktopCard) -> some View {
        ForEach(DesktopCardSurfaceStyle.allCases, id: \.self) { style in
            Button {
                store.updateCard(cardID) { $0.surfaceStyle = style }
            } label: {
                Label(
                    style.displayName,
                    systemImage: card.resolvedSurfaceStyle == style ? "checkmark" : style.symbolName
                )
            }
        }
    }

    @ViewBuilder
    private func themeButtons(for card: DesktopCard) -> some View {
        ForEach(DesktopCardTheme.allCases, id: \.self) { theme in
            Button {
                store.updateCard(cardID) { $0.theme = theme }
            } label: {
                Label(theme.displayName, systemImage: card.theme == theme ? "checkmark.circle.fill" : "circle.fill")
            }
        }
    }
}

private struct StickyCardContent: View {
    @EnvironmentObject private var store: DesktopWorkspaceStore
    let card: DesktopCard
    let availableSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: noteBinding)
                .font(.system(size: availableSize.width < 270 ? 15 : 17, design: .rounded))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .padding(.horizontal, 9)
                .padding(.bottom, availableSize.height > 220 ? 24 : 8)

            if card.noteText.isEmpty {
                Text("写点什么…")
                    .font(.system(size: availableSize.width < 270 ? 15 : 17, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.65))
                    .padding(.leading, 17)
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if availableSize.height > 220 {
                Text("\(card.noteText.count) 字")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 9)
                    .allowsHitTesting(false)
            }
        }
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { store.card(withID: card.id)?.noteText ?? "" },
            set: { value in store.updateCard(card.id) { $0.noteText = value } }
        )
    }
}

private struct CountdownCardContent: View {
    @EnvironmentObject private var store: DesktopWorkspaceStore
    @EnvironmentObject private var windowManager: DesktopWindowManager
    @State private var displayedMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var selectedDay = Date()
    @State private var editorContext: ImportantDateEditorContext?

    let card: DesktopCard
    let availableSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            importantDateHeader

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let contentHeight = max(0, availableSize.height - 42)
                let compact = availableSize.width < 330 || contentHeight < 260
                let events = filteredEvents

                Group {
                    switch card.resolvedImportantDateViewMode {
                    case .calendar:
                        ImportantDateCalendarView(
                            month: $displayedMonth,
                            selectedDay: $selectedDay,
                            events: events,
                            compact: compact,
                            accent: card.theme.palette.accent,
                            referenceDate: context.date,
                            edit: edit
                        )
                    case .list:
                        ImportantDateListView(
                            events: ordered(events, referenceDate: context.date),
                            compact: compact,
                            accent: card.theme.palette.accent,
                            referenceDate: context.date,
                            edit: edit
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $editorContext) { context in
            ImportantDateEditorView(
                event: context.event,
                onSave: save,
                onDelete: { event in store.deleteImportantDate(event.id) }
            )
        }
    }

    private var importantDateHeader: some View {
        let compact = availableSize.width < 330
        let ultraCompact = availableSize.width < 245
        let controlSize: CGFloat = compact ? 20 : 24

        return HStack(spacing: 4) {
            Picker("视图", selection: viewModeBinding) {
                Text("日历").tag(ImportantDateViewMode.calendar)
                Text("列表").tag(ImportantDateViewMode.list)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: compact ? 94 : 148)
            .controlSize(.small)

            categoryFilterMenu(controlSize: controlSize)

            Button {
                editorContext = ImportantDateEditorContext(event: nil)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: compact ? 14 : 16, weight: .semibold))
                    .foregroundStyle(card.theme.palette.accent)
                    .frame(width: controlSize, height: controlSize)
            }
            .buttonStyle(.plain)
            .help("添加重要日期")

            Spacer(minLength: 0)

            Button {
                store.updateCard(card.id) {
                    $0.isPositionLocked = !card.resolvedIsPositionLocked
                }
            } label: {
                Image(systemName: card.resolvedIsPositionLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(card.resolvedIsPositionLocked ? card.theme.palette.accent : .secondary)
                    .frame(width: controlSize, height: controlSize)
            }
            .buttonStyle(.plain)
            .help(card.resolvedIsPositionLocked ? "位置已锁定，点击允许移动" : "锁定卡片位置")

            cardOptionsMenu(controlSize: controlSize, includesHide: ultraCompact)

            if !ultraCompact {
                Button {
                    windowManager.hide(card.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: controlSize, height: controlSize)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("隐藏卡片（可在菜单栏重新显示）")
            }
        }
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.top, 8)
        .padding(.bottom, 5)
    }

    private func categoryFilterMenu(controlSize: CGFloat) -> some View {
        Menu {
            Button {
                setCategoryFilter(nil)
            } label: {
                Label("全部分类", systemImage: card.importantDateCategoryFilter == nil ? "checkmark" : "square.grid.2x2")
            }
            Divider()
            ForEach(ImportantDateCategory.allCases, id: \.self) { category in
                Button {
                    setCategoryFilter(category)
                } label: {
                    Label(
                        category.displayName,
                        systemImage: card.importantDateCategoryFilter == category ? "checkmark" : category.symbolName
                    )
                }
            }
        } label: {
            Image(systemName: card.importantDateCategoryFilter?.symbolName ?? "line.3.horizontal.decrease.circle")
                .frame(width: controlSize, height: controlSize)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("筛选日期分类")
    }

    private func cardOptionsMenu(controlSize: CGFloat, includesHide: Bool) -> some View {
        Menu {
            Menu("卡片尺寸", systemImage: "aspectratio") {
                let selected = windowManager.selectedSizePreset(for: card.id)
                ForEach(DesktopCardSizePreset.allCases) { preset in
                    Button {
                        windowManager.applySizePreset(preset, to: card.id)
                    } label: {
                        Label(
                            "\(preset.displayName)  \(preset.dimensions)",
                            systemImage: selected == preset ? "checkmark" : preset.symbolName
                        )
                    }
                }
            }
            Menu("背景风格", systemImage: card.resolvedSurfaceStyle.symbolName) {
                ForEach(DesktopCardSurfaceStyle.allCases, id: \.self) { style in
                    Button {
                        store.updateCard(card.id) { $0.surfaceStyle = style }
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
                        store.updateCard(card.id) { $0.theme = theme }
                    } label: {
                        Label(
                            theme.displayName,
                            systemImage: card.theme == theme ? "checkmark.circle.fill" : "circle.fill"
                        )
                    }
                }
            }
            Divider()
            Button("恢复默认位置", systemImage: "arrow.counterclockwise") {
                windowManager.resetPosition(card.id)
            }
            if includesHide {
                Button("隐藏卡片", systemImage: "eye.slash") {
                    windowManager.hide(card.id)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: controlSize, height: controlSize)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("卡片设置")
    }

    private var filteredEvents: [ImportantDateEvent] {
        guard let category = card.importantDateCategoryFilter else { return store.importantDates }
        return store.importantDates.filter { $0.category == category }
    }

    private var viewModeBinding: Binding<ImportantDateViewMode> {
        Binding(
            get: { store.card(withID: card.id)?.resolvedImportantDateViewMode ?? .calendar },
            set: { mode in store.updateCard(card.id) { $0.importantDateViewMode = mode } }
        )
    }

    private func setCategoryFilter(_ category: ImportantDateCategory?) {
        store.updateCard(card.id) { $0.importantDateCategoryFilter = category }
    }

    private func ordered(_ events: [ImportantDateEvent], referenceDate: Date) -> [ImportantDateEvent] {
        events.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            let lhsDays = lhs.daysUntilOccurrence(from: referenceDate) ?? Int.max
            let rhsDays = rhs.daysUntilOccurrence(from: referenceDate) ?? Int.max
            let lhsPast = lhs.recurrence == .once && lhsDays < 0
            let rhsPast = rhs.recurrence == .once && rhsDays < 0
            if lhsPast != rhsPast { return !lhsPast }
            if lhsDays != rhsDays { return lhsDays < rhsDays }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func edit(_ event: ImportantDateEvent) {
        editorContext = ImportantDateEditorContext(event: event)
    }

    private func save(_ event: ImportantDateEvent) {
        if store.importantDates.contains(where: { $0.id == event.id }) {
            store.updateImportantDate(event.id) { $0 = event }
        } else {
            store.addImportantDate(event)
            if card.featuredImportantDateID == nil {
                store.updateCard(card.id) { $0.featuredImportantDateID = event.id }
            }
        }
    }
}

private struct ImportantDateEditorContext: Identifiable {
    let id = UUID()
    let event: ImportantDateEvent?
}

private struct ImportantDateListView: View {
    let events: [ImportantDateEvent]
    let compact: Bool
    let accent: Color
    let referenceDate: Date
    let edit: (ImportantDateEvent) -> Void

    var body: some View {
        if events.isEmpty {
            ContentUnavailableView {
                Label("还没有重要日期", systemImage: "calendar.badge.plus")
            } description: {
                if !compact { Text("点击右上角加号开始记录") }
            }
            .controlSize(.small)
        } else {
            ScrollView {
                LazyVStack(spacing: compact ? 4 : 7) {
                    ForEach(events) { event in
                        ImportantDateRow(
                            event: event,
                            compact: compact,
                            accent: accent,
                            referenceDate: referenceDate,
                            action: { edit(event) }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ImportantDateRow: View {
    let event: ImportantDateEvent
    let compact: Bool
    let accent: Color
    let referenceDate: Date
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: compact ? 7 : 10) {
                Image(systemName: event.category.symbolName)
                    .font(.system(size: compact ? 13 : 16, weight: .semibold))
                    .foregroundStyle(event.category.color)
                    .frame(width: compact ? 26 : 32, height: compact ? 26 : 32)
                    .background(event.category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(event.title)
                            .font(.system(size: compact ? 11 : 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        if event.isPinned {
                            Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(accent)
                        }
                        if event.reminderDaysBefore != nil {
                            Image(systemName: "bell.fill").font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                    }
                    Text(detailText)
                        .font(.system(size: compact ? 9 : 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(statusNumber)
                        .font(.system(size: compact ? 15 : 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isPast ? .secondary : accent)
                    Text(statusCaption)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: compact ? 36 : 48)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var days: Int { event.daysUntilOccurrence(from: referenceDate) ?? 0 }
    private var isPast: Bool { event.recurrence == .once && days < 0 }

    private var statusNumber: String {
        if days == 0 { return "今天" }
        return "\(abs(days))"
    }

    private var statusCaption: String {
        if days == 0 { return "就是今天" }
        return isPast ? "天前" : "天后"
    }

    private var detailText: String {
        let dateText: String
        if event.recurrence == .yearly {
            dateText = "\(event.date.month)月\(event.date.day)日 · 每年"
        } else if let occurrence = event.storedOccurrence() {
            dateText = occurrence.formatted(date: .abbreviated, time: .omitted)
        } else {
            dateText = "日期待完善"
        }

        guard let occurrence = event.relevantOccurrence(from: referenceDate),
              let number = event.anniversaryNumber(for: occurrence)
        else { return dateText }

        switch event.category {
        case .birthday: return "\(dateText) · \(number)岁"
        case .anniversary: return "\(dateText) · 第\(number)周年"
        default: return dateText
        }
    }
}

private struct ImportantDateCalendarView: View {
    @Binding var month: Date
    @Binding var selectedDay: Date
    let events: [ImportantDateEvent]
    let compact: Bool
    let accent: Color
    let referenceDate: Date
    let edit: (ImportantDateEvent) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    var body: some View {
        VStack(spacing: compact ? 2 : 6) {
            HStack {
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Button(month.formatted(.dateTime.year().month(.wide))) {
                    month = startOfMonth(referenceDate)
                    selectedDay = referenceDate
                }
                .buttonStyle(.plain)
                .font(.system(size: compact ? 10 : 13, weight: .semibold, design: .rounded))
                Spacer()
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)

            LazyVGrid(columns: columns, spacing: compact ? 0 : 2) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: compact ? 7 : 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: compact ? 15 : 30)
                    }
                }
            }
            .padding(.horizontal, 10)

            if !compact {
                let selectedEvents = events.filter { $0.occurs(on: selectedDay) }
                if selectedEvents.isEmpty {
                    Text("\(selectedDay.formatted(.dateTime.month().day()))没有记录")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(selectedEvents, id: \.id) { event in
                                Button {
                                    edit(event)
                                } label: {
                                    Label(event.title, systemImage: event.category.symbolName)
                                        .font(.caption)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(event.category.color.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let dayEvents = events.filter { $0.occurs(on: day) }
        let selected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
        let today = Calendar.current.isDateInToday(day)

        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: compact ? 0 : 2) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.system(size: compact ? 8 : 11, weight: today ? .bold : .regular, design: .rounded))
                    .foregroundStyle(selected ? Color.white : (today ? accent : Color.primary))
                HStack(spacing: 1) {
                    ForEach(Array(dayEvents.prefix(3)), id: \.id) { event in
                        Circle().fill(event.category.color).frame(width: compact ? 2 : 4, height: compact ? 2 : 4)
                    }
                }
                .frame(height: compact ? 2 : 4)
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 15 : 30)
            .background(selected ? accent : .clear, in: RoundedRectangle(cornerRadius: compact ? 4 : 7))
            .overlay {
                if today && !selected {
                    RoundedRectangle(cornerRadius: compact ? 4 : 7).stroke(accent.opacity(0.65), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var calendarDays: [Date?] {
        let calendar = Calendar.current
        let start = startOfMonth(month)
        let dayRange = calendar.range(of: .day, in: .month, for: start) ?? 1..<2
        let weekday = calendar.component(.weekday, from: start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var values = Array<Date?>(repeating: nil, count: leading)
        values.append(contentsOf: dayRange.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: start)
        })
        while values.count % 7 != 0 { values.append(nil) }
        return values
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(0, calendar.firstWeekday - 1)
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }

    private func startOfMonth(_ date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    private func changeMonth(_ value: Int) {
        month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
    }
}

private struct ImportantDateEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let originalEvent: ImportantDateEvent?
    let onSave: (ImportantDateEvent) -> Void
    let onDelete: (ImportantDateEvent) -> Void

    @State private var title: String
    @State private var category: ImportantDateCategory
    @State private var selectedDate: Date
    @State private var recurrence: ImportantDateRecurrence
    @State private var tracksStartYear: Bool
    @State private var startYear: Int
    @State private var notes: String
    @State private var isPinned: Bool
    @State private var leapDayPolicy: ImportantDateLeapDayPolicy
    @State private var reminderEnabled: Bool
    @State private var reminderDaysBefore: Int
    @State private var reminderHour: Int
    @State private var confirmsDeletion = false

    init(
        event: ImportantDateEvent?,
        onSave: @escaping (ImportantDateEvent) -> Void,
        onDelete: @escaping (ImportantDateEvent) -> Void
    ) {
        originalEvent = event
        self.onSave = onSave
        self.onDelete = onDelete

        let calendar = Calendar.current
        let fallbackDate = calendar.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        let resolvedDate = event?.date.representativeGregorianDate(
            from: Date(),
            calendar: calendar
        ) ?? event?.relevantOccurrence() ?? fallbackDate
        let resolvedStartYear = event?.startYear ?? calendar.component(.year, from: resolvedDate)

        _title = State(initialValue: event?.title ?? "")
        _category = State(initialValue: event?.category ?? .other)
        _selectedDate = State(initialValue: resolvedDate)
        _recurrence = State(initialValue: event?.recurrence ?? .yearly)
        _tracksStartYear = State(initialValue: event?.startYear != nil)
        _startYear = State(initialValue: resolvedStartYear)
        _notes = State(initialValue: event?.notes ?? "")
        _isPinned = State(initialValue: event?.isPinned ?? false)
        _leapDayPolicy = State(initialValue: event?.leapDayPolicy ?? .february28)
        _reminderEnabled = State(initialValue: event?.reminderDaysBefore != nil)
        _reminderDaysBefore = State(initialValue: event?.reminderDaysBefore ?? 1)
        _reminderHour = State(initialValue: event?.reminderHour ?? 9)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Text(originalEvent == nil ? "添加重要日期" : "编辑重要日期")
                    .font(.headline)
                Spacer()
                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedTitle.isEmpty)
            }
            .padding()

            Divider()

            Form {
                Section("基本信息") {
                    TextField("名称", text: $title)
                    Picker("分类", selection: $category) {
                        ForEach(ImportantDateCategory.allCases, id: \.self) { value in
                            Label(value.displayName, systemImage: value.symbolName).tag(value)
                        }
                    }
                    DatePicker("日期", selection: $selectedDate, displayedComponents: [.date])
                    Picker("重复", selection: $recurrence) {
                        Text("仅一次").tag(ImportantDateRecurrence.once)
                        Text("每年").tag(ImportantDateRecurrence.yearly)
                    }
                    Toggle("置顶显示", isOn: $isPinned)
                }

                if recurrence == .yearly && (category == .birthday || category == .anniversary) {
                    Section(category == .birthday ? "年龄" : "周年") {
                        Toggle("记录起始年份", isOn: $tracksStartYear)
                        if tracksStartYear {
                            Stepper("起始年份：\(startYear)", value: $startYear, in: 1900...currentYear)
                        }
                    }
                }

                if recurrence == .yearly && selectedMonth == 2 && selectedDay == 29 {
                    Section("非闰年规则") {
                        Picker("按哪一天提醒", selection: $leapDayPolicy) {
                            Text("2月28日").tag(ImportantDateLeapDayPolicy.february28)
                            Text("3月1日").tag(ImportantDateLeapDayPolicy.march1)
                        }
                    }
                }

                Section("本地通知") {
                    Toggle("启用提醒", isOn: $reminderEnabled)
                    if reminderEnabled {
                        Picker("提前", selection: $reminderDaysBefore) {
                            Text("当天").tag(0)
                            Text("提前1天").tag(1)
                            Text("提前3天").tag(3)
                            Text("提前7天").tag(7)
                        }
                        Picker("提醒时间", selection: $reminderHour) {
                            ForEach([8, 9, 10, 12, 18, 20], id: \.self) { hour in
                                Text("\(hour):00").tag(hour)
                            }
                        }
                        Text("首次启用时，macOS 会请求通知权限。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("备注") {
                    TextEditor(text: $notes).frame(minHeight: 60)
                }

                Section {
                    LabeledContent("日历类型", value: "公历")
                    Text("数据结构已预留农历与闰月，农历编辑将在后续版本开放。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if originalEvent != nil {
                    Section {
                        Button("删除这个日期", role: .destructive) {
                            confirmsDeletion = true
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 420, minHeight: 570)
        .confirmationDialog(
            "删除“\(originalEvent?.title ?? "重要日期")”？",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("永久删除", role: .destructive) {
                if let originalEvent { onDelete(originalEvent) }
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("该日期记录和对应的本地提醒都会删除，此操作无法撤销。")
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var selectedMonth: Int { Calendar.current.component(.month, from: selectedDate) }
    private var selectedDay: Int { Calendar.current.component(.day, from: selectedDate) }

    private func save() {
        let now = Date()
        let components = ImportantDateComponents(
            gregorianDate: selectedDate,
            includeYear: recurrence == .once
        )
        let event = ImportantDateEvent(
            id: originalEvent?.id ?? UUID(),
            title: trimmedTitle,
            category: category,
            date: components,
            recurrence: recurrence,
            startYear: recurrence == .yearly
                && tracksStartYear
                && (category == .birthday || category == .anniversary) ? startYear : nil,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            isPinned: isPinned,
            leapDayPolicy: leapDayPolicy,
            reminderDaysBefore: reminderEnabled ? reminderDaysBefore : nil,
            reminderHour: reminderHour,
            createdAt: originalEvent?.createdAt ?? now,
            updatedAt: now
        )
        onSave(event)
        dismiss()
    }
}

private struct TodoCardContent: View {
    @EnvironmentObject private var store: DesktopWorkspaceStore
    @State private var draft = ""
    @State private var filter: TodoFilter = .all
    @FocusState private var isAdding: Bool

    let card: DesktopCard
    let availableSize: CGSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let compact = availableSize.width < 310 || availableSize.height < 300
            let visibleItems = filteredItems

            VStack(spacing: 8) {
                HStack(spacing: 9) {
                    Text(progressText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !compact && !card.todoItems.isEmpty {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 82)
                            .tint(card.theme.palette.accent)
                    }

                    Spacer(minLength: 0)
                    filterControl(compact: compact)
                }
                .padding(.horizontal, 15)

                ScrollView {
                    LazyVStack(spacing: 5) {
                        if visibleItems.isEmpty {
                            ContentUnavailableView {
                                Label(emptyStateTitle, systemImage: filter.emptySymbol)
                            } description: {
                                if card.todoItems.isEmpty {
                                    Text("在下方输入后按回车")
                                }
                            }
                            .controlSize(.small)
                            .padding(.top, compact ? 6 : 16)
                        } else {
                            ForEach(visibleItems) { item in
                                TodoItemRow(
                                    cardID: card.id,
                                    item: item,
                                    compact: compact,
                                    accent: card.theme.palette.accent,
                                    referenceDate: context.date
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .animation(.easeInOut(duration: 0.22), value: card.todoItems.map(\.isCompleted))
                }

                HStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(card.theme.palette.accent)
                    TextField("添加待办，按回车", text: $draft)
                        .textFieldStyle(.plain)
                        .focused($isAdding)
                        .onSubmit(addTodo)
                    Button(action: addTodo) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 17))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(card.theme.palette.accent)
                    .disabled(trimmedDraft.isEmpty)
                    .opacity(trimmedDraft.isEmpty ? 0.35 : 1)
                }
                .padding(.horizontal, 12)
                .frame(height: compact ? 34 : 38)
                .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .padding(.horizontal, 11)
                .padding(.bottom, 11)
            }
        }
    }

    @ViewBuilder
    private func filterControl(compact: Bool) -> some View {
        if compact {
            Menu {
                filterButtons
            } label: {
                Label(filter.displayName, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("筛选待办")
        } else {
            Picker("筛选", selection: $filter) {
                ForEach(TodoFilter.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var filterButtons: some View {
        ForEach(TodoFilter.allCases) { option in
            Button {
                filter = option
            } label: {
                Label(option.displayName, systemImage: filter == option ? "checkmark" : option.symbolName)
            }
        }
    }

    private var filteredItems: [TinyDeskTodoItem] {
        card.orderedTodoItems.filter { item in
            switch filter {
            case .all: return true
            case .pending: return !item.isCompleted
            case .completed: return item.isCompleted
            }
        }
    }

    private var emptyStateTitle: String {
        if card.todoItems.isEmpty { return "没有待办" }
        switch filter {
        case .all: return "没有待办"
        case .pending: return "没有未完成事项"
        case .completed: return "还没有已完成事项"
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var progress: Double {
        guard !card.todoItems.isEmpty else { return 0 }
        return Double(card.completedTodoCount) / Double(card.todoItems.count)
    }

    private var progressText: String {
        "已完成 \(card.completedTodoCount) / \(card.todoItems.count)"
    }

    private func addTodo() {
        let title = trimmedDraft
        guard !title.isEmpty else { return }
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        store.updateCard(card.id) { card in
            card.todoItems.append(TinyDeskTodoItem(title: title, dueDate: today, createdAt: now))
        }
        draft = ""
        filter = .all
        isAdding = true
    }
}

private enum TodoFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case completed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .pending: return "未完成"
        case .completed: return "已完成"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "list.bullet"
        case .pending: return "circle"
        case .completed: return "checkmark.circle"
        }
    }

    var emptySymbol: String {
        switch self {
        case .all: return "checkmark.circle"
        case .pending: return "checkmark.circle.fill"
        case .completed: return "clock"
        }
    }
}

private struct TodoItemRow: View {
    @EnvironmentObject private var store: DesktopWorkspaceStore
    @State private var isHovering = false

    let cardID: UUID
    let item: TinyDeskTodoItem
    let compact: Bool
    let accent: Color
    let referenceDate: Date

    var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            Button(action: toggleCompleted) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: compact ? 15 : 17, weight: .medium))
                    .foregroundStyle(item.isCompleted ? accent : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                TextField("待办内容", text: titleBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: compact ? 12 : 13, design: .rounded))
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                if let timingText {
                    Label(timingText, systemImage: timingSymbol)
                        .font(.system(size: compact ? 9 : 10, weight: .medium, design: .rounded))
                        .foregroundStyle(isOverdue ? .red : .secondary)
                        .lineLimit(1)
                }
            }

            if !compact {
                Menu {
                    priorityMenu
                    Divider()
                    dueDateButtons
                } label: {
                    Circle()
                        .fill(item.priority.color)
                        .frame(width: 8, height: 8)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("优先级与计划日期")
            }

            Button(action: deleteItem) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovering || compact ? 0.7 : 0)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: compact ? 34 : 38)
        .background(.white.opacity(isHovering ? 0.1 : 0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { isHovering = $0 }
        .contextMenu {
            Menu("优先级") {
                priorityMenu
            }
            Menu("计划日期") {
                dueDateButtons
            }
            Divider()
            Button(item.isCompleted ? "标记为未完成" : "标记为完成", action: toggleCompleted)
            Button("删除", role: .destructive, action: deleteItem)
        }
    }

    private var timingText: String? {
        guard !item.isCompleted else { return nil }
        let offset = item.scheduledDayOffset(from: referenceDate)
        if offset == -1 { return "昨日未完成" }
        if offset < -1 { return "逾期 \(-offset) 天" }
        if offset == 0 { return "今日" }
        if offset == 1 { return "明日" }
        return item.scheduledDate.formatted(.dateTime.month().day())
    }

    private var timingSymbol: String {
        isOverdue ? "exclamationmark.circle.fill" : "calendar"
    }

    private var isOverdue: Bool {
        !item.isCompleted && item.scheduledDayOffset(from: referenceDate) < 0
    }

    @ViewBuilder
    private var dueDateButtons: some View {
        Button("今天") { setDueDate(dayOffset: 0) }
        Button("明天") { setDueDate(dayOffset: 1) }
        if item.dueDate != nil {
            Button("使用创建日期") { updateItem { $0.dueDate = nil } }
        }
    }

    @ViewBuilder
    private var priorityMenu: some View {
        ForEach(TodoPriority.allCases, id: \.self) { priority in
            Button {
                updateItem { $0.priority = priority }
            } label: {
                Label(priority.displayName, systemImage: item.priority == priority ? "checkmark" : priority.symbolName)
            }
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: {
                store.card(withID: cardID)?.todoItems.first(where: { $0.id == item.id })?.title ?? ""
            },
            set: { value in updateItem { $0.title = value } }
        )
    }

    private func updateItem(_ mutation: (inout TinyDeskTodoItem) -> Void) {
        store.updateCard(cardID) { card in
            guard let index = card.todoItems.firstIndex(where: { $0.id == item.id }) else { return }
            mutation(&card.todoItems[index])
        }
    }

    private func toggleCompleted() {
        updateItem { $0.isCompleted.toggle() }
    }

    private func deleteItem() {
        store.updateCard(cardID) { card in
            card.todoItems.removeAll { $0.id == item.id }
        }
    }

    private func setDueDate(dayOffset: Int) {
        let today = Calendar.current.startOfDay(for: Date())
        let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: today)
        updateItem { $0.dueDate = date }
    }
}

private struct CardSurface: View {
    let theme: DesktopCardTheme
    let style: DesktopCardSurfaceStyle

    @ViewBuilder
    var body: some View {
        switch style {
        case .frosted:
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: theme.palette.gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                accentGlow(opacity: 0.22)
            }
        case .transparent:
            ZStack {
                Color.clear
                LinearGradient(
                    colors: [theme.palette.accent.opacity(0.10), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                accentGlow(opacity: 0.12)
            }
        case .opaque:
            ZStack {
                Rectangle().fill(Color(nsColor: .windowBackgroundColor))
                LinearGradient(
                    colors: [theme.palette.accent.opacity(0.28), theme.palette.accent.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                accentGlow(opacity: 0.18)
            }
        }
    }

    private func accentGlow(opacity: Double) -> some View {
        RadialGradient(
            colors: [theme.palette.accent.opacity(opacity), .clear],
            center: .topLeading,
            startRadius: 0,
            endRadius: 320
        )
    }
}

private struct ResizeHint: View {
    var body: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.isEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.isEnabled = isEnabled
    }

    final class DragView: NSView {
        var isEnabled = true

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            window?.performDrag(with: event)
        }
    }
}

struct CardPalette {
    let accent: Color
    let gradient: [Color]
}

extension DesktopCardKind {
    var symbolName: String {
        switch self {
        case .sticky: return "note.text"
        case .countdown: return "calendar.badge.clock"
        case .todo: return "checklist"
        }
    }
}

private extension ImportantDateCategory {
    var displayName: String {
        switch self {
        case .birthday: return "生日"
        case .anniversary: return "纪念日"
        case .holiday: return "节日"
        case .other: return "其他"
        }
    }

    var symbolName: String {
        switch self {
        case .birthday: return "birthday.cake.fill"
        case .anniversary: return "heart.fill"
        case .holiday: return "sparkles"
        case .other: return "bookmark.fill"
        }
    }

    var color: Color {
        switch self {
        case .birthday: return .pink
        case .anniversary: return .purple
        case .holiday: return .orange
        case .other: return .blue
        }
    }
}

extension DesktopCardTheme {
    var displayName: String {
        switch self {
        case .graphite: return "石墨"
        case .sand: return "暖沙"
        case .mint: return "薄荷"
        case .rose: return "玫瑰"
        case .ocean: return "海洋"
        }
    }

    var palette: CardPalette {
        switch self {
        case .graphite:
            return CardPalette(
                accent: Color(red: 0.66, green: 0.72, blue: 0.82),
                gradient: [.black.opacity(0.36), Color.blue.opacity(0.10)]
            )
        case .sand:
            return CardPalette(
                accent: Color(red: 0.96, green: 0.68, blue: 0.25),
                gradient: [Color.orange.opacity(0.25), Color.yellow.opacity(0.08)]
            )
        case .mint:
            return CardPalette(
                accent: Color(red: 0.28, green: 0.78, blue: 0.58),
                gradient: [Color.green.opacity(0.20), Color.teal.opacity(0.08)]
            )
        case .rose:
            return CardPalette(
                accent: Color(red: 0.96, green: 0.42, blue: 0.56),
                gradient: [Color.pink.opacity(0.24), Color.purple.opacity(0.08)]
            )
        case .ocean:
            return CardPalette(
                accent: Color(red: 0.24, green: 0.65, blue: 0.96),
                gradient: [Color.blue.opacity(0.24), Color.cyan.opacity(0.08)]
            )
        }
    }
}

extension DesktopCardSurfaceStyle {
    var displayName: String {
        switch self {
        case .frosted: return "毛玻璃"
        case .transparent: return "透明"
        case .opaque: return "不透明"
        }
    }

    var symbolName: String {
        switch self {
        case .frosted: return "circle.lefthalf.filled"
        case .transparent: return "circle.dotted"
        case .opaque: return "circle.fill"
        }
    }
}

private extension TodoPriority {
    var displayName: String {
        switch self {
        case .normal: return "普通"
        case .important: return "重要"
        case .urgent: return "紧急"
        }
    }

    var symbolName: String {
        switch self {
        case .normal: return "circle"
        case .important: return "exclamationmark.circle"
        case .urgent: return "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .normal: return .secondary
        case .important: return .orange
        case .urgent: return .red
        }
    }
}
