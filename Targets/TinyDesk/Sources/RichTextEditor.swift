import AppKit
import SwiftUI

@MainActor
final class RichTextEditorController: ObservableObject {
    struct FormatState {
        var isBold = false
        var isItalic = false
        var isUnderlined = false
        var isStruckThrough = false
        var foregroundColor = NSColor.labelColor
    }

    @Published private(set) var format = FormatState()
    @Published private(set) var isReady = false

    private weak var textView: NSTextView?

    func connect(to textView: NSTextView) {
        guard self.textView !== textView else { return }
        self.textView = textView
        isReady = true
        refreshSelectionState()
    }

    func toggleBold() {
        applyFontTrait(.boldFontMask, adding: !format.isBold)
    }

    func toggleItalic() {
        guard let textView else { return }
        if format.isItalic {
            removeAttribute(.obliqueness, in: textView)
            removeFontTraitIfPresent(.italicFontMask, in: textView)
        } else {
            applyAttribute(.obliqueness, value: 0.18, in: textView)
        }
    }

    func toggleUnderline() {
        applyStyle(
            key: .underlineStyle,
            adding: !format.isUnderlined
        )
    }

    func toggleStrikethrough() {
        applyStyle(
            key: .strikethroughStyle,
            adding: !format.isStruckThrough
        )
    }

    func applyForegroundColor(_ color: NSColor) {
        guard let textView else { return }
        applyAttribute(.foregroundColor, value: color, in: textView)
    }

    func clearFormatting() {
        guard let textView else { return }
        let defaults = RichTextDefaults.attributes(fontSize: textView.font?.pointSize ?? 16)
        let removableKeys: [NSAttributedString.Key] = [
            .font,
            .foregroundColor,
            .backgroundColor,
            .underlineStyle,
            .strikethroughStyle,
            .strokeColor,
            .strokeWidth,
            .obliqueness,
            .shadow,
            .link,
        ]

        let range = textView.selectedRange()
        if range.length == 0 {
            var typing = textView.typingAttributes
            removableKeys.forEach { typing.removeValue(forKey: $0) }
            defaults.forEach { typing[$0.key] = $0.value }
            textView.typingAttributes = typing
            refreshSelectionState()
            return
        }

        guard textView.shouldChangeText(in: range, replacementString: nil),
              let storage = textView.textStorage
        else { return }

        storage.beginEditing()
        removableKeys.forEach { storage.removeAttribute($0, range: range) }
        defaults.forEach { storage.addAttribute($0.key, value: $0.value, range: range) }
        storage.endEditing()
        textView.didChangeText()
        refreshSelectionState()
    }

    func refreshSelectionState() {
        guard let textView else { return }
        let attributes = representativeAttributes(in: textView)
        let font = attributes[.font] as? NSFont ?? textView.font ?? NSFont.systemFont(ofSize: 16)
        let traits = font.fontDescriptor.symbolicTraits

        format = FormatState(
            isBold: traits.contains(.bold),
            isItalic: traits.contains(.italic) || styleIsEnabled(attributes[.obliqueness]),
            isUnderlined: styleIsEnabled(attributes[.underlineStyle]),
            isStruckThrough: styleIsEnabled(attributes[.strikethroughStyle]),
            foregroundColor: attributes[.foregroundColor] as? NSColor ?? textView.textColor ?? .labelColor
        )
    }

    private func applyFontTrait(_ trait: NSFontTraitMask, adding: Bool) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let manager = NSFontManager.shared

        if range.length == 0 {
            var typing = textView.typingAttributes
            let font = typing[.font] as? NSFont ?? textView.font ?? NSFont.systemFont(ofSize: 16)
            typing[.font] = adding
                ? manager.convert(font, toHaveTrait: trait)
                : manager.convert(font, toNotHaveTrait: trait)
            textView.typingAttributes = typing
            refreshSelectionState()
            return
        }

        guard textView.shouldChangeText(in: range, replacementString: nil),
              let storage = textView.textStorage
        else { return }

        var runs: [(NSRange, NSFont)] = []
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            runs.append((subrange, value as? NSFont ?? textView.font ?? NSFont.systemFont(ofSize: 16)))
        }

        storage.beginEditing()
        for (subrange, font) in runs {
            let converted = adding
                ? manager.convert(font, toHaveTrait: trait)
                : manager.convert(font, toNotHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: subrange)
        }
        storage.endEditing()
        textView.didChangeText()
        refreshSelectionState()
    }

    private func removeFontTraitIfPresent(_ trait: NSFontTraitMask, in textView: NSTextView) {
        let range = textView.selectedRange()
        let attributes = representativeAttributes(in: textView)
        guard let font = attributes[.font] as? NSFont,
              font.fontDescriptor.symbolicTraits.contains(.italic)
        else { return }

        if range.length == 0 {
            var typing = textView.typingAttributes
            typing[.font] = NSFontManager.shared.convert(font, toNotHaveTrait: trait)
            textView.typingAttributes = typing
            refreshSelectionState()
        } else {
            applyFontTrait(trait, adding: false)
        }
    }

    private func applyStyle(key: NSAttributedString.Key, adding: Bool) {
        guard let textView else { return }
        if adding {
            applyAttribute(key, value: NSUnderlineStyle.single.rawValue, in: textView)
        } else {
            removeAttribute(key, in: textView)
        }
    }

    private func applyAttribute(_ key: NSAttributedString.Key, value: Any, in textView: NSTextView) {
        let range = textView.selectedRange()
        if range.length == 0 {
            var typing = textView.typingAttributes
            typing[key] = value
            textView.typingAttributes = typing
            refreshSelectionState()
            return
        }

        guard textView.shouldChangeText(in: range, replacementString: nil),
              let storage = textView.textStorage
        else { return }

        storage.addAttribute(key, value: value, range: range)
        textView.didChangeText()
        refreshSelectionState()
    }

    private func removeAttribute(_ key: NSAttributedString.Key, in textView: NSTextView) {
        let range = textView.selectedRange()
        if range.length == 0 {
            var typing = textView.typingAttributes
            typing.removeValue(forKey: key)
            textView.typingAttributes = typing
            refreshSelectionState()
            return
        }

        guard textView.shouldChangeText(in: range, replacementString: nil),
              let storage = textView.textStorage
        else { return }

        storage.removeAttribute(key, range: range)
        textView.didChangeText()
        refreshSelectionState()
    }

    private func representativeAttributes(in textView: NSTextView) -> [NSAttributedString.Key: Any] {
        let range = textView.selectedRange()
        guard range.length > 0,
              let storage = textView.textStorage,
              storage.length > 0
        else {
            return textView.typingAttributes
        }

        return storage.attributes(at: min(range.location, storage.length - 1), effectiveRange: nil)
    }

    private func styleIsEnabled(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.intValue != 0 }
        if let integer = value as? Int { return integer != 0 }
        return false
    }
}

struct RichTextEditor: NSViewRepresentable {
    let richTextData: Data?
    let fallbackText: String
    let fontSize: CGFloat
    let controller: RichTextEditorController
    let onChange: (Data?, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.usesFindPanel = true
        textView.font = RichTextDefaults.font(size: fontSize)
        textView.textColor = .labelColor
        textView.typingAttributes = RichTextDefaults.attributes(fontSize: fontSize)

        scrollView.documentView = textView
        context.coordinator.load(richTextData: richTextData, fallbackText: fallbackText, into: textView)
        controller.connect(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        controller.connect(to: textView)

        if context.coordinator.shouldReload(richTextData: richTextData, fallbackText: fallbackText) {
            context.coordinator.load(richTextData: richTextData, fallbackText: fallbackText, into: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        private var didLoad = false
        private var isApplyingExternalContent = false
        private var lastRichTextData: Data?
        private var lastPlainText = ""

        init(parent: RichTextEditor) {
            self.parent = parent
        }

        func shouldReload(richTextData: Data?, fallbackText: String) -> Bool {
            !didLoad || richTextData != lastRichTextData || fallbackText != lastPlainText
        }

        func load(richTextData: Data?, fallbackText: String, into textView: NSTextView) {
            isApplyingExternalContent = true
            defer { isApplyingExternalContent = false }

            let attributed = RichTextDefaults.attributedString(
                from: richTextData,
                fallbackText: fallbackText,
                fontSize: parent.fontSize
            )
            textView.textStorage?.setAttributedString(attributed)
            textView.typingAttributes = RichTextDefaults.attributes(fontSize: parent.fontSize)
            lastRichTextData = richTextData
            lastPlainText = fallbackText
            didLoad = true
            parent.controller.refreshSelectionState()
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalContent,
                  let textView = notification.object as? NSTextView
            else { return }

            let data = textView.string.isEmpty ? nil : RichTextDefaults.rtfData(from: textView.attributedString())
            lastRichTextData = data
            lastPlainText = textView.string
            parent.onChange(data, textView.string)
            parent.controller.refreshSelectionState()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.controller.refreshSelectionState()
        }
    }
}

private enum RichTextDefaults {
    static func font(size: CGFloat) -> NSFont {
        let systemFont = NSFont.systemFont(ofSize: size)
        guard let descriptor = systemFont.fontDescriptor.withDesign(.rounded) else {
            return systemFont
        }
        return NSFont(descriptor: descriptor, size: size) ?? systemFont
    }

    static func attributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return [
            .font: font(size: fontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }

    static func attributedString(from data: Data?, fallbackText: String, fontSize: CGFloat) -> NSAttributedString {
        if let data,
           let attributed = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return attributed
        }

        return NSAttributedString(string: fallbackText, attributes: attributes(fontSize: fontSize))
    }

    static func rtfData(from attributedString: NSAttributedString) -> Data? {
        try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}
