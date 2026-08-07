import AppKit
import Foundation
import TinyDeskCore

// CI 中复制为 Sources/main.swift 通过 SwiftPM 运行；
// 本地可用 swiftc 配合 Core 模块验证。

var failures = 0
var runs = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    runs += 1
    if condition() {
        print("  ✓ \(message)")
    } else {
        failures += 1
        print("  ✗ \(message)")
    }
}

let temp = FileManager.default.temporaryDirectory
    .appendingPathComponent("TinyDeskBackupTests-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: temp) }

let docDir = temp.appendingPathComponent("documents")
try FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)
let fm = LibraryFileManager(documentsDirectory: docDir)

// 写入带格式的文档
let docID = UUID()
let text = NSMutableAttributedString(
    string: "春江花月夜",
    attributes: [.font: NSFont(name: "STFangsong", size: 16) ?? .systemFont(ofSize: 16)]
)
text.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: NSRange(location: 0, length: 2))
text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 3, length: 1))
let attachmentPayload = Data("备份附件内容".utf8)
let attachmentFile = FileWrapper(regularFileWithContents: attachmentPayload)
attachmentFile.preferredFilename = "reference.txt"
text.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: attachmentFile)))
try fm.save(documentID: docID, attributedString: text)

let isDir = (try? fm.fileURL(forDocumentID: docID).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
check(isDir, "RTFD 正文保存为文件包（目录）")

// 打包备份
let doc = LibraryDocument(id: docID, title: "春江花月夜", wordCount: 5)
let archiveData = try LibraryBackup.createArchive(
    categories: [],
    tags: [],
    documents: [doc],
    fileManager: fm
)
check(archiveData.count > 0, "备份 ZIP 生成")

// 解包
let (bundle, restoredBodies) = try LibraryBackup.extractArchive(data: archiveData, fileManager: fm)
check(bundle.documents.first?.id == docID, "备份元数据往返一致")
let archiveEntries = try LibraryBackupArchive.extract(archiveData)
check(
    archiveEntries.contains { $0.path == "documents/\(docID.uuidString).rtfd/TXT.rtf" },
    "备份保留完整 RTFD 文件包结构"
)
check(
    archiveEntries.contains {
        $0.path.hasPrefix("documents/\(docID.uuidString).rtfd/") && $0.data == attachmentPayload
    },
    "备份保留 RTFD 附件"
)
guard let body = restoredBodies[docID], let wrapper = body.rtfdFileWrapper else {
    fatalError("备份中缺少文档正文")
}
check(true, "备份包含文档正文")

// 还原到新目录并读回
let docDir2 = temp.appendingPathComponent("documents2")
try FileManager.default.createDirectory(at: docDir2, withIntermediateDirectories: true)
let fm2 = LibraryFileManager(documentsDirectory: docDir2)
try fm2.save(documentID: docID, rtfdFileWrapper: wrapper)
guard let restored = fm2.load(documentID: docID) else {
    fatalError("还原后无法读取正文")
}
check(restored.string.hasPrefix("春江花月夜"), "还原正文文本一致")
check(
    restored.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemBlue,
    "还原后文字颜色保留"
)
check(
    (restored.attribute(.underlineStyle, at: 3, effectiveRange: nil) as? Int) ?? 0 != 0,
    "还原后下划线保留"
)

print("结果: \(runs - failures)/\(runs) 通过, \(failures) 失败")
if failures > 0 {
    print("❌ 有失败断言")
    exit(1)
}
print("✅ 全部通过")
