import AppKit
import Carbon.HIToolbox
import SwiftUI

struct GlobalShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyDisplay: String

    static let defaultQuickNote = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_N),
        modifiers: UInt32(cmdKey | optionKey),
        keyDisplay: "N"
    )

    var displayString: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + keyDisplay
    }
}

final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    var onShortcut: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var activeShortcut: GlobalShortcut?

    private init() {
        var type = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandlerCallback,
            1,
            &type,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    @discardableResult
    func register(_ shortcut: GlobalShortcut) -> Bool {
        if activeShortcut == shortcut, hotKey != nil {
            return true
        }

        let identifier = EventHotKeyID(signature: OSType(0x54444B51), id: 1)
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &replacement
        )
        guard status == noErr, let replacement else { return false }

        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        activeShortcut = shortcut
        return true
    }

    private static let eventHandlerCallback: EventHandlerUPP = { _, _, userData in
        guard let userData else { return noErr }
        let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
        manager.onShortcut?()
        return noErr
    }
}

struct GlobalShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onChange = { shortcut in self.shortcut = shortcut }
        view.shortcut = shortcut
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.onChange = { shortcut in self.shortcut = shortcut }
        nsView.shortcut = shortcut
    }
}

final class ShortcutRecorderView: NSView {
    var onChange: ((GlobalShortcut) -> Void)?
    var shortcut: GlobalShortcut = .defaultQuickNote {
        didSet { label.stringValue = shortcut.displayString }
    }

    private let label = NSTextField(labelWithString: "")

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        label.stringValue = shortcut.displayString
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    override func resignFirstResponder() -> Bool {
        layer?.borderColor = NSColor.separatorColor.cgColor
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        let allowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).intersection(allowed)
        guard !flags.isEmpty else {
            NSSound.beep()
            return
        }

        let display = event.charactersIgnoringModifiers?.uppercased() ?? "键"
        let next = GlobalShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers(from: flags),
            keyDisplay: display
        )
        shortcut = next
        onChange?(next)
        window?.makeFirstResponder(nil)
    }
}

private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var modifiers: UInt32 = 0
    if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
    if flags.contains(.option) { modifiers |= UInt32(optionKey) }
    if flags.contains(.control) { modifiers |= UInt32(controlKey) }
    if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
    return modifiers
}
