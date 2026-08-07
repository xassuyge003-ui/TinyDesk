import EventKit
import Foundation
import TinyDeskCore

struct SystemCalendarDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let sourceTitle: String
    let isWritable: Bool
}

struct SystemCalendarCandidate: Identifiable, Hashable {
    /// 日历标识与事件标识拼接而成，仅供 SwiftUI 列表和选择状态使用。
    let id: String
    /// EventKit 用于后续重新定位同一事件的原始标识。
    let eventIdentifier: String
    let title: String
    let startDate: Date
    let isAllDay: Bool
    let recurrence: ImportantDateRecurrence
    let calendarIdentifier: String
    let calendarTitle: String
    let externalIdentifier: String?
    let isReadOnly: Bool
    let notes: String
}

@MainActor
final class SystemCalendarService: ObservableObject {
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var calendars: [SystemCalendarDescriptor] = []
    @Published private(set) var lastError: String?
    /// 最近一次读取候选事件时被跳过的内容说明（重复规则不受支持/带具体时间）。
    @Published private(set) var lastImportNote: String?

    private let eventStore = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        refreshCalendars()
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshCalendars()
            }
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    var canRequestAccess: Bool {
        authorizationStatus == .notDetermined
    }

    var readableCalendars: [SystemCalendarDescriptor] {
        calendars
    }

    var writableCalendars: [SystemCalendarDescriptor] {
        calendars.filter(\.isWritable)
    }

    func requestFullAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            refreshCalendars()
            if !granted { lastError = "没有获得系统日历访问权限。" }
            return granted
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            lastError = "无法请求系统日历权限：\(error.localizedDescription)"
            return false
        }
    }

    func refreshCalendars() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard hasFullAccess else {
            calendars = []
            return
        }

        calendars = eventStore.calendars(for: .event)
            .map {
                SystemCalendarDescriptor(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    sourceTitle: $0.source.title,
                    isWritable: $0.allowsContentModifications && !$0.isImmutable
                )
            }
            .sorted {
                if $0.sourceTitle != $1.sourceTitle {
                    return $0.sourceTitle.localizedStandardCompare($1.sourceTitle) == .orderedAscending
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func fetchCandidates(
        calendarIdentifiers: Set<String>,
        start: Date,
        end: Date
    ) -> [SystemCalendarCandidate] {
        guard hasFullAccess else { return [] }
        let selectedCalendars = eventStore.calendars(for: .event).filter {
            calendarIdentifiers.isEmpty || calendarIdentifiers.contains($0.calendarIdentifier)
        }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: selectedCalendars)
        let events = eventStore.events(matching: predicate)
        var uniqueEvents: [String: EKEvent] = [:]
        var skippedTimedCount = 0
        var skippedRuleCount = 0

        for event in events {
            guard !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard supportsImportantDateRecurrence(event) else {
                skippedRuleCount += 1
                continue
            }
            // TinyDesk 重要日期是日期级模型；带具体时刻的事件不能静默变成全天。
            guard event.isAllDay else {
                skippedTimedCount += 1
                continue
            }
            let externalIdentifier = event.calendarItemExternalIdentifier?.isEmpty == false
                ? event.calendarItemExternalIdentifier
                : nil
            let stableIdentifier = externalIdentifier ?? event.eventIdentifier ?? UUID().uuidString
            let key = "\(event.calendar.calendarIdentifier)|\(stableIdentifier)"
            if let existing = uniqueEvents[key], existing.startDate <= event.startDate { continue }
            uniqueEvents[key] = event
        }

        var notes: [String] = []
        if skippedRuleCount > 0 {
            notes.append("已跳过 \(skippedRuleCount) 个重复规则不受支持的事件（只支持每年一次、无结束日期的规则）。")
        }
        if skippedTimedCount > 0 {
            notes.append("已跳过 \(skippedTimedCount) 个带具体时间的事件（TinyDesk 只支持全天重要日期）。")
        }
        lastImportNote = notes.isEmpty ? nil : notes.joined(separator: " ")

        return uniqueEvents.values
            .map(candidate(from:))
            .sorted { $0.startDate < $1.startDate }
    }

    func makeImportantDate(from candidate: SystemCalendarCandidate) -> ImportantDateEvent {
        let category = inferredCategory(title: candidate.title, calendarTitle: candidate.calendarTitle)
        let date = ImportantDateComponents(
            gregorianDate: candidate.startDate,
            includeYear: candidate.recurrence == .once
        )
        return ImportantDateEvent(
            title: candidate.title,
            category: category,
            date: date,
            recurrence: candidate.recurrence,
            notes: candidate.notes,
            systemCalendarLink: SystemCalendarLink(
                calendarIdentifier: candidate.calendarIdentifier,
                calendarTitle: candidate.calendarTitle,
                eventIdentifier: candidate.eventIdentifier,
                externalIdentifier: candidate.externalIdentifier,
                authority: .systemCalendar,
                isReadOnly: candidate.isReadOnly,
                lastSyncedAt: Date()
            )
        )
    }

    func refreshLinkedEvent(_ local: ImportantDateEvent) -> ImportantDateEvent? {
        guard hasFullAccess, let link = local.systemCalendarLink else { return local }

        switch link.authority {
        case .tinyDesk:
            do {
                return try write(local, to: link)
            } catch {
                lastError = "无法更新“\(local.title)”到系统日历：\(error.localizedDescription)"
                return local
            }
        case .systemCalendar:
            guard let source = systemEvent(for: link) else {
                var unlinked = local
                unlinked.systemCalendarLink = nil
                lastError = "系统日历中的“\(local.title)”事件已不存在，已解除本地关联。"
                return unlinked
            }
            return merging(local: local, source: source)
        }
    }

    func export(_ event: ImportantDateEvent, to calendarIdentifier: String) throws -> ImportantDateEvent {
        guard hasFullAccess else { throw SystemCalendarServiceError.accessRequired }
        guard let calendar = eventStore.calendar(withIdentifier: calendarIdentifier) else {
            throw SystemCalendarServiceError.calendarNotFound
        }
        guard calendar.allowsContentModifications, !calendar.isImmutable else {
            throw SystemCalendarServiceError.calendarReadOnly
        }

        let link = SystemCalendarLink(
            calendarIdentifier: calendar.calendarIdentifier,
            calendarTitle: calendar.title,
            eventIdentifier: "",
            authority: .tinyDesk,
            isReadOnly: false
        )
        return try write(event, to: link)
    }

    func removeLink(from event: ImportantDateEvent) -> ImportantDateEvent {
        var unlinked = event
        unlinked.systemCalendarLink = nil
        return unlinked
    }

    private func candidate(from event: EKEvent) -> SystemCalendarCandidate {
        let externalIdentifier = event.calendarItemExternalIdentifier?.isEmpty == false
            ? event.calendarItemExternalIdentifier
            : nil
        let eventIdentifier = event.eventIdentifier ?? externalIdentifier ?? UUID().uuidString
        let recurrence: ImportantDateRecurrence = isSimpleYearlyRecurrence(event) ? .yearly : .once
        return SystemCalendarCandidate(
            id: "\(event.calendar.calendarIdentifier)|\(eventIdentifier)",
            eventIdentifier: eventIdentifier,
            title: event.title,
            startDate: event.startDate,
            isAllDay: event.isAllDay,
            recurrence: recurrence,
            calendarIdentifier: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            externalIdentifier: externalIdentifier,
            isReadOnly: !event.calendar.allowsContentModifications || event.calendar.isImmutable,
            notes: event.notes ?? ""
        )
    }

    /// 仅“每年一次、interval 为 1、无结束日期”的规则才能映射为 TinyDesk 的每年重复。
    private func supportsImportantDateRecurrence(_ event: EKEvent) -> Bool {
        guard let rules = event.recurrenceRules, !rules.isEmpty else { return true }
        return rules.allSatisfy {
            $0.frequency == .yearly && $0.interval == 1 && $0.recurrenceEnd == nil
        }
    }

    private func isSimpleYearlyRecurrence(_ event: EKEvent) -> Bool {
        guard let rules = event.recurrenceRules, !rules.isEmpty else { return false }
        return rules.allSatisfy {
            $0.frequency == .yearly && $0.interval == 1 && $0.recurrenceEnd == nil
        }
    }

    private func systemEvent(for link: SystemCalendarLink) -> EKEvent? {
        if !link.eventIdentifier.isEmpty, let event = eventStore.event(withIdentifier: link.eventIdentifier) {
            return event
        }
        guard let externalIdentifier = link.externalIdentifier, !externalIdentifier.isEmpty else { return nil }
        return eventStore.calendarItems(withExternalIdentifier: externalIdentifier)
            .compactMap { $0 as? EKEvent }
            .first { $0.calendar.calendarIdentifier == link.calendarIdentifier }
    }

    private func merging(local: ImportantDateEvent, source: EKEvent) -> ImportantDateEvent {
        var updated = local
        updated.title = source.title
        updated.date = ImportantDateComponents(
            gregorianDate: source.startDate,
            includeYear: !isSimpleYearlyRecurrence(source)
        )
        updated.recurrence = isSimpleYearlyRecurrence(source) ? .yearly : .once
        if var link = updated.systemCalendarLink {
            link.eventIdentifier = source.eventIdentifier ?? link.eventIdentifier
            link.externalIdentifier = source.calendarItemExternalIdentifier?.isEmpty == false
                ? source.calendarItemExternalIdentifier
                : nil
            link.calendarIdentifier = source.calendar.calendarIdentifier
            link.calendarTitle = source.calendar.title
            link.isReadOnly = !source.calendar.allowsContentModifications || source.calendar.isImmutable
            link.lastSyncedAt = Date()
            updated.systemCalendarLink = link
        }
        updated.updatedAt = Date()
        return updated
    }

    private func write(_ local: ImportantDateEvent, to link: SystemCalendarLink) throws -> ImportantDateEvent {
        guard let calendar = eventStore.calendar(withIdentifier: link.calendarIdentifier) else {
            throw SystemCalendarServiceError.calendarNotFound
        }
        guard calendar.allowsContentModifications, !calendar.isImmutable else {
            throw SystemCalendarServiceError.calendarReadOnly
        }

        let existing = systemEvent(for: link)
        let event = existing ?? EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = local.title
        event.isAllDay = true
        event.notes = local.notes.isEmpty ? nil : local.notes

        let startDate: Date
        let isGregorianYearly = local.recurrence == .yearly && local.date.calendarSystem == .gregorian
        if local.date.calendarSystem == .chineseLunar {
            guard let next = local.relevantOccurrence() else {
                throw SystemCalendarServiceError.invalidLunarDate
            }
            startDate = next
            // EventKit 的 yearly recurrence 是公历规则；农历事件只维护下一次发生日。
            event.recurrenceRules = nil
        } else if isGregorianYearly && local.date.month == 2 && local.date.day == 29 {
            // 闰日事件无法用普通年度规则表达（非闰年需按策略回退）。
            // 导出为下一次发生日的一次性事件，由 TinyDesk 定期同步刷新。
            guard let occurrence = local.relevantOccurrence() else {
                throw SystemCalendarServiceError.invalidDate
            }
            startDate = occurrence
            event.recurrenceRules = nil
        } else {
            guard let occurrence = local.recurrence == .once
                ? local.storedOccurrence()
                : local.relevantOccurrence()
            else { throw SystemCalendarServiceError.invalidDate }
            startDate = occurrence
            event.recurrenceRules = local.recurrence == .yearly
                ? [EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)]
                : nil
        }
        event.startDate = startDate
        event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        let usesFutureEventsSpan = isGregorianYearly
            && !(local.date.month == 2 && local.date.day == 29)
        try eventStore.save(event, span: usesFutureEventsSpan ? .futureEvents : .thisEvent)

        var updated = local
        updated.systemCalendarLink = SystemCalendarLink(
            calendarIdentifier: calendar.calendarIdentifier,
            calendarTitle: calendar.title,
            eventIdentifier: event.eventIdentifier ?? link.eventIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier?.isEmpty == false
                ? event.calendarItemExternalIdentifier
                : nil,
            authority: .tinyDesk,
            isReadOnly: false,
            lastSyncedAt: Date()
        )
        updated.updatedAt = Date()
        return updated
    }

    private func inferredCategory(title: String, calendarTitle: String) -> ImportantDateCategory {
        let combined = "\(title) \(calendarTitle)"
        if combined.localizedCaseInsensitiveContains("生日") { return .birthday }
        if combined.localizedCaseInsensitiveContains("纪念") { return .anniversary }
        if combined.localizedCaseInsensitiveContains("节") || combined.localizedCaseInsensitiveContains("假期") {
            return .holiday
        }
        return .other
    }
}

private enum SystemCalendarServiceError: LocalizedError {
    case accessRequired
    case calendarNotFound
    case calendarReadOnly
    case invalidDate
    case invalidLunarDate

    var errorDescription: String? {
        switch self {
        case .accessRequired: return "请先允许 TinyDesk 访问系统日历。"
        case .calendarNotFound: return "找不到所选系统日历。"
        case .calendarReadOnly: return "所选系统日历是只读的。"
        case .invalidDate: return "此日期缺少有效的公历发生日。"
        case .invalidLunarDate: return "此农历日期无法计算下一次公历发生日。"
        }
    }
}
