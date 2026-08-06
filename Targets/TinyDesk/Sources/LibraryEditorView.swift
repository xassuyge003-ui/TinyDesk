import AppKit
import SwiftUI
import TinyDeskCore

/// 资料库长文档编辑器：纸张背景 + NSTextView + 格式工具栏。
struct LibraryEditorView: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        Group {
            if let document = selectedDocument {
                editor(for: document)
            } else {
                emptyState
            }
        }
    }

    private var selectedDocument: LibraryDocument? {
        guard let id = store.selectedDocumentID else { return nil }
        return store.document(withID: id)
    }

    private func editor(for document: LibraryDocument) -> some View {
        LibraryEditorContent(document: document)
            .id(document.id)
            .environmentObject(store)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("选择或新建一篇资料文档")
                .font(.headline)
            Text("正文会保存在本地 RTFD 中，格式完整保留")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 单个文档的编辑器主体。以 document.id 作为 identity，切换文档时重建。
private struct LibraryEditorContent: View {
    private struct BodySave: Equatable {
        let data: Data?
        let plainText: String
    }

    @EnvironmentObject private var store: LibraryStore
    @StateObject private var editorController = RichTextEditorController()
    @State private var draftTitle: String
    @State private var pendingBodySave: Task<Void, Never>?
    @State private var pendingBody: BodySave?

    let document: LibraryDocument

    init(document: LibraryDocument) {
        self.document = document
        _draftTitle = State(initialValue: document.title)
    }

    private var style: PaperThemeStyle {
        .style(for: document.paperTheme)
    }

    private var chrome: LibraryChrome {
        LibraryChrome(theme: document.paperTheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(chrome.separator)
            LibraryFormattingToolbar(
                controller: editorController,
                theme: document.paperTheme
            ) { preset in
                store.updateMetadata(document.id) { metadata in
                    metadata.fontPreset = Self.documentFontPreset(from: preset)
                }
            }
            Divider().overlay(chrome.separator)
            editorBody
            statusBar
        }
        .background(PaperBackground(theme: document.paperTheme, showsOrnament: false))
        .onAppear {
            editorController.currentFontPreset = Self.richTextPreset(from: document.fontPreset)
        }
        .onDisappear {
            flushPendingBodySave()
        }
    }

    /// 把 Core 的字体预设映射为编辑器工具栏的预设。
    private static func richTextPreset(from preset: FontPreset) -> RichTextDefaults.FontPreset {
        switch preset {
        case .fangSong: return .fangSong
        case .songTi: return .songTi
        case .system: return .system
        }
    }

    private static func documentFontPreset(from preset: RichTextDefaults.FontPreset) -> FontPreset {
        switch preset {
        case .fangSong: return .fangSong
        case .songTi: return .songTi
        case .system: return .system
        }
    }

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: document.paperTheme.symbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(style.accentColorSwiftUI)
            TextField("文档标题", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(NSFont(name: "STFangsong", size: 22) != nil
                    ? .custom("STFangsong", size: 22)
                    : .system(size: 22, weight: .semibold))
                .foregroundStyle(style.textColorSwiftUI)
                .onSubmit { commitTitle() }
                .onChange(of: draftTitle) { _, newValue in
                    commitTitle(newValue)
                }
            Spacer()
            Menu {
                ForEach(PaperTheme.allCases, id: \.self) { theme in
                    Button {
                        store.updateMetadata(document.id) { $0.paperTheme = theme }
                    } label: {
                        Label(
                            "\(theme.displayName) · \(theme.materialDescription)",
                            systemImage: document.paperTheme == theme ? "checkmark.circle.fill" : theme.symbolName
                        )
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    PaperThemeSwatch(theme: document.paperTheme)
                    Text(document.paperTheme.displayName)
                        .font(.caption)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(style.textColorSwiftUI.opacity(0.82))
                .padding(.horizontal, 7)
                .frame(height: 26)
                .background(style.textColorSwiftUI.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("选择花笺材料")

            Button {
                store.toggleFavorite(document.id)
            } label: {
                Image(systemName: document.isFavorited ? "star.fill" : "star")
                    .foregroundStyle(
                        document.isFavorited
                            ? style.accentColorSwiftUI
                            : style.textColorSwiftUI.opacity(0.55)
                    )
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .help(document.isFavorited ? "取消收藏" : "收藏")
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 14)
        .background(PaperBackground(theme: document.paperTheme, showsOrnament: false))
    }

    private var editorBody: some View {
        RichTextEditor(
            richTextData: nil,
            fallbackText: initialBodyText,
            fontSize: 16,
            controller: editorController,
            reloadsFromExternalChanges: false,
            defaultTextColor: style.textColor,
            adaptiveBackgroundColor: style.backgroundColor,
            textContainerInset: NSSize(width: 48, height: 28),
            onChange: persistBody
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperBackground(theme: document.paperTheme))
        .onAppear { loadBody() }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text("\(document.paperTheme.displayName) · 本地保存")
                .font(.caption)
                .foregroundStyle(style.accentColorSwiftUI)
            Spacer()
            Text("\(wordCount) 字")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(style.textColorSwiftUI.opacity(0.64))
            Text("修改于 \(document.updatedAt.formatted(.relative(presentation: .named)))")
                .font(.caption2)
                .foregroundStyle(style.textColorSwiftUI.opacity(0.64))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(PaperBackground(theme: document.paperTheme, showsOrnament: false))
    }

    private var initialBodyText: String {
        // 首次渲染用空文本占位，避免闪动；真实内容在 onAppear 读取。
        ""
    }

    private var wordCount: Int {
        document.wordCount
    }

    private func commitTitle(_ value: String = "") {
        let resolved = value.isEmpty ? draftTitle : value
        let trimmed = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != document.title else { return }
        store.updateMetadata(document.id) { doc in
            doc.title = trimmed
        }
    }

    private func loadBody() {
        guard let attributed = store.loadAttributedString(for: document) else {
            return
        }
        editorController.present(
            attributed,
            fontPreset: Self.richTextPreset(from: document.fontPreset),
            defaultTextColor: style.textColor
        )
    }

    private func persistBody(_ data: Data?, _ plainText: String) {
        pendingBodySave?.cancel()
        let snapshot = BodySave(data: data, plainText: plainText)
        pendingBody = snapshot
        let documentID = document.id
        pendingBodySave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, pendingBody == snapshot else { return }
            saveBody(snapshot.data, plainText: snapshot.plainText, for: documentID)
            pendingBody = nil
            pendingBodySave = nil
        }
    }

    private func flushPendingBodySave() {
        pendingBodySave?.cancel()
        pendingBodySave = nil
        guard let pendingBody else { return }
        saveBody(pendingBody.data, plainText: pendingBody.plainText, for: document.id)
        self.pendingBody = nil
    }

    private func saveBody(_ data: Data?, plainText: String, for documentID: UUID) {
        let attributed: NSAttributedString
        if let data {
            guard let decoded = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) else { return }
            attributed = decoded
        } else {
            attributed = NSAttributedString(string: "")
        }
        store.updateDocument(documentID, attributedString: attributed) { doc in
            doc.wordCount = plainText.count
            doc.summary = String(plainText.prefix(120))
        }
    }
}

/// 资料库专用格式工具栏：在桌面便签基础上增加字体、字号与标题。
private struct LibraryFormattingToolbar: View {
    @ObservedObject var controller: RichTextEditorController
    let theme: PaperTheme
    let onFontPresetChange: (RichTextDefaults.FontPreset) -> Void

    private var style: PaperThemeStyle { .style(for: theme) }
    private var chrome: LibraryChrome { LibraryChrome(theme: theme) }
    private var accent: Color { style.accentColorSwiftUI }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                formatButton("bold", help: "粗体", isActive: controller.format.isBold, action: controller.toggleBold)
                formatButton("italic", help: "斜体", isActive: controller.format.isItalic, action: controller.toggleItalic)
                formatButton("underline", help: "下划线", isActive: controller.format.isUnderlined, action: controller.toggleUnderline)
                formatButton("strikethrough", help: "删除线", isActive: controller.format.isStruckThrough, action: controller.toggleStrikethrough)
            }
            .padding(2)
            .background(chrome.controlBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Menu {
                ForEach(RichTextPaletteChoice.options) { choice in
                    Button {
                        controller.applyForegroundColor(choice.color)
                    } label: {
                        Label(
                            choice.displayName,
                            systemImage: choice.matches(controller.format.foregroundColor)
                                ? "checkmark.circle.fill"
                                : "circle.fill"
                        )
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 11, weight: .semibold))
                    Text("颜色")
                        .font(LibraryTypography.label(12))
                    Circle()
                        .fill(Color(nsColor: controller.format.foregroundColor))
                        .frame(width: 10, height: 10)
                }
                .foregroundStyle(chrome.primaryText)
                .padding(.horizontal, 7)
                .frame(height: 26)
                .background(chrome.controlBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(chrome.selectionBorder.opacity(0.55), lineWidth: 0.7)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!controller.isReady)
            .help("文字颜色")

            formatButton("eraser", help: "清除格式", isActive: false, action: controller.clearFormatting)

            Divider().overlay(chrome.separator).frame(height: 16)

            Menu {
                ForEach(FontSizeOption.allCases) { option in
                    Button(option.displayName) {
                        controller.applyFontSize(option.pointSize)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "textformat.size")
                    Text("字号")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(LibraryTypography.label(12))
                .foregroundStyle(chrome.primaryText)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(chrome.controlBackground, in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!controller.isReady)
            .help("调整字号")

            Menu {
                ForEach(RichTextDefaults.FontPreset.allCases, id: \.self) { preset in
                    Button {
                        controller.applyFontPreset(preset)
                        onFontPresetChange(preset)
                    } label: {
                        Label(
                            preset.displayName,
                            systemImage: controller.currentFontPreset == preset ? "checkmark" : "textformat"
                        )
                        .font(previewFont(for: preset))
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text("字")
                        .font(LibraryTypography.title(11))
                        .frame(width: 18, height: 18)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(accent.opacity(0.85), lineWidth: 0.8)
                        }
                    Text(controller.currentFontPreset.displayName)
                        .font(previewFont(for: controller.currentFontPreset))
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(chrome.primaryText)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(accent.opacity(style.isDark ? 0.20 : 0.11), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(chrome.selectionBorder, lineWidth: 0.8)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!controller.isReady)
            .help("中文字体")
            .accessibilityLabel("字体 · \(controller.currentFontPreset.displayName)")

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(PaperBackground(theme: theme, showsOrnament: false))
    }

    private func formatButton(
        _ systemName: String,
        help: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        RichTextFormatButton(
            systemName: systemName,
            help: help,
            isActive: isActive,
            isEnabled: controller.isReady,
            activeColor: accent,
            inactiveColor: chrome.secondaryText,
            inactiveBackground: Color.clear,
            action: action
        )
    }

    private func previewFont(for preset: RichTextDefaults.FontPreset) -> Font {
        switch preset {
        case .fangSong:
            return NSFont(name: "STFangsong", size: 13) != nil
                ? .custom("STFangsong", size: 13)
                : LibraryTypography.label(13)
        case .songTi:
            return NSFont(name: "STSongti-SC", size: 13) != nil
                ? .custom("STSongti-SC", size: 13)
                : LibraryTypography.label(13)
        case .system:
            return .system(size: 12)
        }
    }
}

private enum FontSizeOption: String, CaseIterable, Identifiable {
    case small
    case middle
    case large
    case extraLarge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "小 (14)"
        case .middle: return "中 (16)"
        case .large: return "大 (18)"
        case .extraLarge: return "特大 (22)"
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .small: return 14
        case .middle: return 16
        case .large: return 18
        case .extraLarge: return 22
        }
    }
}
