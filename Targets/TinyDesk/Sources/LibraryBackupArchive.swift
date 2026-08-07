import Foundation

/// 资料库备份 ZIP 包的最小实现。
///
/// 在 App Sandbox 中不能保证可以调用外部 `zip` 命令，因此这里用原生代码
/// 直接生成标准 ZIP 归档（local headers + central directory）。
/// 条目使用 stored（方法 0）存储，以保证与 Finder、Archive Utility、ditto、
/// unzip 的完全兼容；系统 `libcompression` 的 COMPRESSION_ZLIB 输出是 zlib
/// 封装而非 ZIP 期望的裸 deflate 流，因此这里不做 deflate，换取通用可读性。
/// 资料库文档为 RTF 文本，体积可控，stored 不会带来明显膨胀。
enum LibraryBackupArchive {
    struct Entry {
        let path: String
        let data: Data
        let isDirectory: Bool

        init(path: String, data: Data, isDirectory: Bool = false) {
            self.path = path
            self.data = data
            self.isDirectory = isDirectory
        }
    }

    // MARK: - 写入

    static func create(entries: [Entry]) throws -> Data {
        guard entries.count <= UInt16.max else {
            throw LibraryBackupArchiveError.entryCountOverflow
        }
        var output = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        let fixedDate = dosDateTime()

        for entry in entries {
            let name = Array(entry.path.utf8)
            let fileData = entry.isDirectory ? Data() : entry.data
            guard name.count <= UInt16.max else {
                throw LibraryBackupArchiveError.nameTooLong(entry.path)
            }
            guard fileData.count <= UInt32.max, name.count <= UInt32.max else {
                throw LibraryBackupArchiveError.dataTooLarge(entry.path)
            }
            let crc = crc32(of: entry.data)

            var local = Data()
            local.appendUInt32(0x04034b50)
            local.appendUInt16(entry.isDirectory ? 20 : 10)   // version needed
            local.appendUInt16(0x0800)                        // UTF-8 filename flag
            local.appendUInt16(0)                             // method: stored
            local.appendUInt16(fixedDate.time)
            local.appendUInt16(fixedDate.date)
            local.appendUInt32(crc)
            local.appendUInt32(UInt32(fileData.count))
            local.appendUInt32(UInt32(entry.data.count))
            local.appendUInt16(UInt16(name.count))
            local.appendUInt16(0)                             // extra length
            local.append(contentsOf: name)
            local.append(fileData)
            output.append(local)

            var central = Data()
            central.appendUInt32(0x02014b50)
            central.appendUInt16(20)                          // version made by
            central.appendUInt16(entry.isDirectory ? 20 : 10) // version needed
            central.appendUInt16(0x0800)
            central.appendUInt16(0)
            central.appendUInt16(fixedDate.time)
            central.appendUInt16(fixedDate.date)
            central.appendUInt32(crc)
            central.appendUInt32(UInt32(fileData.count))
            central.appendUInt32(UInt32(entry.data.count))
            central.appendUInt16(UInt16(name.count))
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(entry.isDirectory ? 0x10 : 0) // external attrs: dir bit
            central.appendUInt32(offset)
            central.append(contentsOf: name)
            centralDirectory.append(central)

            offset += UInt32(local.count)
        }

        var end = Data()
        end.appendUInt32(0x06054b50)
        end.appendUInt16(0)
        end.appendUInt16(0)
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt32(UInt32(centralDirectory.count))
        end.appendUInt32(offset)
        end.appendUInt16(0)

        output.append(centralDirectory)
        output.append(end)
        return output
    }

    // MARK: - 读取

    static func extract(_ data: Data) throws -> [Entry] {
        guard let end = locateEndOfCentralDirectory(in: data) else {
            throw LibraryBackupArchiveError.eocdNotFound
        }
        let recordCount = Int(end.readUInt16(at: 10))
        var cursor = Int(end.readUInt32(at: 16))
        var entries: [Entry] = []

        for _ in 0..<recordCount {
            guard cursor + 46 <= data.count,
                  data.readUInt32(at: cursor) == 0x02014b50
            else {
                throw LibraryBackupArchiveError.invalidCentralDirectory
            }

            let flags = data.readUInt16(at: cursor + 8)
            let method = data.readUInt16(at: cursor + 10)
            let compressedSize = Int(data.readUInt32(at: cursor + 20))
            let uncompressedSize = Int(data.readUInt32(at: cursor + 24))
            let nameLength = Int(data.readUInt16(at: cursor + 28))
            let extraLength = Int(data.readUInt16(at: cursor + 30))
            let commentLength = Int(data.readUInt16(at: cursor + 32))
            let crcCentral = data.readUInt32(at: cursor + 16)
            let localOffset = Int(data.readUInt32(at: cursor + 42))

            if flags & 0x1 != 0 {
                throw LibraryBackupArchiveError.encryptedUnsupported
            }
            if compressedSize == 0xFFFFFFFF || uncompressedSize == 0xFFFFFFFF || localOffset == 0xFFFFFFFF {
                throw LibraryBackupArchiveError.zip64Unsupported
            }

            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count else {
                throw LibraryBackupArchiveError.truncated
            }
            let name = String(decoding: data[nameStart..<nameEnd], as: UTF8.self)
            let isDirectory = name.hasSuffix("/")

            guard let fileData = try readFileData(
                in: data,
                localOffset: localOffset,
                flags: flags,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize
            ) else {
                throw LibraryBackupArchiveError.truncated
            }

            let calculated = crc32(of: fileData)
            guard calculated == crcCentral else {
                throw LibraryBackupArchiveError.crcMismatch(path: name)
            }

            entries.append(Entry(path: name, data: fileData, isDirectory: isDirectory))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func readFileData(
        in data: Data,
        localOffset: Int,
        flags: UInt16,
        method: UInt16,
        compressedSize: Int,
        uncompressedSize: Int
    ) throws -> Data? {
        guard localOffset + 30 <= data.count else { return nil }
        guard data.readUInt32(at: localOffset) == 0x04034b50 else {
            throw LibraryBackupArchiveError.invalidLocalHeader
        }
        let localFlags = data.readUInt16(at: localOffset + 6)
        if localFlags & 0x1 != 0 {
            throw LibraryBackupArchiveError.encryptedUnsupported
        }
        // data descriptor 位（bit 3）不影响正文起点：正文偏移只依赖文件名与 extra field。
        _ = flags
        let localNameLength = Int(data.readUInt16(at: localOffset + 26))
        let localExtraLength = Int(data.readUInt16(at: localOffset + 28))
        let fileStart = localOffset + 30 + localNameLength + localExtraLength
        guard fileStart + compressedSize <= data.count else { return nil }

        switch method {
        case 0:
            guard compressedSize == uncompressedSize else {
                throw LibraryBackupArchiveError.crcMismatch(path: "")
            }
            return data.subdata(in: fileStart..<(fileStart + compressedSize))
        default:
            throw LibraryBackupArchiveError.unsupportedMethod(method)
        }
    }

    private static func locateEndOfCentralDirectory(in data: Data) -> Data? {
        let minimum = 22
        guard data.count >= minimum else { return nil }
        // EOCD 前可携带最多 65535 字节注释，扫描窗口要覆盖完整范围。
        let windowSize = min(65535 + minimum, data.count)
        let window = Data(data.suffix(windowSize))
        for index in stride(from: window.count - minimum, through: 0, by: -1) {
            if window.readUInt32(at: index) == 0x06054b50 {
                return window.subdata(in: index..<window.count)
            }
        }
        return nil
    }

    // MARK: - CRC32

    private static var crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : (c >> 1)
            }
            table[n] = c
        }
        return table
    }()

    static func crc32(of data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: - DOS 时间（用固定基准避免 Date 依赖不稳定）

    private struct DOSDateTime {
        let time: UInt16
        let date: UInt16
    }

    private static func dosDateTime() -> DOSDateTime {
        // 使用应用启动时间（macOS 14 起可用），否则固定为 2026-01-01。
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        components.hour = 0
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_767_225_600)
        let cal = Calendar.current
        let year = max(1980, cal.component(.year, from: date)) - 1980
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let second = min(59, cal.component(.second, from: date) / 2)
        return DOSDateTime(
            time: UInt16((hour << 11) | (minute << 5) | second),
            date: UInt16((year << 9) | (month << 5) | day)
        )
    }
}

// MARK: - Data 小端读取

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[startIndex.advanced(by: offset)]) |
            (UInt16(self[startIndex.advanced(by: offset + 1)]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[startIndex.advanced(by: offset)]) |
            (UInt32(self[startIndex.advanced(by: offset + 1)]) << 8) |
            (UInt32(self[startIndex.advanced(by: offset + 2)]) << 16) |
            (UInt32(self[startIndex.advanced(by: offset + 3)]) << 24)
    }
}

/// ZIP 归档读写错误。
enum LibraryBackupArchiveError: LocalizedError {
    case eocdNotFound
    case invalidCentralDirectory
    case invalidLocalHeader
    case truncated
    case crcMismatch(path: String)
    case unsupportedMethod(UInt16)
    case encryptedUnsupported
    case zip64Unsupported
    case entryCountOverflow
    case nameTooLong(String)
    case dataTooLarge(String)

    var errorDescription: String? {
        switch self {
        case .eocdNotFound: return "备份包缺少 ZIP 结束标记。"
        case .invalidCentralDirectory: return "备份包中央目录损坏。"
        case .invalidLocalHeader: return "备份包文件头损坏。"
        case .truncated: return "备份包内容被截断。"
        case let .crcMismatch(path): return "备份包校验失败（\(path.isEmpty ? "未知文件" : path)）。"
        case let .unsupportedMethod(method): return "备份包使用了不支持的压缩方式（\(method)）。"
        case .encryptedUnsupported: return "备份包包含加密条目，无法读取。"
        case .zip64Unsupported: return "备份包使用 ZIP64 扩展，当前版本无法读取。"
        case .entryCountOverflow: return "备份包条目过多，无法生成。"
        case let .nameTooLong(path): return "备份条目文件名过长（\(path)）。"
        case let .dataTooLarge(path): return "备份条目数据过大（\(path)）。"
        }
    }
}
