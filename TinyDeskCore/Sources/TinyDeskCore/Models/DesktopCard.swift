import Foundation

public enum DesktopCardKind: String, Codable, Sendable, CaseIterable {
    case sticky
    case countdown
    case todo
    /// 资料库桌面摘要卡片（v2.5）：只读展示文档摘要，双击打开资料库对应文档。
    case deskRef
}

public enum DesktopCardTheme: String, Codable, Sendable, CaseIterable {
    case graphite
    case sand
    case mint
    case rose
    case ocean
}

public enum DesktopCardSurfaceStyle: String, Codable, Sendable, CaseIterable {
    case frosted
    case transparent
    case opaque
}

public enum ImportantDateCategory: String, Codable, Sendable, CaseIterable {
    case birthday
    case anniversary
    case holiday
    case other
}

public enum ImportantDateRecurrence: String, Codable, Sendable, CaseIterable {
    case once
    case yearly
}

public enum ImportantDateCalendarSystem: String, Codable, Sendable, CaseIterable {
    case gregorian
    case chineseLunar
}

public enum ImportantDateLeapDayPolicy: String, Codable, Sendable, CaseIterable {
    case february28
    case march1
}

public enum ImportantDateLunarLeapMonthPolicy: String, Codable, Sendable, CaseIterable {
    /// 在没有对应闰月的农历年份，按同名普通月庆祝。
    case regularMonthFallback
    /// 仅在存在对应闰月的年份庆祝。
    case strictLeapMonth
}

public enum SystemCalendarLinkAuthority: String, Codable, Sendable, CaseIterable {
    /// 系统日历是标题、日期和重复规则的来源。
    case systemCalendar
    /// TinyDesk 是来源，修改后会写回已关联的系统日历事件。
    case tinyDesk
}

public struct SystemCalendarLink: Codable, Sendable, Equatable {
    public var calendarIdentifier: String
    public var calendarTitle: String
    public var eventIdentifier: String
    public var externalIdentifier: String?
    public var authority: SystemCalendarLinkAuthority
    public var isReadOnly: Bool
    public var lastSyncedAt: Date?

    public init(
        calendarIdentifier: String,
        calendarTitle: String,
        eventIdentifier: String,
        externalIdentifier: String? = nil,
        authority: SystemCalendarLinkAuthority,
        isReadOnly: Bool,
        lastSyncedAt: Date? = nil
    ) {
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.authority = authority
        self.isReadOnly = isReadOnly
        self.lastSyncedAt = lastSyncedAt
    }
}

public enum ImportantDateViewMode: String, Codable, Sendable, CaseIterable {
    case calendar
    case list
}

public struct ImportantDateComponents: Codable, Sendable, Equatable {
    public var calendarSystem: ImportantDateCalendarSystem
    public var year: Int?
    public var month: Int
    public var day: Int
    public var isLeapMonth: Bool

    public init(
        calendarSystem: ImportantDateCalendarSystem = .gregorian,
        year: Int? = nil,
        month: Int,
        day: Int,
        isLeapMonth: Bool = false
    ) {
        self.calendarSystem = calendarSystem
        self.year = year
        self.month = month
        self.day = day
        self.isLeapMonth = isLeapMonth
    }

    public init(gregorianDate date: Date, calendar: Calendar = .current, includeYear: Bool = true) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(
            calendarSystem: .gregorian,
            year: includeYear ? components.year : nil,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    public func representativeGregorianDate(
        from referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let referenceYear = calendar.component(.year, from: referenceDate)
        switch calendarSystem {
        case .gregorian:
            let candidateYears = year.map { [$0] } ?? Array(referenceYear...(referenceYear + 8))
            for candidateYear in candidateYears {
                var components = DateComponents()
                components.calendar = calendar
                components.timeZone = calendar.timeZone
                components.year = candidateYear
                components.month = month
                components.day = day
                guard let value = calendar.date(from: components) else { continue }
                let resolved = calendar.dateComponents([.year, .month, .day], from: value)
                if resolved.year == candidateYear, resolved.month == month, resolved.day == day {
                    return calendar.startOfDay(for: value)
                }
            }
        case .chineseLunar:
            if let year {
                return ChineseLunarCalendar.occurrence(
                    inLunarYear: year,
                    month: month,
                    day: day,
                    isLeapMonth: isLeapMonth,
                    leapMonthPolicy: .regularMonthFallback,
                    calendar: calendar
                )
            }
            for candidateYear in referenceYear...(referenceYear + 8) {
                if let value = ChineseLunarCalendar.occurrence(
                    inGregorianYear: candidateYear,
                    month: month,
                    day: day,
                    isLeapMonth: isLeapMonth,
                    leapMonthPolicy: .regularMonthFallback,
                    calendar: calendar
                ) {
                    return value
                }
            }
        }
        return nil
    }
}

public struct ImportantDateEvent: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var category: ImportantDateCategory
    public var date: ImportantDateComponents
    public var recurrence: ImportantDateRecurrence
    public var startYear: Int?
    public var notes: String
    public var isPinned: Bool
    public var leapDayPolicy: ImportantDateLeapDayPolicy
    /// 缺失时按 v2.0 的默认规则“普通月补过”处理，兼容 schema 2 工作区。
    public var lunarLeapMonthPolicy: ImportantDateLunarLeapMonthPolicy?
    /// 可选关联信息，避免旧版工作区因新增字段无法读取。
    public var systemCalendarLink: SystemCalendarLink?
    public var reminderDaysBefore: Int?
    public var reminderHour: Int
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        category: ImportantDateCategory = .other,
        date: ImportantDateComponents,
        recurrence: ImportantDateRecurrence = .once,
        startYear: Int? = nil,
        notes: String = "",
        isPinned: Bool = false,
        leapDayPolicy: ImportantDateLeapDayPolicy = .february28,
        lunarLeapMonthPolicy: ImportantDateLunarLeapMonthPolicy? = nil,
        systemCalendarLink: SystemCalendarLink? = nil,
        reminderDaysBefore: Int? = nil,
        reminderHour: Int = 9,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.date = date
        self.recurrence = recurrence
        self.startYear = startYear
        self.notes = notes
        self.isPinned = isPinned
        self.leapDayPolicy = leapDayPolicy
        self.lunarLeapMonthPolicy = lunarLeapMonthPolicy
        self.systemCalendarLink = systemCalendarLink
        self.reminderDaysBefore = reminderDaysBefore
        self.reminderHour = min(max(reminderHour, 0), 23)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func occurrence(inYear year: Int, calendar: Calendar = .current) -> Date? {
        if recurrence == .yearly, let startYear, year < startYear { return nil }

        if date.calendarSystem == .chineseLunar {
            return ChineseLunarCalendar.occurrence(
                inGregorianYear: year,
                month: date.month,
                day: date.day,
                isLeapMonth: date.isLeapMonth,
                leapMonthPolicy: resolvedLunarLeapMonthPolicy,
                calendar: calendar
            )
        }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = date.month
        components.day = date.day

        if let value = calendar.date(from: components) {
            let resolved = calendar.dateComponents([.year, .month, .day], from: value)
            if resolved.year == year, resolved.month == date.month, resolved.day == date.day {
                return calendar.startOfDay(for: value)
            }
        }

        guard date.month == 2, date.day == 29 else { return nil }
        components.month = leapDayPolicy == .february28 ? 2 : 3
        components.day = leapDayPolicy == .february28 ? 28 : 1
        return calendar.date(from: components).map(calendar.startOfDay(for:))
    }

    public func storedOccurrence(calendar: Calendar = .current) -> Date? {
        guard let year = date.year else { return nil }
        if date.calendarSystem == .chineseLunar {
            return ChineseLunarCalendar.occurrence(
                inLunarYear: year,
                month: date.month,
                day: date.day,
                isLeapMonth: date.isLeapMonth,
                leapMonthPolicy: resolvedLunarLeapMonthPolicy,
                calendar: calendar
            )
        }
        return occurrence(inYear: year, calendar: calendar)
    }

    public func relevantOccurrence(from referenceDate: Date = Date(), calendar: Calendar = .current) -> Date? {
        if recurrence == .once {
            return storedOccurrence(calendar: calendar)
        }

        let today = calendar.startOfDay(for: referenceDate)
        let currentYear = calendar.component(.year, from: today)
        let earliestYear = max(currentYear, startYear ?? currentYear)
        if let current = occurrence(inYear: earliestYear, calendar: calendar), current >= today {
            return current
        }
        return occurrence(inYear: earliestYear + 1, calendar: calendar)
    }

    public func daysUntilOccurrence(from referenceDate: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let occurrence = relevantOccurrence(from: referenceDate, calendar: calendar) else { return nil }
        let today = calendar.startOfDay(for: referenceDate)
        return calendar.dateComponents([.day], from: today, to: occurrence).day
    }

    public func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        if recurrence == .yearly {
            guard let year = components.year else { return false }
            guard let occurrence = occurrence(inYear: year, calendar: calendar) else { return false }
            return calendar.isDate(occurrence, inSameDayAs: day)
        }
        guard let occurrence = storedOccurrence(calendar: calendar) else { return false }
        return calendar.isDate(occurrence, inSameDayAs: day)
    }

    public func anniversaryNumber(for occurrence: Date, calendar: Calendar = .current) -> Int? {
        guard let startYear else { return nil }
        let year = calendar.component(.year, from: occurrence)
        let value = year - startYear
        return value > 0 ? value : nil
    }

    public var resolvedLunarLeapMonthPolicy: ImportantDateLunarLeapMonthPolicy {
        lunarLeapMonthPolicy ?? .regularMonthFallback
    }

    public var isSystemCalendarManaged: Bool {
        systemCalendarLink?.authority == .systemCalendar
    }
}

public enum TodoPriority: Int, Codable, Sendable, CaseIterable, Comparable {
    case normal = 0
    case important = 1
    case urgent = 2

    public static func < (lhs: TodoPriority, rhs: TodoPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct TinyDeskTodoItem: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var isCompleted: Bool
    public var priority: TodoPriority
    public var dueDate: Date?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        priority: TodoPriority = .normal,
        dueDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.priority = priority
        self.dueDate = dueDate
        self.createdAt = createdAt
    }

    public var scheduledDate: Date {
        dueDate ?? createdAt
    }

    public func scheduledDayOffset(
        from date: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let today = calendar.startOfDay(for: date)
        let scheduledDay = calendar.startOfDay(for: scheduledDate)
        return calendar.dateComponents([.day], from: today, to: scheduledDay).day ?? 0
    }
}

public struct DesktopCardFrame: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var screenIdentifier: String?

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        screenIdentifier: String? = nil
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.screenIdentifier = screenIdentifier
    }
}

public struct DesktopCard: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var kind: DesktopCardKind
    public var title: String
    public var noteText: String
    public var noteRichTextData: Data?
    public var targetDate: Date
    public var todoItems: [TinyDeskTodoItem]
    public var theme: DesktopCardTheme
    public var surfaceStyle: DesktopCardSurfaceStyle?
    public var importantDateViewMode: ImportantDateViewMode?
    public var importantDateCategoryFilter: ImportantDateCategory?
    public var featuredImportantDateID: UUID?
    public var isPositionLocked: Bool?
    /// 快捷便签可使用真正的 floating window；缺失时保持旧版桌面层行为。
    public var isAlwaysOnTop: Bool?
    // MARK: 资料库摘要卡片（v2.5）
    /// 关联的资料库文档 ID；仅 `kind == .deskRef` 时有意义。
    public var referenceDocumentID: UUID?
    /// 文档标题缓存；资料库中改名时同步更新。
    public var referenceDocumentTitle: String?
    /// 文档摘要缓存。
    public var referenceDocumentSummary: String?
    /// 标签名缓存，用于摘要卡片展示。
    public var referenceDocumentTags: [String]?
    public var isVisible: Bool
    public var frame: DesktopCardFrame?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: DesktopCardKind,
        title: String,
        noteText: String = "",
        noteRichTextData: Data? = nil,
        targetDate: Date = Date(),
        todoItems: [TinyDeskTodoItem] = [],
        theme: DesktopCardTheme = .graphite,
        surfaceStyle: DesktopCardSurfaceStyle? = .frosted,
        importantDateViewMode: ImportantDateViewMode? = .calendar,
        importantDateCategoryFilter: ImportantDateCategory? = nil,
        featuredImportantDateID: UUID? = nil,
        isPositionLocked: Bool? = false,
        isAlwaysOnTop: Bool? = false,
        referenceDocumentID: UUID? = nil,
        referenceDocumentTitle: String? = nil,
        referenceDocumentSummary: String? = nil,
        referenceDocumentTags: [String]? = nil,
        isVisible: Bool = true,
        frame: DesktopCardFrame? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.noteText = noteText
        self.noteRichTextData = noteRichTextData
        self.targetDate = targetDate
        self.todoItems = todoItems
        self.theme = theme
        self.surfaceStyle = surfaceStyle
        self.importantDateViewMode = importantDateViewMode
        self.importantDateCategoryFilter = importantDateCategoryFilter
        self.featuredImportantDateID = featuredImportantDateID
        self.isPositionLocked = isPositionLocked
        self.isAlwaysOnTop = isAlwaysOnTop
        self.referenceDocumentID = referenceDocumentID
        self.referenceDocumentTitle = referenceDocumentTitle
        self.referenceDocumentSummary = referenceDocumentSummary
        self.referenceDocumentTags = referenceDocumentTags
        self.isVisible = isVisible
        self.frame = frame
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func sticky(now: Date = Date()) -> DesktopCard {
        DesktopCard(
            kind: .sticky,
            title: "便签",
            noteText: "点击这里开始记录…",
            targetDate: now,
            theme: .sand,
            createdAt: now,
            updatedAt: now
        )
    }

    public static func countdown(now: Date = Date(), calendar: Calendar = .current) -> DesktopCard {
        let start = calendar.startOfDay(for: now)
        let target = calendar.date(byAdding: .day, value: 30, to: start) ?? now
        return DesktopCard(
            kind: .countdown,
            title: "重要日子",
            targetDate: target,
            theme: .rose,
            createdAt: now,
            updatedAt: now
        )
    }

    public static func todo(now: Date = Date(), calendar: Calendar = .current) -> DesktopCard {
        DesktopCard(
            kind: .todo,
            title: "今日待办",
            targetDate: now,
            todoItems: [
                TinyDeskTodoItem(
                    title: "点击添加新的待办",
                    dueDate: calendar.startOfDay(for: now),
                    createdAt: now
                ),
            ],
            theme: .mint,
            createdAt: now,
            updatedAt: now
        )
    }

    /// 资料库桌面摘要卡片（v2.5）。
    public static func deskRef(
        documentID: UUID,
        documentTitle: String,
        documentSummary: String,
        documentTags: [String],
        now: Date = Date()
    ) -> DesktopCard {
        DesktopCard(
            kind: .deskRef,
            title: documentTitle,
            targetDate: now,
            theme: .sand,
            referenceDocumentID: documentID,
            referenceDocumentTitle: documentTitle,
            referenceDocumentSummary: documentSummary,
            referenceDocumentTags: documentTags,
            createdAt: now,
            updatedAt: now
        )
    }

    public mutating func markUpdated(at date: Date = Date()) {
        updatedAt = date
    }

    public func remainingDays(from date: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: targetDate)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    public var completedTodoCount: Int {
        todoItems.lazy.filter(\.isCompleted).count
    }

    public var pendingTodoCount: Int {
        todoItems.count - completedTodoCount
    }

    public var orderedTodoItems: [TinyDeskTodoItem] {
        todoItems.filter { !$0.isCompleted } + todoItems.filter(\.isCompleted)
    }

    public var resolvedSurfaceStyle: DesktopCardSurfaceStyle {
        surfaceStyle ?? .frosted
    }

    public var resolvedImportantDateViewMode: ImportantDateViewMode {
        importantDateViewMode ?? .calendar
    }

    public var resolvedIsPositionLocked: Bool {
        isPositionLocked ?? false
    }

    public var resolvedIsAlwaysOnTop: Bool {
        isAlwaysOnTop ?? false
    }
}

public struct TinyDeskWorkspace: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var cards: [DesktopCard]
    public var importantDates: [ImportantDateEvent]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        cards: [DesktopCard],
        importantDates: [ImportantDateEvent] = []
    ) {
        self.schemaVersion = schemaVersion
        self.cards = cards
        self.importantDates = importantDates
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case cards
        case importantDates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        cards = try container.decode([DesktopCard].self, forKey: .cards)
        importantDates = try container.decodeIfPresent([ImportantDateEvent].self, forKey: .importantDates) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(cards, forKey: .cards)
        try container.encode(importantDates, forKey: .importantDates)
    }

    public static func seeded(now: Date = Date(), calendar: Calendar = .current) -> TinyDeskWorkspace {
        var countdown = DesktopCard.countdown(now: now, calendar: calendar)
        let event = ImportantDateEvent(
            title: countdown.title,
            date: ImportantDateComponents(gregorianDate: countdown.targetDate, calendar: calendar),
            recurrence: .once,
            createdAt: now,
            updatedAt: now
        )
        countdown.featuredImportantDateID = event.id
        return TinyDeskWorkspace(
            cards: [
                .sticky(now: now),
                countdown,
                .todo(now: now, calendar: calendar),
            ],
            importantDates: [event]
        )
    }

    public func migratedToCurrentSchema(calendar: Calendar = .current) -> TinyDeskWorkspace {
        guard schemaVersion < Self.currentSchemaVersion else { return self }
        var migrated = self

        if migrated.schemaVersion < 2 {
            for index in migrated.cards.indices where migrated.cards[index].kind == .countdown {
                let card = migrated.cards[index]
                let event = ImportantDateEvent(
                    title: card.title.isEmpty ? "重要日子" : card.title,
                    date: ImportantDateComponents(gregorianDate: card.targetDate, calendar: calendar),
                    recurrence: .once,
                    createdAt: card.createdAt,
                    updatedAt: card.updatedAt
                )
                migrated.importantDates.append(event)
                migrated.cards[index].featuredImportantDateID = event.id
                migrated.cards[index].importantDateViewMode = .calendar
            }
        }

        if migrated.schemaVersion < 3 {
            // 新增字段均为可选并带默认解析，不改变旧卡片及重要日期的既有行为。
            for index in migrated.cards.indices {
                migrated.cards[index].isAlwaysOnTop = false
            }
        }

        migrated.schemaVersion = Self.currentSchemaVersion
        return migrated
    }
}
