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
    /// 当前资料库文档的字体预设（工具栏高亮用）。
    @Published var currentFontPreset: RichTextDefaults.FontPreset = .fangSong
    /// 用户最近一次显式选择的文字颜色；自适应前景色不得覆盖它。
    fileprivate(set) var userSelectedForeground: NSColor?

    private weak var textView: NSTextView?

    func connect(to textView: NSTextView) {
        guard self.textView !== textView else { return }
        self.textView = textView
        isReady = true
        refreshSelectionState()
    }

    /// 用外部读到的正文替换编辑器内容（资料库加载文档用）。
    func present(
        _ attributedString: NSAttributedString,
        fontPreset: RichTextDefaults.FontPreset,
        defaultTextColor: NSColor = .labelColor
    ) {
        guard let textView else { return }
        currentFontPreset = fontPreset
        userSelectedForeground = nil
        textView.textStorage?.setAttributedString(attributedString)
        var typingAttributes = RichTextDefaults.attributes(fontSize: 16, preset: fontPreset)
        typingAttributes[.foregroundColor] = defaultTextColor
        textView.textColor = defaultTextColor
        textView.typingAttributes = typingAttributes
        refreshSelectionState()
    }

    /// 应用字号（资料库）。
    func applyFontSize(_ pointSize: CGFloat) {
        guard let textView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var typing = textView.typingAttributes
            let font = typing[.font] as? NSFont ?? textView.font ?? RichTextDefaults.font(size: 16)
            typing[.font] = RichTextDefaults.resized(font, to: pointSize)
            textView.typingAttributes = typing
            refreshSelectionState()
            return
        }
        guard textView.shouldChangeText(in: range, replacementString: nil),
              let storage = textView.textStorage
        else { return }

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? textView.font ?? RichTextDefaults.font(size: 16)
            storage.addAttribute(.font, value: RichTextDefaults.resized(font, to: pointSize), range: subrange)
        }
        storage.endEditing()
        textView.didChangeText()
        refreshSelectionState()
    }

    /// 应用中文字体预设（资料库）。
    func applyFontPreset(_ preset: RichTextDefaults.FontPreset) {
        guard let textView else { return }
        currentFontPreset = preset
        let range = textView.selectedRange()
        if range.length == 0 {
            var typing = textView.typingAttributes
            let font = typing[.font] as? NSFont ?? textView.font ?? RichTextDefaults.font(size: 16)
            typing[.font] = RichTextDefaults.font(size: font.pointSize, preset: preset)
            textView.typingAttributes = typing
            refreshSelectionState()
            return
        }
        guard textView.shouldChangeText(in: range, replacementString: nil),
              let storage = textView.textStorage
        else { return }

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? textView.font ?? RichTextDefaults.font(size: 16)
            storage.addAttribute(.font, value: RichTextDefaults.font(size: font.pointSize, preset: preset), range: subrange)
        }
        storage.endEditing()
        textView.didChangeText()
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
        userSelectedForeground = color
        guard let textView else { return }
        applyAttribute(.foregroundColor, value: color, in: textView)
    }

    func clearFormatting() {
        guard let textView else { return }
        userSelectedForeground = nil
        currentFontPreset = .system
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
            .paragraphStyle,
            .kern,
            .baselineOffset,
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
            isBold: fontHasBoldTrait(font),
            isItalic: traits.contains(.italicFontMask)
                || styleIsEnabled(attributes[RichTextDefaults.syntheticItalicAttribute])
                || RichTextDefaults.isSyntheticItalic(font)
                || styleIsEnabled(attributes[.obliqueness]),
            isUnderlined: styleIsEnabled(attributes[.underlineStyle]),
            isStruckThrough: styleIsEnabled(attributes[.strikethroughStyle]),
            foregroundColor: attributes[.foregroundColor] as? NSColor ?? textView.textColor ?? .labelColor
        )
    }

    /// 判断字体是否具有加粗语义，兼容半粗体（PingFangSC-Semibold 等）。
    private func fontHasBoldTrait(_ font: NSFont) -> Bool {
        let traits = NSFontManager.shared.traits(of: font)
        if traits.contains(.boldFontMask) { return true }
        let name = font.fontName.lowercased()
        return name.contains("semibold") || name.contains("bold")
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
            if trait == .boldFontMask {
                let candidate = manager.convert(sourceFont, toHaveTrait: .boldFontMask)
                if manager.traits(of: candidate).contains(.boldFontMask) {
                    converted = candidate
                } else if let fallback = RichTextDefaults.boldFallbackFont(from: sourceFont) {
                    // 仿宋/宋体等没有粗体字重的字体：回退到可加粗的中文字体，
                    // 保证视觉加粗与 RTF 持久化，工具栏状态保持正确。
                    converted = fallback
                } else {
                    converted = candidate
                }
            } else {
                converted = manager.convert(sourceFont, toHaveTrait: trait)
            }
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
                // 只有非原生斜体才需要合成斜体标记，避免 RTF 落盘时改写原生斜体。
                let isNativeItalic = manager.traits(of: font).contains(.italicFontMask)
                    || RichTextDefaults.isSyntheticItalic(font)
                if isNativeItalic {
                    typing.removeValue(forKey: RichTextDefaults.syntheticItalicAttribute)
                } else {
                    typing[RichTextDefaults.syntheticItalicAttribute] = true
                }
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
        for (subrange, font) in runs {
            if adding {
                let isNativeItalic = manager.traits(of: font).contains(.italicFontMask)
                    || RichTextDefaults.isSyntheticItalic(font)
                if isNativeItalic {
                    storage.removeAttribute(RichTextDefaults.syntheticItalicAttribute, range: subrange)
                } else {
                    storage.addAttribute(RichTextDefaults.syntheticItalicAttribute, value: true, range: subrange)
                }
            } else {
                storage.removeAttribute(RichTextDefaults.syntheticItalicAttribute, range: subrange)
            }
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
            if trait == .boldFontMask {
                return fontHasBoldTrait(font)
            }
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

enum RichTextReloadPolicy {
    static func shouldReload(
        didLoad: Bool,
        reloadsFromExternalChanges: Bool,
        richTextData: Data?,
        fallbackText: String,
        lastRichTextData: Data?,
        lastPlainText: String
    ) -> Bool {
        guard didLoad else { return true }
        guard reloadsFromExternalChanges else { return false }
        return richTextData != lastRichTextData || fallbackText != lastPlainText
    }
}

/// 让富文本在不同深浅纸张上保持可读，同时保留文档中真实存储的文字颜色。
enum RichTextContrast {
    static let minimumRatio: CGFloat = 3.0

    static func contrastRatio(foreground: NSColor, background: NSColor) -> CGFloat {
        let foregroundLuminance = relativeLuminance(
            color: foreground,
            compositedOn: background
        )
        let backgroundLuminance = relativeLuminance(color: background, compositedOn: background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func needsAdaptiveForeground(_ foreground: NSColor?, on background: NSColor) -> Bool {
        guard let foreground else { return true }
        return contrastRatio(foreground: foreground, background: background) < minimumRatio
    }

    static func displayAttributedString(
        from source: NSAttributedString,
        background: NSColor,
        fallback: NSColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let range = NSRange(location: 0, length: result.length)
        guard range.length > 0 else { return result }

        source.enumerateAttribute(.foregroundColor, in: range) { value, subrange, _ in
            let color = value as? NSColor
            if needsAdaptiveForeground(color, on: background) {
                result.addAttribute(.foregroundColor, value: fallback, range: subrange)
            }
        }
        return result
    }

    @MainActor
    static func applyTemporaryForegrounds(
        to textView: NSTextView,
        background: NSColor,
        fallback: NSColor,
        range: NSRange? = nil
    ) {
        guard let storage = textView.textStorage,
              let layoutManager = textView.layoutManager
        else { return }

        let fullRange = NSRange(location: 0, length: storage.length)
        let target: NSRange
        if let range {
            let intersection = NSIntersectionRange(range, fullRange)
            target = intersection.length > 0 ? intersection : NSRange(location: 0, length: 0)
        } else {
            target = fullRange
        }
        if target.length == 0 { return }

        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: target)

        storage.enumerateAttribute(.foregroundColor, in: target) { value, subrange, _ in
            let color = value as? NSColor
            if needsAdaptiveForeground(color, on: background) {
                layoutManager.addTemporaryAttribute(
                    .foregroundColor,
                    value: fallback,
                    forCharacterRange: subrange
                )
            }
        }
    }

    private static func relativeLuminance(color: NSColor, compositedOn background: NSColor) -> CGFloat {
        guard let foregroundRGB = color.usingColorSpace(.sRGB),
              let backgroundRGB = background.usingColorSpace(.sRGB)
        else { return 0 }

        let alpha = foregroundRGB.alphaComponent
        let red = foregroundRGB.redComponent * alpha + backgroundRGB.redComponent * (1 - alpha)
        let green = foregroundRGB.greenComponent * alpha + backgroundRGB.greenComponent * (1 - alpha)
        let blue = foregroundRGB.blueComponent * alpha + backgroundRGB.blueComponent * (1 - alpha)

        func linearize(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(red)
            + 0.7152 * linearize(green)
            + 0.0722 * linearize(blue)
    }
}

struct RichTextEditor: NSViewRepresentable {
    let richTextData: Data?
    let fallbackText: String
    let fontSize: CGFloat
    let controller: RichTextEditorController
    /// 桌面便签由外部 Binding 驱动；资料库正文则由同一编辑会话负责，
    /// 避免存储层刷新时把用户刚输入的内容重新替换掉。
    var reloadsFromExternalChanges = true
    /// 资料库纸张主题可指定默认输入颜色；桌面便签仍使用系统文字色。
    var defaultTextColor: NSColor? = nil
    /// 指定后，仅把低对比度文字临时显示成主题字色，不修改或保存用户原有颜色。
    var adaptiveBackgroundColor: NSColor? = nil
    /// 编辑正文的安全留白。桌面便签使用默认值，资料库使用更宽的纸张边距。
    var textContainerInset = NSSize(width: 8, height: 0)
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
        textView.textContainerInset = textContainerInset
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.usesFindPanel = true
        textView.font = RichTextDefaults.font(size: fontSize)
        let textColor = defaultTextColor ?? .labelColor
        textView.textColor = textColor
        var typingAttributes = RichTextDefaults.attributes(fontSize: fontSize)
        typingAttributes[.foregroundColor] = textColor
        textView.typingAttributes = typingAttributes

        scrollView.documentView = textView
        context.coordinator.load(richTextData: richTextData, fallbackText: fallbackText, into: textView)
        controller.connect(to: textView)
        context.coordinator.refreshAdaptiveForeground(in: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        controller.connect(to: textView)

        if context.coordinator.shouldReload(richTextData: richTextData, fallbackText: fallbackText) {
            context.coordinator.load(richTextData: richTextData, fallbackText: fallbackText, into: textView)
        }
        context.coordinator.refreshAdaptiveForeground(in: textView)
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
            RichTextReloadPolicy.shouldReload(
                didLoad: didLoad,
                reloadsFromExternalChanges: parent.reloadsFromExternalChanges,
                richTextData: richTextData,
                fallbackText: fallbackText,
                lastRichTextData: lastRichTextData,
                lastPlainText: lastPlainText
            )
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
            var typingAttributes = RichTextDefaults.attributes(fontSize: parent.fontSize)
            typingAttributes[.foregroundColor] = parent.defaultTextColor ?? .labelColor
            textView.textColor = parent.defaultTextColor ?? .labelColor
            textView.typingAttributes = typingAttributes
            lastRichTextData = richTextData
            lastPlainText = fallbackText
            didLoad = true
            parent.controller.userSelectedForeground = nil
            parent.controller.refreshSelectionState()
            refreshAdaptiveForeground(in: textView)
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
            // 只处理本次编辑范围，避免每次键入都扫描并重算全文临时前景色。
            let editedRange = textView.textStorage?.editedRange
                ?? NSRange(location: 0, length: textView.string.utf16.count)
            refreshAdaptiveForeground(in: textView, editedRange: editedRange)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.controller.refreshSelectionState()
        }

        func refreshAdaptiveForeground(in textView: NSTextView, editedRange: NSRange? = nil) {
            guard let background = parent.adaptiveBackgroundColor else {
                if let layoutManager = textView.layoutManager {
                    layoutManager.removeTemporaryAttribute(
                        .foregroundColor,
                        forCharacterRange: NSRange(location: 0, length: textView.string.utf16.count)
                    )
                }
                return
            }

            let fallback = parent.defaultTextColor ?? .labelColor
            textView.textColor = fallback
            // 用户显式选择的颜色不被自适应前景色覆盖。
            if parent.controller.userSelectedForeground == nil {
                var typingAttributes = textView.typingAttributes
                if RichTextContrast.needsAdaptiveForeground(
                    typingAttributes[.foregroundColor] as? NSColor,
                    on: background
                ) {
                    typingAttributes[.foregroundColor] = fallback
                    textView.typingAttributes = typingAttributes
                }
            }
            RichTextContrast.applyTemporaryForegrounds(
                to: textView,
                background: background,
                fallback: fallback,
                range: editedRange
            )
        }
    }
}

enum RichTextDefaults {
    static let persistedItalicObliqueness = 0.55
    static let syntheticItalicShear = 0.55
    static let syntheticItalicAttribute = NSAttributedString.Key("TinyDeskSyntheticItalic")

    /// 正文基准字号（资料库编辑器使用）。
    static let bodyFontSize: CGFloat = 16

    /// 资料库中文字体预设，独立于 Core 模型以便独立编译测试。
    enum FontPreset: String, CaseIterable {
        case fangSong
        case songTi
        case system

        var displayName: String {
            switch self {
            case .fangSong: return "仿宋"
            case .songTi: return "宋体"
            case .system: return "系统默认"
            }
        }
    }

    /// 按字体预设返回中文字体；英文始终使用 Apple 系统字体。
    static func font(size: CGFloat, preset: FontPreset = .system) -> NSFont {
        switch preset {
        case .fangSong:
            return fangSongFont(size: size)
        case .songTi:
            return songTiFont(size: size)
        case .system:
            return font(size: size)
        }
    }

    /// 仿宋优先，缺失时降级宋体，再降级系统字体。
    static func fangSongFont(size: CGFloat) -> NSFont {
        if let fangSong = NSFont(name: "STFangsong", size: size) {
            return fangSong
        }
        return songTiFont(size: size)
    }

    /// 宋体，缺失时降级系统字体。
    static func songTiFont(size: CGFloat) -> NSFont {
        if let songTi = NSFont(name: "STSongti-SC", size: size) {
            return songTi
        }
        return NSFont.systemFont(ofSize: size)
    }

    static func font(size: CGFloat) -> NSFont {
        let systemFont = NSFont.systemFont(ofSize: size)
        guard let descriptor = systemFont.fontDescriptor.withDesign(.rounded) else {
            return systemFont
        }
        return NSFont(descriptor: descriptor, size: size) ?? systemFont
    }

    /// 按字号缩放字体，保留字体族与斜体矩阵。
    static func resized(_ font: NSFont, to pointSize: CGFloat) -> NSFont {
        guard font.pointSize != pointSize else { return font }
        let descriptor = font.fontDescriptor.withSize(pointSize)
        return NSFont(descriptor: descriptor, size: pointSize) ?? font
    }

    /// 字体族没有粗体字重时的加粗回退：先尝试加粗字重转换，
    /// 仿宋/宋体回退到苹方半粗体，保证中文视觉加粗。
    static func boldFallbackFont(from font: NSFont) -> NSFont? {
        let family = font.familyName ?? ""
        let name = font.fontName
        let chineseFamilies = ["STFangsong", "STSongti-SC", "FangSong", "Songti SC", "Songti"]
        if chineseFamilies.contains(where: { family == $0 || name == $0 }) {
            return NSFont(name: "PingFangSC-Semibold", size: font.pointSize)
                ?? NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        }
        let heavier = NSFontManager.shared.convertWeight(true, of: font)
        if NSFontManager.shared.traits(of: heavier).contains(.boldFontMask) {
            return heavier
        }
        return nil
    }

    static func attributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        attributes(fontSize: fontSize, preset: .system)
    }

    static func attributes(fontSize: CGFloat, preset: FontPreset) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return [
            .font: font(size: fontSize, preset: preset),
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
