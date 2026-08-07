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
        let archive = try LibraryBackupArchive.create(entries: entries)
        check(archive.count > 0, "ZIP 数据生成")

        // 自解包往返
        let extracted = try LibraryBackupArchive.extract(archive)
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

        // 带 local extra field 的归档：正文起点必须计入 extra 长度。
        let withExtra = try LibraryBackupArchive.create(entries: entries)
        check(
            LibraryBackupArchiveTestHelper.appendsLocalExtraField(to: withExtra, for: "documents/abc.rtf"),
            "外部工具写入 local extra field 后仍能读取正文"
        )

        // CRC 失配必须报错，而不是返回部分结果。
        let corrupted = LibraryBackupArchiveTestHelper.corruptPayload(of: archive, for: "docs/large.bin")
        do {
            _ = try LibraryBackupArchive.extract(corrupted)
            check(false, "CRC 失配必须抛出错误")
        } catch {
            check(true, "CRC 失配抛出错误：\(error)")
        }

        // 截断包必须报错。
        do {
            _ = try LibraryBackupArchive.extract(archive.prefix(archive.count - 3))
            check(false, "截断 ZIP 必须抛出错误")
        } catch {
            check(true, "截断 ZIP 抛出错误：\(error)")
        }

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

/// 测试辅助：在 local header 中插入 extra field、破坏条目 CRC，验证读取器健壮性。
enum LibraryBackupArchiveTestHelper {
    /// 在指定条目的 local header 中插入 4 字节 extra field，
    /// 并同步修正本地头长度、中央目录 local offset 与 EOCD 偏移。
    /// 验证读取器按 local extra length 计算正文起点（而不是按中央目录值）。
    static func appendsLocalExtraField(to archive: Data, for path: String) -> Bool {
        var bytes = [UInt8](archive)

        guard let eocd = findEOCD(in: bytes) else { return false }
        let oldCentralOffset = Int(read32(bytes, eocd + 16))

        guard let localStart = findLocalHeader(in: bytes, for: path) else { return false }
        let nameLength = Int(bytes[localStart + 26]) | (Int(bytes[localStart + 27]) << 8)
        let extraLength = Int(bytes[localStart + 28]) | (Int(bytes[localStart + 29]) << 8)
        let payloadStart = localStart + 30 + nameLength + extraLength

        let extra: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        bytes[localStart + 28] = 4
        bytes[localStart + 29] = 0
        bytes.insert(contentsOf: extra, at: payloadStart)

        // 插入点之后的中央目录与 EOCD 整体右移 4 字节。
        let eocdNew = eocd + 4
        var cursor = oldCentralOffset + 4
        while cursor + 46 <= eocdNew {
            guard read32(bytes, cursor) == 0x02014b50 else { break }
            let nameLen = Int(bytes[cursor + 28]) | (Int(bytes[cursor + 29]) << 8)
            let extraLen = Int(bytes[cursor + 30]) | (Int(bytes[cursor + 31]) << 8)
            let commentLen = Int(bytes[cursor + 32]) | (Int(bytes[cursor + 33]) << 8)
            let localOffset = Int(read32(bytes, cursor + 42))
            if localOffset >= payloadStart {
                write32(&bytes, cursor + 42, UInt32(localOffset + 4))
            }
            cursor += 46 + nameLen + extraLen + commentLen
        }
        write32(&bytes, eocdNew + 16, UInt32(oldCentralOffset + 4))

        let result = Data(bytes)
        return (try? LibraryBackupArchive.extract(result))?
            .first { $0.path == path }?.data == Data("桃花潭水深千尺，不及汪伦送我情。".utf8)
    }

    /// 翻转指定条目正文的一个字节，使 CRC 失配。
    static func corruptPayload(of archive: Data, for path: String) -> Data {
        flipPayloadByte(of: archive, for: path)
    }

    /// 直接在归档字节流中翻转指定条目正文的一个字节。
    static func flipPayloadByte(of archive: Data, for path: String) -> Data {
        var bytes = [UInt8](archive)
        var index = 0
        let target = Array(path.utf8)
        while index + 30 <= bytes.count {
            let signature = UInt32(bytes[index]) | (UInt32(bytes[index + 1]) << 8)
                | (UInt32(bytes[index + 2]) << 16) | (UInt32(bytes[index + 3]) << 24)
            guard signature == 0x04034b50 else { break }
            let nameLength = Int(bytes[index + 26]) | (Int(bytes[index + 27]) << 8)
            let extraLength = Int(bytes[index + 28]) | (Int(bytes[index + 29]) << 8)
            let nameStart = index + 30
            let nameEnd = nameStart + nameLength
            guard nameEnd <= bytes.count else { break }
            if Array(bytes[nameStart..<nameEnd]) == target {
                let dataStart = nameEnd + extraLength
                if dataStart < bytes.count {
                    bytes[dataStart] = bytes[dataStart] ^ 0xFF
                }
                return Data(bytes)
            }
            let dataLength = Int(bytes[index + 18]) | (Int(bytes[index + 19]) << 8)
                | (Int(bytes[index + 20]) << 16) | (Int(bytes[index + 21]) << 24)
            index = nameEnd + extraLength + dataLength
        }
        return archive
    }

    private static func findEOCD(in bytes: [UInt8]) -> Int? {
        let minimum = 22
        guard bytes.count >= minimum else { return nil }
        let start = max(0, bytes.count - 65535 - minimum)
        var index = bytes.count - minimum
        while index >= start {
            if read32(bytes, index) == 0x06054b50 { return index }
            index -= 1
        }
        return nil
    }

    private static func findLocalHeader(in bytes: [UInt8], for path: String) -> Int? {
        let target = Array(path.utf8)
        var index = 0
        while index + 30 <= bytes.count {
            guard read32(bytes, index) == 0x04034b50 else { return nil }
            let nameLength = Int(bytes[index + 26]) | (Int(bytes[index + 27]) << 8)
            let extraLength = Int(bytes[index + 28]) | (Int(bytes[index + 29]) << 8)
            let nameStart = index + 30
            let nameEnd = nameStart + nameLength
            guard nameEnd <= bytes.count else { return nil }
            if Array(bytes[nameStart..<nameEnd]) == target {
                return index
            }
            let dataLength = Int(read32(bytes, index + 18))
            index = nameEnd + extraLength + Int(dataLength)
        }
        return nil
    }

    private static func read32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func write32(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt32) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}
