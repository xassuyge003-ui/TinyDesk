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
        guard let textView else { return }
        applyFontTrait(
            .boldFontMask,
            adding: !selectionHasFontTrait(.boldFontMask, in: textView)
        )
    }

    func toggleItalic() {
        guard let textView else { return }
        applyItalic(adding: !selectionHasItalic(in: textView))
    }

    func toggleUnderline() {
        guard let textView else { return }
        applyStyle(
            key: .underlineStyle,
            adding: !selectionHasEnabledAttribute(.underlineStyle, in: textView)
        )
    }

    func toggleStrikethrough() {
        guard let textView else { return }
        applyStyle(
            key: .strikethroughStyle,
            adding: !selectionHasEnabledAttribute(.strikethroughStyle, in: textView)
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
            RichTextDefaults.syntheticItalicAttribute,
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
        let traits = NSFontManager.shared.traits(of: font)

        format = FormatState(
            isBold: traits.contains(.boldFontMask),
            isItalic: traits.contains(.italicFontMask)
                || styleIsEnabled(attributes[RichTextDefaults.syntheticItalicAttribute])
                || RichTextDefaults.isSyntheticItalic(font)
                || styleIsEnabled(attributes[.obliqueness]),
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
            typing[.font] = convertedFont(font, trait: trait, adding: adding, manager: manager)
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
            let converted = convertedFont(font, trait: trait, adding: adding, manager: manager)
            storage.addAttribute(.font, value: converted, range: subrange)
        }
        storage.endEditing()
        textView.didChangeText()
        refreshSelectionState()
    }

    private func convertedFont(
        _ font: NSFont,
        trait: NSFontTraitMask,
        adding: Bool,
        manager: NSFontManager
    ) -> NSFont {
        let preservesSyntheticItalic = RichTextDefaults.isSyntheticItalic(font)
        let sourceFont = preservesSyntheticItalic ? RichTextDefaults.baseFont(from: font) : font
        let converted: NSFont

        if adding {
            converted = manager.convert(sourceFont, toHaveTrait: trait)
        } else {
            let withoutTrait = manager.convert(sourceFont, toNotHaveTrait: trait)
            if !manager.traits(of: withoutTrait).contains(trait) {
                converted = withoutTrait
            } else if trait == .boldFontMask,
                      sourceFont.familyName == ".AppleSystemUIFontRounded" {
                let regular = NSFont.systemFont(ofSize: sourceFont.pointSize, weight: .regular)
                if let descriptor = regular.fontDescriptor.withDesign(.rounded) {
                    converted = NSFont(descriptor: descriptor, size: sourceFont.pointSize) ?? regular
                } else {
                    converted = regular
                }
            } else {
                let lighter = manager.convertWeight(false, of: sourceFont)
                converted = manager.traits(of: lighter).contains(trait) ? withoutTrait : lighter
            }
        }

        return preservesSyntheticItalic
            ? RichTextDefaults.syntheticItalicFont(from: converted)
            : converted
    }

    private func applyItalic(adding: Bool) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let manager = NSFontManager.shared

        if range.length == 0 {
            var typing = textView.typingAttributes
            let font = typing[.font] as? NSFont ?? textView.font ?? NSFont.systemFont(ofSize: 16)
            typing[.font] = convertedItalicFont(font, adding: adding, manager: manager)
            typing.removeValue(forKey: .obliqueness)
            if adding {
                typing[RichTextDefaults.syntheticItalicAttribute] = true
            } else {
                typing.removeValue(forKey: RichTextDefaults.syntheticItalicAttribute)
            }
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
        storage.removeAttribute(.obliqueness, range: range)
        if adding {
            storage.addAttribute(RichTextDefaults.syntheticItalicAttribute, value: true, range: range)
        } else {
            storage.removeAttribute(RichTextDefaults.syntheticItalicAttribute, range: range)
        }
        for (subrange, font) in runs {
            storage.addAttribute(
                .font,
                value: convertedItalicFont(font, adding: adding, manager: manager),
                range: subrange
            )
        }
        storage.endEditing()
        textView.didChangeText()
        refreshSelectionState()
    }

    private func convertedItalicFont(
        _ font: NSFont,
        adding: Bool,
        manager: NSFontManager
    ) -> NSFont {
        if adding {
            if manager.traits(of: font).contains(.italicFontMask)
                || RichTextDefaults.isSyntheticItalic(font) {
                return font
            }

            let nativeItalic = manager.convert(font, toHaveTrait: .italicFontMask)
            if manager.traits(of: nativeItalic).contains(.italicFontMask) {
                return nativeItalic
            }
            return RichTextDefaults.syntheticItalicFont(from: font)
        }

        let untransformed = RichTextDefaults.baseFont(from: font, force: true)
        return manager.convert(untransformed, toNotHaveTrait: .italicFontMask)
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

    private func selectionHasFontTrait(_ trait: NSFontTraitMask, in textView: NSTextView) -> Bool {
        allSelectedRuns(in: textView) { attributes in
            let font = attributes[.font] as? NSFont ?? textView.font ?? NSFont.systemFont(ofSize: 16)
            return NSFontManager.shared.traits(of: font).contains(trait)
        }
    }

    private func selectionHasItalic(in textView: NSTextView) -> Bool {
        allSelectedRuns(in: textView) { attributes in
            let font = attributes[.font] as? NSFont ?? textView.font ?? NSFont.systemFont(ofSize: 16)
            return NSFontManager.shared.traits(of: font).contains(.italicFontMask)
                || styleIsEnabled(attributes[RichTextDefaults.syntheticItalicAttribute])
                || RichTextDefaults.isSyntheticItalic(font)
                || styleIsEnabled(attributes[.obliqueness])
        }
    }

    private func selectionHasEnabledAttribute(
        _ key: NSAttributedString.Key,
        in textView: NSTextView
    ) -> Bool {
        allSelectedRuns(in: textView) { styleIsEnabled($0[key]) }
    }

    private func allSelectedRuns(
        in textView: NSTextView,
        satisfy predicate: ([NSAttributedString.Key: Any]) -> Bool
    ) -> Bool {
        let range = textView.selectedRange()
        guard range.length > 0,
              let storage = textView.textStorage,
              storage.length > 0
        else {
            return predicate(textView.typingAttributes)
        }

        var allMatch = true
        storage.enumerateAttributes(in: range) { attributes, _, stop in
            guard predicate(attributes) else {
                allMatch = false
                stop.pointee = true
                return
            }
        }
        return allMatch
    }

    private func styleIsEnabled(_ value: Any?) -> Bool {
        if let boolean = value as? Bool { return boolean }
        if let number = value as? NSNumber { return number.doubleValue != 0 }
        if let integer = value as? Int { return integer != 0 }
        if let double = value as? Double { return double != 0 }
        if let float = value as? Float { return float != 0 }
        if let cgFloat = value as? CGFloat { return cgFloat != 0 }
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

enum RichTextDefaults {
    static let persistedItalicObliqueness = 0.55
    static let syntheticItalicShear = 0.55
    static let syntheticItalicAttribute = NSAttributedString.Key("TinyDeskSyntheticItalic")

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
            return renderedAttributedString(from: attributed)
        }

        return NSAttributedString(string: fallbackText, attributes: attributes(fontSize: fontSize))
    }

    static func rtfData(from attributedString: NSAttributedString) -> Data? {
        let serializable = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: serializable.length)
        var syntheticRuns: [(NSRange, NSFont)] = []
        serializable.enumerateAttributes(in: fullRange) { attributes, range, _ in
            guard let font = attributes[.font] as? NSFont,
                  numericValue(attributes[syntheticItalicAttribute]) != 0 || isSyntheticItalic(font)
            else { return }
            syntheticRuns.append((range, font))
        }

        serializable.removeAttribute(syntheticItalicAttribute, range: fullRange)
        for (range, font) in syntheticRuns {
            serializable.addAttribute(.font, value: baseFont(from: font, force: true), range: range)
            serializable.addAttribute(
                .obliqueness,
                value: persistedItalicObliqueness,
                range: range
            )
        }

        return try? serializable.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    static func syntheticItalicFont(from font: NSFont) -> NSFont {
        guard !isSyntheticItalic(font) else { return font }
        let transform = AffineTransform(
            m11: 1,
            m12: 0,
            m21: syntheticItalicShear,
            m22: 1,
            tX: 0,
            tY: 0
        )
        return NSFont(
            descriptor: font.fontDescriptor.withMatrix(transform),
            size: font.pointSize
        ) ?? font
    }

    static func baseFont(from font: NSFont, force: Bool = false) -> NSFont {
        guard force || isSyntheticItalic(font) else { return font }
        if let named = NSFont(name: font.fontName, size: font.pointSize) {
            return named
        }
        return NSFont(
            descriptor: font.fontDescriptor.withMatrix(AffineTransform()),
            size: font.pointSize
        ) ?? font
    }

    static func isSyntheticItalic(_ font: NSFont) -> Bool {
        let matrix = font.matrix
        guard matrix[0] != 0 else { return false }
        return abs(matrix[2] / matrix[0]) >= 0.1
    }

    private static func renderedAttributedString(from attributed: NSAttributedString) -> NSAttributedString {
        let rendered = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: rendered.length)
        var italicRuns: [(NSRange, NSFont)] = []

        rendered.enumerateAttributes(in: fullRange) { attributes, range, _ in
            guard numericValue(attributes[.obliqueness]) != 0 else { return }
            let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 16)
            italicRuns.append((range, font))
        }

        for (range, font) in italicRuns {
            if !NSFontManager.shared.traits(of: font).contains(.italicFontMask) {
                rendered.addAttribute(.font, value: syntheticItalicFont(from: font), range: range)
                rendered.addAttribute(syntheticItalicAttribute, value: true, range: range)
            }
            rendered.removeAttribute(.obliqueness, range: range)
        }
        return rendered
    }

    private static func numericValue(_ value: Any?) -> Double {
        if let boolean = value as? Bool { return boolean ? 1 : 0 }
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        if let float = value as? Float { return Double(float) }
        if let cgFloat = value as? CGFloat { return Double(cgFloat) }
        return 0
    }
}
