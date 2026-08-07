import AppKit
import CoreGraphics
import Foundation
import TinyDeskCore

/// 用 NSLayoutManager 分页，把文档按纸张主题渲染为多页 PDF。
enum LibraryPDFRenderer {
    /// 把文档正文渲染为 PDF 数据，背景使用文档的纸张主题。
    /// 长文档按声明纸张尺寸分页输出，不允许出现单页数千点的非标准 PDF。
    static func render(
        attributedString: NSAttributedString,
        paperTheme: PaperTheme
    ) throws -> Data {
        let style = PaperThemeStyle.style(for: paperTheme)

        let pageSize = NSSize(width: 612, height: 792)
        let horizontalMargin: CGFloat = 40
        let verticalMargin: CGFloat = 40
        let contentWidth = pageSize.width - horizontalMargin * 2
        let contentHeight = pageSize.height - verticalMargin * 2

        let display = RichTextContrast.displayAttributedString(
            from: attributedString,
            background: style.backgroundColor,
            fallback: style.textColor
        )
        let textStorage = NSTextStorage(attributedString: display)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(
            size: NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        let usedHeight = layoutManager.usedRect(for: container).height
        let totalTextHeight = verticalMargin * 2 + usedHeight
        let pageCount = max(1, Int(ceil(totalTextHeight / contentHeight)))

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw LibraryPDFError.pdfContextFailed
        }
        var mediaBox = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
        guard let cgContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw LibraryPDFError.pdfContextFailed
        }

        for page in 0..<pageCount {
            cgContext.beginPDFPage(nil)
            let nsContext = NSGraphicsContext(cgContext: cgContext, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext

            // 纸张背景
            style.backgroundColor.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)).fill()
            if [.moQing, .yeMo, .songYan, .yunJin].contains(paperTheme) {
                if let gradient = NSGradient(
                    starting: style.accentColor.withAlphaComponent(0.12),
                    ending: NSColor.clear
                ) {
                    gradient.draw(
                        in: NSRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height),
                        angle: -60
                    )
                }
            }

            if usedHeight > 0 {
                let sliceRect = NSRect(
                    x: 0,
                    y: CGFloat(page) * contentHeight,
                    width: contentWidth,
                    height: contentHeight
                )
                let glyphRange = layoutManager.glyphRange(forBoundingRect: sliceRect, in: container)

                // 页面区域裁剪：PDF 坐标原点在左下，文本容器坐标 y 向下。
                nsContext.cgContext.saveGState()
                nsContext.cgContext.clip(
                    to: CGRect(
                        x: horizontalMargin,
                        y: verticalMargin,
                        width: contentWidth,
                        height: contentHeight
                    )
                )
                nsContext.cgContext.translateBy(
                    x: horizontalMargin,
                    y: verticalMargin + contentHeight
                )
                nsContext.cgContext.scaleBy(x: 1, y: -1)
                nsContext.cgContext.translateBy(x: 0, y: -CGFloat(page) * contentHeight)

                layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
                layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
                nsContext.cgContext.restoreGState()
            }

            NSGraphicsContext.restoreGraphicsState()
            cgContext.endPDFPage()
        }
        cgContext.closePDF()
        return data as Data
    }
}

/// PDF 渲染错误。
enum LibraryPDFError: LocalizedError {
    case pdfContextFailed

    var errorDescription: String? {
        switch self {
        case .pdfContextFailed: return "无法创建 PDF 绘图上下文。"
        }
    }
}
