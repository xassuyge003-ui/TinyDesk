import Foundation
import TinyDeskCore
import UserNotifications

final class TinyDeskNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TinyDeskNotificationDelegate()

    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

actor ImportantDateNotificationScheduler {
    static let shared = ImportantDateNotificationScheduler()

    /// 一次同步的结果，供 UI 展示失败数量与原因。
    struct SyncResult {
        var scheduled = 0
        var failed = 0
        var unauthorized = false
        var failureDetails: [String] = []
    }

    private let identifierPrefix = "tinydesk.important-date."

    func synchronize(events: [ImportantDateEvent], referenceDate: Date = Date()) async -> SyncResult {
        var result = SyncResult()
        guard !Task.isCancelled else { return result }
        let center = UNUserNotificationCenter.current()

        let enabledEvents = events.filter { $0.reminderDaysBefore != nil }
        // 没有任何启用提醒的事件时不请求权限，避免首次启动弹出无关授权。
        guard !enabledEvents.isEmpty else { return result }

        var settings = await notificationSettings(from: center)
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await notificationSettings(from: center)
        }
        // 未授权时保留已有请求（可能是用户刚在系统设置中拒绝），
        // 不删除旧通知，避免“清空后没有新请求”的空状态。
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            result.unauthorized = true
            return result
        }

        let calendar = Calendar.current
        var newIdentifiers = Set<String>()

        for event in enabledEvents {
            guard !Task.isCancelled else { break }
            for scheduled in requests(for: event, referenceDate: referenceDate, calendar: calendar) {
                newIdentifiers.insert(scheduled.identifier)
                let content = UNMutableNotificationContent()
                content.title = event.title
                content.body = notificationBody(for: event)
                content.sound = .default
                content.userInfo = ["importantDateID": event.id.uuidString]

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: scheduled.components,
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: scheduled.identifier,
                    content: content,
                    trigger: trigger
                )
                do {
                    try await center.add(request)
                    result.scheduled += 1
                } catch {
                    result.failed += 1
                    result.failureDetails.append("\(event.title)（\(scheduled.identifier)）：\(error.localizedDescription)")
                }
            }
        }

        // 相同 identifier 的 add 会替换旧请求；这里只删除本次不再需要的旧请求。
        let existing = await pendingRequests(from: center)
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        let obsolete = existing.filter { !newIdentifiers.contains($0) }
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
        }
        return result
    }

    private func requests(
        for event: ImportantDateEvent,
        referenceDate: Date,
        calendar: Calendar
    ) -> [(identifier: String, components: DateComponents)] {
        guard let daysBefore = event.reminderDaysBefore else { return [] }
        let currentYear = calendar.component(.year, from: referenceDate)
        let occurrences: [Date]

        switch event.recurrence {
        case .once:
            occurrences = event.storedOccurrence(calendar: calendar).map { [$0] } ?? []
        case .yearly:
            occurrences = (currentYear...(currentYear + 2)).compactMap {
                event.occurrence(inYear: $0, calendar: calendar)
            }
        }

        return occurrences.compactMap { occurrence in
            guard let reminderDay = calendar.date(byAdding: .day, value: -daysBefore, to: occurrence) else {
                return nil
            }
            var components = calendar.dateComponents([.year, .month, .day], from: reminderDay)
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.hour = event.reminderHour
            components.minute = 0
            guard let fireDate = calendar.date(from: components), fireDate > referenceDate else { return nil }
            let occurrenceYear = calendar.component(.year, from: occurrence)
            return (
                identifier: "\(identifierPrefix)\(event.id.uuidString).\(occurrenceYear)",
                components: components
            )
        }
    }

    private func notificationBody(for event: ImportantDateEvent) -> String {
        switch event.reminderDaysBefore ?? 0 {
        case 0:
            return "今天是\(event.title)"
        case 1:
            return "\(event.title)将在明天到来"
        case let days:
            return "\(event.title)还有 \(days) 天"
        }
    }

    private func pendingRequests(from center: UNUserNotificationCenter) async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { continuation.resume(returning: $0) }
        }
    }

    private func notificationSettings(from center: UNUserNotificationCenter) async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { continuation.resume(returning: $0) }
        }
    }
}
