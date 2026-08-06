import AppKit
import Foundation
import TinyDeskCore

/// 用 NSPrintOperation 把文档按纸张主题渲染为 PDF。
enum LibraryPDFRenderer {
    /// 把文档正文渲染为 PDF 数据，背景使用文档的纸张主题。
    static func render(
        attributedString: NSAttributedString,
        paperTheme: PaperTheme
    ) throws -> Data {
        let style = PaperThemeStyle.style(for: paperTheme)

        // 用 NSTextView 承载正文，背景用纸张色。
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textColor = style.textColor
        textView.textContainerInset = NSSize(width: 40, height: 40)
        textView.textStorage?.setAttributedString(
            RichTextContrast.displayAttributedString(
                from: attributedString,
                background: style.backgroundColor,
                fallback: style.textColor
            )
        )
        textView.frame = NSRect(
            x: 0, y: 0,
            width: 612,
            height: max(792, textView.attributedString().size().height + 120)
        )

        let container = PaperBackedView(textView: textView, theme: paperTheme)
        container.frame = textView.frame

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.paperSize = NSSize(width: 612, height: 792)
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let operation = NSPrintOperation(view: container, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false

        guard let renderedView = operation.view else {
            throw LibraryPDFError.printOperationFailed
        }
        let pdfData = renderedView.dataWithPDF(
            inside: container.bounds
        )
        return pdfData
    }
}

/// 带纸张主题背景的视图，用于 PDF 渲染。
private final class PaperBackedView: NSView {
    private let textView: NSTextView
    private let theme: PaperTheme

    init(textView: NSTextView, theme: PaperTheme) {
        self.textView = textView
        self.theme = theme
        super.init(frame: textView.frame)
        wantsLayer = true
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let style = PaperThemeStyle.style(for: theme)
        style.backgroundColor.setFill()
        bounds.fill()

        // 深色主题增加轻微亮部层次，不绘制会干扰阅读的横向行线。
        if [.moQing, .yeMo, .songYan, .yunJin].contains(theme) {
            let gradient = NSGradient(
                starting: style.accentColor.withAlphaComponent(0.12),
                ending: NSColor.clear
            )
            gradient?.draw(in: bounds, angle: -60)
        }
    }
}

/// PDF 渲染错误。
enum LibraryPDFError: LocalizedError {
    case printOperationFailed

    var errorDescription: String? {
        switch self {
        case .printOperationFailed: return "无法创建打印操作。"
        }
    }
}
