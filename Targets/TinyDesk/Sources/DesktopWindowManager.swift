import AppKit
import Combine
import SwiftUI
import TinyDeskCore

enum DesktopCardSizePreset: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "小号 · 方形"
        case .medium: return "中号 · 横向"
        case .large: return "大号 · 方形"
        }
    }

    var dimensions: String {
        "\(Int(size.width)) × \(Int(size.height))"
    }

    /// 按卡片类型显示实际生效尺寸。
    func dimensions(for kind: DesktopCardKind) -> String {
        let target = effectiveSize(for: kind)
        return "\(Int(target.width)) × \(Int(target.height))"
    }

    var symbolName: String {
        switch self {
        case .small: return "square"
        case .medium: return "rectangle"
        case .large: return "square.resize"
        }
    }

    var size: NSSize {
        switch self {
        case .small: return NSSize(width: 280, height: 280)
        case .medium: return NSSize(width: 440, height: 220)
        case .large: return NSSize(width: 440, height: 440)
        }
    }

    /// 按卡片类型计算实际生效的预设尺寸（受该类型最小/最大尺寸约束）。
    func effectiveSize(for kind: DesktopCardKind) -> NSSize {
        let raw = size
        let (minimum, maximum) = DesktopWindowManager.sizeLimits(for: kind)
        return NSSize(
            width: min(max(raw.width, minimum.width), maximum.width),
            height: min(max(raw.height, minimum.height), maximum.height)
        )
    }

    func matches(_ size: NSSize, kind: DesktopCardKind? = nil) -> Bool {
        let target = kind.map(effectiveSize(for:)) ?? self.size
        return abs(size.width - target.width) < 2 && abs(size.height - target.height) < 2
    }
}

@MainActor
final class DesktopWindowManager: ObservableObject {
    private let store: DesktopWorkspaceStore
    private let settings: TinyDeskSettings
    private let calendarService: SystemCalendarService
    private var panels: [UUID: DesktopCardPanel] = [:]
    private var delegates: [UUID: DesktopPanelDelegate] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var didStart = false

    init(
        store: DesktopWorkspaceStore,
        settings: TinyDeskSettings,
        calendarService: SystemCalendarService
    ) {
        self.store = store
        self.settings = settings
        self.calendarService = calendarService
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        store.$workspace
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reconcileWindows()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.keepWindowsOnScreen()
            }
            .store(in: &cancellables)

        // 资料库文档 → 桌面摘要卡片。
        NotificationCenter.default.publisher(for: LibraryDeskCardRequest.notificationName)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let documentID = notification.userInfo?[LibraryDeskCardRequest.documentIDKey] as? UUID
                else { return }
                let title = notification.userInfo?[LibraryDeskCardRequest.titleKey] as? String ?? "资料"
                let summary = notification.userInfo?[LibraryDeskCardRequest.summaryKey] as? String ?? ""
                let tags = notification.userInfo?[LibraryDeskCardRequest.tagsKey] as? [String] ?? []
                self.createDeskRefCard(
                    documentID: documentID,
                    documentTitle: title,
                    documentSummary: summary,
                    documentTags: tags
                )
            }
            .store(in: &cancellables)

        // 资料库文档变更 → 桌面摘要卡片同步。
        NotificationCenter.default.publisher(for: LibraryDocumentSyncNotification.notificationName)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let documentID = notification.userInfo?[LibraryDocumentSyncNotification.documentIDKey] as? UUID
                else { return }
                self.synchronizeDeskRefCard(
                    documentID: documentID,
                    title: notification.userInfo?[LibraryDocumentSyncNotification.titleKey] as? String,
                    summary: notification.userInfo?[LibraryDocumentSyncNotification.summaryKey] as? String,
                    tags: notification.userInfo?[LibraryDocumentSyncNotification.tagsKey] as? [String],
                    status: (notification.userInfo?[LibraryDocumentSyncNotification.statusKey] as? String)
                        .flatMap(DesktopReferenceStatus.init(rawValue:))
                )
            }
            .store(in: &cancellables)

        GlobalShortcutManager.shared.onShortcut = { [weak self] in
            Task { @MainActor in self?.createQuickSticky() }
        }
        _ = GlobalShortcutManager.shared.register(settings.quickNoteShortcut)
        settings.$quickNoteShortcut
            .receive(on: DispatchQueue.main)
            .sink { shortcut in
                _ = GlobalShortcutManager.shared.register(shortcut)
            }
            .store(in: &cancellables)

        reconcileWindows()
    }

    func createCard(_ kind: DesktopCardKind) {
        guard !store.isReadOnly else { return }
        let card = store.addCard(kind: kind)
        reconcileWindows()
        focus(card.id)
    }

    func createQuickSticky() {
        guard !store.isReadOnly else { return }
        let screen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        let size = DesktopCardSizePreset.medium.size
        let frame = quickStickyFrame(size: size, screen: screen)
        let card = store.addCard(kind: .sticky)
        store.updateCard(card.id) {
            $0.title = "快速便签"
            $0.noteText = ""
            $0.noteRichTextData = nil
            $0.isAlwaysOnTop = settings.quickNotesStartPinned
            $0.frame = DesktopCardFrame(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.width,
                height: frame.height,
                screenIdentifier: screen?.tinyDeskIdentifier
            )
        }
        reconcileWindows()
        focus(card.id)
        focusTextEditor(in: panels[card.id])
    }

    /// 从资料库创建桌面摘要卡片。
    func createDeskRefCard(
        documentID: UUID,
        documentTitle: String,
        documentSummary: String,
        documentTags: [String]
    ) {
        guard !store.isReadOnly else { return }
        // 避免重复添加同一文档。
        if store.cards.contains(where: { $0.kind == .deskRef && $0.referenceDocumentID == documentID }) {
            if let existing = store.cards.first(where: { $0.kind == .deskRef && $0.referenceDocumentID == documentID }) {
                focus(existing.id)
            }
            return
        }

        let card = store.addCard(kind: .deskRef)
        store.updateCard(card.id) {
            $0.title = documentTitle
            $0.referenceDocumentID = documentID
            $0.referenceDocumentTitle = documentTitle
            $0.referenceDocumentSummary = documentSummary
            $0.referenceDocumentTags = documentTags
        }
        reconcileWindows()
        focus(card.id)
    }

    /// 同步资料库文档到桌面摘要卡片：标题、摘要、标签与生命周期状态。
    private func synchronizeDeskRefCard(
        documentID: UUID,
        title: String?,
        summary: String?,
        tags: [String]?,
        status: DesktopReferenceStatus?
    ) {
        for card in store.cards where card.kind == .deskRef && card.referenceDocumentID == documentID {
            let newTitle = title ?? card.referenceDocumentTitle
            let newSummary = summary ?? card.referenceDocumentSummary
            let newTags = tags ?? card.referenceDocumentTags
            let newStatus = status ?? card.referenceDocumentStatus
            // 值未变化时跳过写入，避免资料库每次保存都触发工作区落盘。
            guard newTitle != card.referenceDocumentTitle
                || newSummary != card.referenceDocumentSummary
                || newTags != card.referenceDocumentTags
                || newStatus != card.referenceDocumentStatus
            else { continue }
            store.updateCard(card.id) {
                if let newTitle {
                    $0.title = newTitle
                    $0.referenceDocumentTitle = newTitle
                }
                if let newSummary { $0.referenceDocumentSummary = newSummary }
                if let newTags { $0.referenceDocumentTags = newTags }
                $0.referenceDocumentStatus = newStatus
            }
        }
    }

    func show(_ id: UUID, focus: Bool = false) {
        guard !store.isReadOnly else { return }
        store.setVisible(true, for: id)
        reconcileWindows()
        if focus { self.focus(id) }
    }

    func hide(_ id: UUID) {
        guard !store.isReadOnly else { return }
        store.setVisible(false, for: id)
    }

    func focus(_ id: UUID) {
        guard store.card(withID: id) != nil else { return }
        if store.card(withID: id)?.isVisible == false {
            store.setVisible(true, for: id)
        }
        reconcileWindows()
        guard let panel = panels[id] else { return }
        applyWindowLevel(panel, for: id)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func resetPosition(_ id: UUID) {
        guard !store.isReadOnly else { return }
        guard let card = store.card(withID: id), let panel = panels[id] else { return }
        let frame = defaultFrame(for: card, index: store.cards.firstIndex(where: { $0.id == id }) ?? 0)
        panel.setFrame(frame, display: true, animate: true)
        saveFrame(of: panel, cardID: id)
    }

    func applySizePreset(_ preset: DesktopCardSizePreset, to id: UUID) {
        guard !store.isReadOnly else { return }
        guard let card = store.card(withID: id) else { return }
        let panel = panels[id] ?? makePanel(
            for: card,
            index: store.cards.firstIndex(where: { $0.id == id }) ?? 0
        )

        // 预设尺寸必须先经过该卡片类型的最小/最大尺寸约束，
        // 否则 AppKit 会按 contentMinSize 静默顶高，导致实际尺寸与预设不一致。
        let targetSize = preset.effectiveSize(for: card.kind)
        let current = panel.frame
        var target = NSRect(
            x: current.midX - targetSize.width / 2,
            y: current.midY - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        target = clampedFrame(target, preferredScreenID: panel.screen?.tinyDeskIdentifier)
        panel.setFrame(target, display: true, animate: true)
        saveFrame(of: panel, cardID: id)
    }

    func selectedSizePreset(for id: UUID) -> DesktopCardSizePreset? {
        guard let panel = panels[id], let card = store.card(withID: id) else { return nil }
        return DesktopCardSizePreset.allCases.first { $0.matches(panel.frame.size, kind: card.kind) }
    }

    func closePanels() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
        _ = store.persistNow()
    }

    /// 打开资料库窗口并选中指定文档（由 App 层监听处理）。
    func openLibraryDocument(_ documentID: UUID) {
        NotificationCenter.default.post(
            name: LibraryDocumentOpenRequest.notificationName,
            object: nil,
            userInfo: [LibraryDocumentOpenRequest.documentIDKey: documentID]
        )
    }

    /// 打开重要日期编辑器/系统日历同步界面期间，临时把卡片提升到浮动层，
    /// 否则 sheet 会继承桌面层级、被普通应用窗口遮挡；关闭后恢复桌面层。
    func temporarilyRaiseCard(_ id: UUID) {
        guard let panel = panels[id] else { return }
        panel.isFloatingPanel = true
        panel.level = .floating
    }

    func restoreCardLevel(_ id: UUID) {
        guard let panel = panels[id], let card = store.card(withID: id) else { return }
        applyWindowLevel(panel, for: card.id)
    }

    fileprivate func panelDidBecomeKey(_ panel: NSWindow, cardID: UUID) {
        applyWindowLevel(panel, for: cardID)
    }

    fileprivate func panelDidResignKey(_ panel: NSWindow, cardID: UUID) {
        DispatchQueue.main.async { [weak panel] in
            guard let panel, !panel.isKeyWindow else { return }
            self.applyWindowLevel(panel, for: cardID)
        }
    }

    fileprivate func saveFrame(of window: NSWindow, cardID: UUID) {
        let frame = window.frame
        store.updateFrame(
            DesktopCardFrame(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width,
                height: frame.size.height,
                screenIdentifier: window.screen?.tinyDeskIdentifier
            ),
            for: cardID
        )
    }

    private func reconcileWindows() {
        let cardsByID = Dictionary(uniqueKeysWithValues: store.cards.map { ($0.id, $0) })

        for id in Array(panels.keys) where cardsByID[id] == nil {
            panels[id]?.orderOut(nil)
            panels[id]?.close()
            panels.removeValue(forKey: id)
            delegates.removeValue(forKey: id)
        }

        for (index, card) in store.cards.enumerated() {
            let panel = panels[card.id] ?? makePanel(for: card, index: index)
            applyPositionLock(card.resolvedIsPositionLocked || store.isReadOnly, to: panel)
            applyWindowLevel(panel, for: card.id)
            if store.isReadOnly {
                panel.styleMask.remove(.resizable)
            } else if !panel.styleMask.contains(.resizable) {
                panel.styleMask.insert(.resizable)
            }
            if card.isVisible {
                if !panel.isVisible {
                    panel.orderFront(nil)
                }
            } else if panel.isVisible {
                panel.orderOut(nil)
            }
        }
    }

    private func makePanel(for card: DesktopCard, index: Int) -> DesktopCardPanel {
        let panel = DesktopCardPanel(
            contentRect: resolvedFrame(for: card, index: index),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier(card.id.uuidString)
        panel.title = card.title
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        applyPositionLock(card.resolvedIsPositionLocked, to: panel)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = card.resolvedIsAlwaysOnTop
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.level = desiredWindowLevel(for: card)
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = DesktopCardWindowPolicy.collectionBehavior
        panel.tabbingMode = .disallowed
        panel.isExcludedFromWindowsMenu = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let limits = Self.sizeLimits(for: card.kind)
        panel.contentMinSize = limits.minimum
        panel.contentMaxSize = limits.maximum

        let delegate = DesktopPanelDelegate(cardID: card.id, manager: self)
        panel.delegate = delegate
        delegates[card.id] = delegate

        let rootView = DesktopCardHostView(cardID: card.id)
            .environmentObject(store)
            .environmentObject(self)
            .environmentObject(settings)
            .environmentObject(calendarService)
            .ignoresSafeArea()
        panel.contentView = DesktopCardHostingView(rootView: rootView)

        panels[card.id] = panel
        if card.frame == nil {
            saveFrame(of: panel, cardID: card.id)
        }
        return panel
    }

    private func applyPositionLock(_ isLocked: Bool, to panel: NSPanel) {
        panel.isMovable = !isLocked
        panel.isMovableByWindowBackground = !isLocked
    }

    private func applyWindowLevel(_ panel: NSWindow, for cardID: UUID) {
        guard let card = store.card(withID: cardID) else {
            panel.level = DesktopCardWindowPolicy.desktopLevel
            return
        }
        if let panel = panel as? NSPanel {
            DesktopCardWindowPolicy.applyWindowLevel(
                to: panel,
                isAlwaysOnTop: card.resolvedIsAlwaysOnTop
            )
        } else {
            panel.level = desiredWindowLevel(for: card)
        }
    }

    private func desiredWindowLevel(for card: DesktopCard) -> NSWindow.Level {
        DesktopCardWindowPolicy.windowLevel(isAlwaysOnTop: card.resolvedIsAlwaysOnTop)
    }

    private func screenContainingMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func quickStickyFrame(size: NSSize, screen: NSScreen?) -> NSRect {
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 14,
            width: size.width,
            height: size.height
        )
    }

    private func focusTextEditor(in panel: NSPanel?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard let panel, let editor = panel.contentView?.firstTextView else { return }
            panel.makeFirstResponder(editor)
        }
    }

    private func keepWindowsOnScreen() {
        for card in store.cards {
            guard let panel = panels[card.id] else { continue }
            let adjusted = clampedFrame(panel.frame, preferredScreenID: panel.screen?.tinyDeskIdentifier)
            if adjusted != panel.frame {
                panel.setFrame(adjusted, display: true)
                saveFrame(of: panel, cardID: card.id)
            }
        }
    }

    private func resolvedFrame(for card: DesktopCard, index: Int) -> NSRect {
        guard let saved = card.frame else { return defaultFrame(for: card, index: index) }
        return clampedFrame(
            NSRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height),
            preferredScreenID: saved.screenIdentifier
        )
    }

    private func clampedFrame(_ frame: NSRect, preferredScreenID: String?) -> NSRect {
        let screen = NSScreen.screens.first { $0.tinyDeskIdentifier == preferredScreenID }
            ?? NSScreen.screens.first { $0.visibleFrame.intersects(frame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let visible = screen?.visibleFrame else { return frame }
        var adjusted = frame
        adjusted.size.width = min(max(frame.width, 220), min(800, visible.width))
        adjusted.size.height = min(max(frame.height, 170), min(700, visible.height))
        adjusted.origin.x = min(max(adjusted.minX, visible.minX), visible.maxX - adjusted.width)
        adjusted.origin.y = min(max(adjusted.minY, visible.minY), visible.maxY - adjusted.height)
        return adjusted
    }

    private func defaultFrame(for card: DesktopCard, index: Int) -> NSRect {
        // 优先使用当前操作屏幕（鼠标所在屏幕），多显示器下新建卡片不会落到主屏。
        let screen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size: NSSize
        switch card.kind {
        case .sticky:
            size = DesktopCardSizePreset.small.size
        case .countdown:
            size = DesktopCardSizePreset.medium.size
        case .todo:
            size = DesktopCardSizePreset.large.size
        case .deskRef:
            size = DesktopCardSizePreset.small.size
        }

        let horizontalInset: CGFloat = 30
        let cellWidth: CGFloat = 460
        let cellHeight: CGFloat = 470
        let usableWidth = max(cellWidth, visible.width - horizontalInset * 2)
        let columns = max(1, Int(usableWidth / cellWidth))
        let column = index % columns
        let row = index / columns
        let x = min(
            visible.minX + horizontalInset + CGFloat(column) * cellWidth,
            visible.maxX - size.width - horizontalInset
        )
        let y = max(
            visible.minY + 30,
            visible.maxY - size.height - 14 - CGFloat(row) * cellHeight
        )
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    fileprivate nonisolated static func sizeLimits(for kind: DesktopCardKind) -> (minimum: NSSize, maximum: NSSize) {
        switch kind {
        case .sticky:
            return (NSSize(width: 220, height: 170), NSSize(width: 760, height: 680))
        case .countdown:
            return (NSSize(width: 220, height: 180), NSSize(width: 720, height: 560))
        case .todo:
            return (NSSize(width: 260, height: 240), NSSize(width: 800, height: 700))
        case .deskRef:
            return (NSSize(width: 220, height: 170), NSSize(width: 480, height: 360))
        }
    }

}

private final class DesktopCardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class DesktopCardHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class DesktopPanelDelegate: NSObject, NSWindowDelegate {
    let cardID: UUID
    weak var manager: DesktopWindowManager?

    init(cardID: UUID, manager: DesktopWindowManager) {
        self.cardID = cardID
        self.manager = manager
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow else { return }
        manager?.panelDidBecomeKey(panel, cardID: cardID)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow else { return }
        manager?.panelDidResignKey(panel, cardID: cardID)
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow else { return }
        manager?.saveFrame(of: panel, cardID: cardID)
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow else { return }
        manager?.saveFrame(of: panel, cardID: cardID)
    }
}

private extension NSScreen {
    var tinyDeskIdentifier: String? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }
}

private extension NSView {
    var firstTextView: NSTextView? {
        if let textView = self as? NSTextView { return textView }
        for subview in subviews {
            if let textView = subview.firstTextView { return textView }
        }
        return nil
    }
}
