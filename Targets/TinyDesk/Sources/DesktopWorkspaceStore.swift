import AppKit
import Combine
import Foundation
import TinyDeskCore

@MainActor
final class DesktopWorkspaceStore: ObservableObject {
    @Published private(set) var workspace: TinyDeskWorkspace
    @Published private(set) var storageMessage: String?
    /// 工作区由更高版本创建时进入只读模式：保留原文件与内存数据，禁止写回。
    private(set) var isReadOnly = false

    let fileURL: URL

    private var pendingSave: DispatchWorkItem?
    private var notificationTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        let resolvedURL = fileURL ?? Self.defaultWorkspaceURL()
        self.fileURL = resolvedURL

        if FileManager.default.fileExists(atPath: resolvedURL.path) {
            do {
                let data = try Data(contentsOf: resolvedURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(TinyDeskWorkspace.self, from: data)
                guard decoded.schemaVersion <= TinyDeskWorkspace.currentSchemaVersion else {
                    // 高版本文件可能完全有效，不能当作损坏文件备份或重建。
                    // 保留原文件并进入只读展示模式，提示升级应用。
                    isReadOnly = true
                    workspace = decoded
                    storageMessage = "工作区由更高版本（schema \(decoded.schemaVersion)）创建。为保护数据，当前版本只读显示，请升级 TinyDesk 后再编辑。"
                    refreshImportantDateNotifications()
                    return
                }
                let migrated = decoded.migratedToCurrentSchema()
                workspace = migrated
                if migrated != decoded {
                    do {
                        try Self.write(migrated, to: resolvedURL)
                    } catch {
                        storageMessage = "旧版重要日期已迁移，但保存失败：\(error.localizedDescription)"
                    }
                }
            } catch {
                workspace = .seeded()
                storageMessage = Self.backupCorruptedFile(at: resolvedURL, error: error)
            }
        } else {
            workspace = .seeded()
            do {
                try Self.write(workspace, to: resolvedURL)
            } catch {
                storageMessage = "首次保存失败：\(error.localizedDescription)"
            }
        }

        refreshImportantDateNotifications()

        // 所有退出路径（菜单、AppleScript、系统终止等）最终落盘。
        // 注册在 store 自身，避免依赖 App.init 中被 SwiftUI 丢弃的实例；
        // queue 必须为 nil（block 指定 queue 是异步派发，终止时不会执行）。
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            _ = self?.persistNow()
        }
    }

    var cards: [DesktopCard] { workspace.cards }
    var importantDates: [ImportantDateEvent] { workspace.importantDates }

    func card(withID id: UUID) -> DesktopCard? {
        workspace.cards.first { $0.id == id }
    }

    @discardableResult
    func addCard(kind: DesktopCardKind) -> DesktopCard {
        let card: DesktopCard
        switch kind {
        case .sticky:
            card = .sticky()
        case .countdown:
            card = .countdown()
        case .todo:
            card = .todo()
        case .deskRef:
            card = DesktopCard(
                kind: .deskRef,
                title: "资料",
                referenceDocumentTitle: "资料",
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        var next = workspace
        next.cards.append(card)
        workspace = next
        scheduleSave()
        return card
    }

    func updateCard(_ id: UUID, _ mutation: (inout DesktopCard) -> Void) {
        guard let index = workspace.cards.firstIndex(where: { $0.id == id }) else { return }
        var next = workspace
        mutation(&next.cards[index])
        next.cards[index].markUpdated()
        workspace = next
        scheduleSave()
    }

    @discardableResult
    func addImportantDate(_ event: ImportantDateEvent) -> ImportantDateEvent {
        var next = workspace
        next.importantDates.append(event)
        workspace = next
        scheduleSave()
        refreshImportantDateNotifications()
        return event
    }

    func updateImportantDate(_ id: UUID, _ mutation: (inout ImportantDateEvent) -> Void) {
        guard let index = workspace.importantDates.firstIndex(where: { $0.id == id }) else { return }
        var next = workspace
        mutation(&next.importantDates[index])
        next.importantDates[index].updatedAt = Date()
        workspace = next
        scheduleSave()
        refreshImportantDateNotifications()
    }

    func deleteImportantDate(_ id: UUID) {
        var next = workspace
        next.importantDates.removeAll { $0.id == id }
        guard next.importantDates.count != workspace.importantDates.count else { return }
        for index in next.cards.indices where next.cards[index].featuredImportantDateID == id {
            next.cards[index].featuredImportantDateID = nil
            next.cards[index].markUpdated()
        }
        workspace = next
        scheduleSave()
        refreshImportantDateNotifications()
    }

    func hasImportedSystemCalendarCandidate(_ candidate: SystemCalendarCandidate) -> Bool {
        workspace.importantDates.contains { event in
            guard let link = event.systemCalendarLink,
                  link.calendarIdentifier == candidate.calendarIdentifier
            else { return false }
            if let externalIdentifier = candidate.externalIdentifier,
               !externalIdentifier.isEmpty {
                return link.externalIdentifier == externalIdentifier
            }
            return link.eventIdentifier == candidate.eventIdentifier
        }
    }

    @discardableResult
    func importSystemCalendarCandidates(
        _ candidates: [SystemCalendarCandidate],
        using service: SystemCalendarService
    ) -> Int {
        let newEvents = candidates
            .filter { !hasImportedSystemCalendarCandidate($0) }
            .map(service.makeImportantDate(from:))
        guard !newEvents.isEmpty else { return 0 }

        var next = workspace
        next.importantDates.append(contentsOf: newEvents)
        workspace = next
        scheduleSave()
        refreshImportantDateNotifications()
        return newEvents.count
    }

    /// 导出到系统日历；成功返回 true，失败返回 false 并设置存储提示。
    @discardableResult
    func exportImportantDate(
        _ id: UUID,
        to calendarIdentifier: String,
        using service: SystemCalendarService
    ) -> Bool {
        guard let event = workspace.importantDates.first(where: { $0.id == id }) else { return false }
        do {
            let updated = try service.export(event, to: calendarIdentifier)
            updateImportantDate(id) { $0 = updated }
            return true
        } catch {
            storageMessage = "无法关联系统日历：\(error.localizedDescription)"
            return false
        }
    }

    func removeSystemCalendarLink(_ id: UUID, using service: SystemCalendarService) {
        updateImportantDate(id) { $0 = service.removeLink(from: $0) }
    }

    func synchronizeSystemCalendar(using service: SystemCalendarService) async {
        guard service.hasFullAccess else { return }
        var next = workspace
        var changed = false

        for index in next.importantDates.indices where next.importantDates[index].systemCalendarLink != nil {
            let original = next.importantDates[index]
            guard let refreshed = service.refreshLinkedEvent(original) else { continue }
            if refreshed != original {
                next.importantDates[index] = refreshed
                changed = true
            }
        }

        guard changed else { return }
        workspace = next
        scheduleSave()
        refreshImportantDateNotifications()
    }

    func updateFrame(_ frame: DesktopCardFrame, for id: UUID) {
        guard let index = workspace.cards.firstIndex(where: { $0.id == id }),
              workspace.cards[index].frame != frame
        else { return }

        var next = workspace
        next.cards[index].frame = frame
        next.cards[index].markUpdated()
        workspace = next
        scheduleSave(after: 0.45)
    }

    func setVisible(_ isVisible: Bool, for id: UUID) {
        updateCard(id) { $0.isVisible = isVisible }
    }

    func showAll() {
        var next = workspace
        var changed = false
        for index in next.cards.indices where !next.cards[index].isVisible {
            next.cards[index].isVisible = true
            next.cards[index].markUpdated()
            changed = true
        }
        guard changed else { return }
        workspace = next
        scheduleSave()
    }

    func hideAll() {
        var next = workspace
        var changed = false
        for index in next.cards.indices where next.cards[index].isVisible {
            next.cards[index].isVisible = false
            next.cards[index].markUpdated()
            changed = true
        }
        guard changed else { return }
        workspace = next
        scheduleSave()
    }

    func deleteCard(_ id: UUID) {
        var next = workspace
        next.cards.removeAll { $0.id == id }
        guard next.cards.count != workspace.cards.count else { return }
        workspace = next
        scheduleSave()
    }

    func dismissStorageMessage() {
        storageMessage = nil
    }

    @discardableResult
    func persistNow() -> Bool {
        guard !isReadOnly else { return true }
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try Self.write(workspace, to: fileURL)
            return true
        } catch {
            storageMessage = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    private func scheduleSave(after delay: TimeInterval = 0.25) {
        guard !isReadOnly else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                _ = self?.persistNow()
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 重新调度所有重要日期提醒（权限恢复、应用激活时调用）。
    func refreshImportantDateNotifications() {
        let events = workspace.importantDates
        notificationTask?.cancel()
        notificationTask = Task {
            guard !Task.isCancelled else { return }
            let result = await ImportantDateNotificationScheduler.shared.synchronize(events: events)
            guard !Task.isCancelled, result.failed > 0 else { return }
            let firstDetail = result.failureDetails.first ?? "系统拒绝了部分请求"
            storageMessage = "有 \(result.failed) 条提醒未能安排：\(firstDetail)"
        }
    }

    private static func defaultWorkspaceURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(TinyDeskConst.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(TinyDeskConst.workspaceFileName, isDirectory: false)
    }

    private static func write(_ workspace: TinyDeskWorkspace, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(workspace)
        try data.write(to: url, options: .atomic)
    }

    private static func backupCorruptedFile(at url: URL, error loadError: Error) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = UUID().uuidString.prefix(8)
        let backup = url
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(formatter.string(from: Date()))-\(suffix).json")

        do {
            try FileManager.default.moveItem(at: url, to: backup)
            return "工作区无法读取，已备份为 \(backup.lastPathComponent)，并创建了新的本地工作区。"
        } catch {
            return "工作区无法读取（\(loadError.localizedDescription)），备份也失败：\(error.localizedDescription)"
        }
    }
}
