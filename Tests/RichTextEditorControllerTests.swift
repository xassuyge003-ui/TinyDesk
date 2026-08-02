import AppKit
import Foundation

@main
struct RichTextEditorControllerTests {
    @MainActor
    static func main() throws {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let font = roundedFont(size: 17)
        let source = "TinyDesk 富文本测试"
        textView.textStorage?.setAttributedString(
            NSAttributedString(
                string: source,
                attributes: [.font: font, .foregroundColor: NSColor.labelColor]
            )
        )
        textView.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]

        let selection = NSRange(
            location: ("TinyDesk " as NSString).length,
            length: ("富文本" as NSString).length
        )
        textView.setSelectedRange(selection)

        let controller = RichTextEditorController()
        controller.connect(to: textView)

        controller.toggleBold()
        try require(controller.format.isBold, "粗体状态未更新")
        try require(selectedFont(in: textView, at: selection).fontDescriptor.symbolicTraits.contains(.bold), "粗体未应用")
        controller.toggleBold()
        try require(!controller.format.isBold, "粗体状态无法关闭")
        try require(!selectedFont(in: textView, at: selection).fontDescriptor.symbolicTraits.contains(.bold), "粗体无法恢复")

        controller.toggleItalic()
        try require(controller.format.isItalic, "斜体状态未更新")
        try require(fontShear(selectedFont(in: textView, at: selection)) >= 0.5, "中文字形未进行几何倾斜")
        try require(
            textView.textStorage?.attribute(
                RichTextDefaults.syntheticItalicAttribute,
                at: selection.location,
                effectiveRange: nil
            ) as? Bool == true,
            "斜体运行时标记未写入"
        )
        controller.toggleBold()
        try require(controller.format.isBold, "斜体与粗体无法组合")
        try require(fontShear(selectedFont(in: textView, at: selection)) >= 0.5, "加粗时丢失斜体")
        controller.toggleBold()
        try require(!controller.format.isBold, "斜体文字无法恢复常规字重")
        try require(fontShear(selectedFont(in: textView, at: selection)) >= 0.5, "恢复字重时丢失斜体")
        controller.toggleItalic()
        try require(!controller.format.isItalic, "斜体状态无法关闭")
        try require(fontShear(selectedFont(in: textView, at: selection)) == 0, "斜体无法恢复")
        try require(
            textView.textStorage?.attribute(
                RichTextDefaults.syntheticItalicAttribute,
                at: selection.location,
                effectiveRange: nil
            ) == nil,
            "关闭斜体后运行时标记未移除"
        )

        controller.toggleUnderline()
        controller.toggleStrikethrough()
        controller.applyForegroundColor(.systemBlue)
        try require(controller.format.isUnderlined, "下划线状态未更新")
        try require(controller.format.isStruckThrough, "删除线状态未更新")
        try require(selectedColor(in: textView, at: selection) == .systemBlue, "文字颜色未应用")
        try require(textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .labelColor, "格式越过选区")

        controller.toggleUnderline()
        controller.toggleStrikethrough()
        try require(!controller.format.isUnderlined, "下划线无法关闭")
        try require(!controller.format.isStruckThrough, "删除线无法关闭")

        controller.toggleItalic()
        guard let storage = textView.textStorage else { throw TestError.missingStorage }
        guard let rtf = RichTextDefaults.rtfData(from: storage) else {
            throw TestError.missingRTF
        }
        let rawRestored = try NSAttributedString(
            data: rtf,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        let rawRestoredAttributes = rawRestored.attributes(at: selection.location, effectiveRange: nil)
        try require((rawRestoredAttributes[.obliqueness] as? NSNumber)?.doubleValue ?? 0 > 0, "几何斜体未写入 RTF")

        let restored = RichTextDefaults.attributedString(
            from: rtf,
            fallbackText: "",
            fontSize: 17
        )
        let restoredAttributes = restored.attributes(at: selection.location, effectiveRange: nil)
        let restoredFont = restoredAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 17)
        try require(fontShear(restoredFont) >= 0.5, "RTF 恢复后未重建几何斜体")
        try require(
            restoredAttributes[RichTextDefaults.syntheticItalicAttribute] as? Bool == true,
            "RTF 恢复后未重建斜体运行时标记"
        )
        try require(restoredAttributes[.foregroundColor] as? NSColor != nil, "颜色未写入 RTF")

        let restoredTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        restoredTextView.textStorage?.setAttributedString(restored)
        restoredTextView.setSelectedRange(selection)
        let restoredController = RichTextEditorController()
        restoredController.connect(to: restoredTextView)
        try require(restoredController.format.isItalic, "RTF 恢复后未识别斜体状态")
        restoredController.toggleItalic()
        try require(!restoredController.format.isItalic, "RTF 恢复后无法关闭斜体")
        try require(
            fontShear(selectedFont(in: restoredTextView, at: selection)) == 0,
            "RTF 恢复后关闭斜体未恢复字体矩阵"
        )

        print("RichTextEditorControllerTests: passed")
    }

    private static func roundedFont(size: CGFloat) -> NSFont {
        let systemFont = NSFont.systemFont(ofSize: size)
        guard let descriptor = systemFont.fontDescriptor.withDesign(.rounded) else {
            return systemFont
        }
        return NSFont(descriptor: descriptor, size: size) ?? systemFont
    }

    @MainActor
    private static func selectedFont(in textView: NSTextView, at range: NSRange) -> NSFont {
        textView.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            ?? NSFont.systemFont(ofSize: 17)
    }

    @MainActor
    private static func selectedColor(in textView: NSTextView, at range: NSRange) -> NSColor? {
        textView.textStorage?.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
    }

    private static func fontShear(_ font: NSFont) -> CGFloat {
        let matrix = font.matrix
        guard matrix[0] != 0 else { return 0 }
        return abs(matrix[2] / matrix[0])
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestError.failed(message) }
    }

    private enum TestError: Error {
        case missingStorage
        case missingRTF
        case failed(String)
    }
}
