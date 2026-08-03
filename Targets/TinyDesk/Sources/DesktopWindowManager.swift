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

    func matches(_ size: NSSize) -> Bool {
        abs(size.width - self.size.width) < 2 && abs(size.height - self.size.height) < 2
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
        let card = store.addCard(kind: kind)
        reconcileWindows()
        focus(card.id)
    }

    func createQuickSticky() {
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

    func show(_ id: UUID, focus: Bool = false) {
        store.setVisible(true, for: id)
        reconcileWindows()
        if focus { self.focus(id) }
    }

    func hide(_ id: UUID) {
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
        guard let card = store.card(withID: id), let panel = panels[id] else { return }
        let frame = defaultFrame(for: card, index: store.cards.firstIndex(where: { $0.id == id }) ?? 0)
        panel.setFrame(frame, display: true, animate: true)
        saveFrame(of: panel, cardID: id)
    }

    func applySizePreset(_ preset: DesktopCardSizePreset, to id: UUID) {
        guard let card = store.card(withID: id) else { return }
        let panel = panels[id] ?? makePanel(
            for: card,
            index: store.cards.firstIndex(where: { $0.id == id }) ?? 0
        )

        let current = panel.frame
        var target = NSRect(
            x: current.midX - preset.size.width / 2,
            y: current.midY - preset.size.height / 2,
            width: preset.size.width,
            height: preset.size.height
        )
        target = clampedFrame(target, preferredScreenID: panel.screen?.tinyDeskIdentifier)
        panel.setFrame(target, display: true, animate: true)
        saveFrame(of: panel, cardID: id)
    }

    func selectedSizePreset(for id: UUID) -> DesktopCardSizePreset? {
        guard let panel = panels[id] else { return nil }
        return DesktopCardSizePreset.allCases.first { $0.matches(panel.frame.size) }
    }

    func closePanels() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
        _ = store.persistNow()
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
            applyPositionLock(card.resolvedIsPositionLocked, to: panel)
            applyWindowLevel(panel, for: card.id)
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.tabbingMode = .disallowed
        panel.isExcludedFromWindowsMenu = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let limits = sizeLimits(for: card.kind)
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
            panel.level = Self.desktopLevel
            return
        }
        panel.level = desiredWindowLevel(for: card)
        if let panel = panel as? NSPanel {
            panel.isFloatingPanel = card.resolvedIsAlwaysOnTop
        }
    }

    private func desiredWindowLevel(for card: DesktopCard) -> NSWindow.Level {
        card.resolvedIsAlwaysOnTop ? .floating : Self.desktopLevel
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
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size: NSSize
        switch card.kind {
        case .sticky:
            size = DesktopCardSizePreset.small.size
        case .countdown:
            size = DesktopCardSizePreset.medium.size
        case .todo:
            size = DesktopCardSizePreset.large.size
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

    private func sizeLimits(for kind: DesktopCardKind) -> (minimum: NSSize, maximum: NSSize) {
        switch kind {
        case .sticky:
            return (NSSize(width: 220, height: 170), NSSize(width: 760, height: 680))
        case .countdown:
            return (NSSize(width: 220, height: 180), NSSize(width: 720, height: 560))
        case .todo:
            return (NSSize(width: 260, height: 240), NSSize(width: 800, height: 700))
        }
    }

    private static let desktopLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    )
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
