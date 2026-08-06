import Foundation

@main
struct LibraryBackupArchiveTests {
    static func main() throws {
        var failures = 0

        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if condition() {
                print("  ✓ \(message)")
            } else {
                failures += 1
                print("  ✗ \(message)")
            }
        }

        let small = Data("桃花潭水深千尺，不及汪伦送我情。".utf8)
        let large = Data((0..<20000).map { UInt8($0 % 256) })

        let entries: [LibraryBackupArchive.Entry] = [
            .init(path: "manifest.json", data: Data(#"{"version":"2.5.0"}"#.utf8)),
            .init(path: "documents/abc.rtf", data: small),
            .init(path: "docs/large.bin", data: large),
            .init(path: "empty/", data: Data(), isDirectory: true),
        ]
        let archive = LibraryBackupArchive.create(entries: entries)
        check(archive.count > 0, "ZIP 数据生成")

        // 自解包往返
        let extracted = LibraryBackupArchive.extract(archive)
        check(extracted.count == 4, "解包条目数量正确（\(extracted.count)/4）")
        check(
            extracted.first(where: { $0.path == "manifest.json" })?.data == Data(#"{"version":"2.5.0"}"#.utf8),
            "manifest 内容往返一致"
        )
        check(
            extracted.first(where: { $0.path == "documents/abc.rtf" })?.data == small,
            "中文小文件往返一致"
        )
        check(
            extracted.first(where: { $0.path == "docs/large.bin" })?.data == large,
            "大文件往返一致"
        )
        check(
            extracted.contains { $0.path == "empty/" && $0.isDirectory },
            "目录条目保留"
        )

        // 系统工具兼容性
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TinyDeskZipTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let zipURL = tempDir.appendingPathComponent("backup.zip")
        try archive.write(to: zipURL)

        let extractDir = tempDir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipURL.path, extractDir.path]
        try ditto.run()
        ditto.waitUntilExit()
        check(ditto.terminationStatus == 0, "系统 ditto 可解压 ZIP")

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-l", zipURL.path]
        try unzip.run()
        unzip.waitUntilExit()
        check(unzip.terminationStatus == 0, "系统 unzip 可读取 ZIP")

        // CRC32 有效
        check(LibraryBackupArchive.crc32(of: small) != 0, "CRC32 计算有效")

        print(failures == 0
            ? "LibraryBackupArchiveTests: passed"
            : "LibraryBackupArchiveTests: \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
