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

    private let identifierPrefix = "tinydesk.important-date."

    func synchronize(events: [ImportantDateEvent], referenceDate: Date = Date()) async {
        guard !Task.isCancelled else { return }
        let center = UNUserNotificationCenter.current()
        let existing = await pendingRequests(from: center)
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        let enabledEvents = events.filter { $0.reminderDaysBefore != nil }
        guard !enabledEvents.isEmpty else { return }

        var settings = await notificationSettings(from: center)
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await notificationSettings(from: center)
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let calendar = Calendar.current
        for event in enabledEvents {
            for scheduled in requests(for: event, referenceDate: referenceDate, calendar: calendar) {
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
                try? await center.add(request)
            }
        }
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
