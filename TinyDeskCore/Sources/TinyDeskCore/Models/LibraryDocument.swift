import Foundation

// MARK: - 纸张主题

/// 资料库文档的纸张背景主题。只影响本地阅读与 PDF 导出外观，
/// 不写入文档正文，因此不污染 RTFD 原始内容。
public enum PaperTheme: String, Codable, Sendable, CaseIterable {
    case suJian   // 素笺：米白素纸
    case xuanZhi  // 宣纸：微黄底，纤维纹理
    case zhuJian  // 竹简：浅棕底，竖条竹纹
    case moQing   // 墨青：青灰底，浅灰白字
    case zhuSha   // 朱砂：淡红底，深红褐字
    case yeMo     // 夜墨：深灰黑底，浅金字
    case meiYing  // 梅影笺：暖白底，朱梅点染
    case qingHua  // 青花笺：瓷白底，青花纹样
    case lanTing  // 兰亭笺：宣纸底，远山水墨
    case dunHuang // 敦煌笺：沙金底，藻井纹样
    case songYan  // 松烟笺：墨绿底，松针暗纹
    case yunJin   // 云锦笺：绛红底，如意云纹

    public var displayName: String {
        switch self {
        case .suJian: return "素笺"
        case .xuanZhi: return "宣纸"
        case .zhuJian: return "竹简"
        case .moQing: return "墨青"
        case .zhuSha: return "朱砂"
        case .yeMo: return "夜墨"
        case .meiYing: return "梅影笺"
        case .qingHua: return "青花笺"
        case .lanTing: return "兰亭笺"
        case .dunHuang: return "敦煌笺"
        case .songYan: return "松烟笺"
        case .yunJin: return "云锦笺"
        }
    }

    public var materialDescription: String {
        switch self {
        case .suJian: return "温润素纸"
        case .xuanZhi: return "纤维宣纸"
        case .zhuJian: return "竹纹简牍"
        case .moQing: return "青墨月色"
        case .zhuSha: return "朱砂印色"
        case .yeMo: return "暗金夜色"
        case .meiYing: return "疏梅点染"
        case .qingHua: return "青花瓷韵"
        case .lanTing: return "远山水墨"
        case .dunHuang: return "藻井飞彩"
        case .songYan: return "苍松烟墨"
        case .yunJin: return "绛云织锦"
        }
    }
}

// MARK: - 字体预设

/// 资料库文档的中文字体预设。英文始终使用 Apple 系统字体。
public enum FontPreset: String, Codable, Sendable, CaseIterable {
    case fangSong  // 仿宋优先
    case songTi    // 宋体
    case system    // 系统默认

    public var displayName: String {
        switch self {
        case .fangSong: return "仿宋"
        case .songTi: return "宋体"
        case .system: return "系统默认"
        }
    }
}

// MARK: - 目录

/// 资料库目录树中的目录节点。
public struct LibraryCategory: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var sortOrder: Int
    public var iconName: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int = 0,
        iconName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.iconName = iconName
        self.createdAt = createdAt
    }
}

// MARK: - 标签

/// 资料库标签，可多选。
public struct LibraryTag: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    /// #RRGGBB 十六进制颜色。
    public var colorHex: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#808080",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

// MARK: - 文档

/// 资料库文档元数据。正文保存在独立的 RTFD 文件中，这里只记录索引所需字段。
public struct LibraryDocument: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    /// 所属目录；nil 表示未分类。
    public var categoryID: UUID?
    public var tagIDs: [UUID]
    public var isFavorited: Bool
    public var paperTheme: PaperTheme
    public var fontPreset: FontPreset
    /// 字数缓存，保存时更新。
    public var wordCount: Int
    /// 纯文本摘要（前 120 字）。
    public var summary: String
    /// 可选自定义封面色（#RRGGBB）。
    public var customCoverColorHex: String?
    public let createdAt: Date
    public var updatedAt: Date
    /// 软删除标记；nil 表示正常，非 nil 表示在回收站中。
    public var deletedAt: Date?
    /// 最近一次打开时间；“最近打开”视图按此排序，缺失时兼容旧数据。
    public var lastOpenedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        categoryID: UUID? = nil,
        tagIDs: [UUID] = [],
        isFavorited: Bool = false,
        paperTheme: PaperTheme = .suJian,
        fontPreset: FontPreset = .fangSong,
        wordCount: Int = 0,
        summary: String = "",
        customCoverColorHex: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.categoryID = categoryID
        self.tagIDs = tagIDs
        self.isFavorited = isFavorited
        self.paperTheme = paperTheme
        self.fontPreset = fontPreset
        self.wordCount = wordCount
        self.summary = summary
        self.customCoverColorHex = customCoverColorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastOpenedAt = lastOpenedAt
    }

    /// 是否为回收站中的文档。
    public var isTrashed: Bool { deletedAt != nil }

    /// 汇总文本，用于生成摘要与索引。
    public var indexableText: String {
        [title, summary].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, categoryID, tagIDs, isFavorited, paperTheme, fontPreset
        case wordCount, summary, customCoverColorHex, createdAt, updatedAt, deletedAt, lastOpenedAt
    }

    /// 自定义解码：`lastOpenedAt` 等新字段缺失时保持旧版备份可读。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        categoryID = try container.decodeIfPresent(UUID.self, forKey: .categoryID)
        tagIDs = try container.decodeIfPresent([UUID].self, forKey: .tagIDs) ?? []
        isFavorited = try container.decodeIfPresent(Bool.self, forKey: .isFavorited) ?? false
        paperTheme = try container.decodeIfPresent(PaperTheme.self, forKey: .paperTheme) ?? .suJian
        fontPreset = try container.decodeIfPresent(FontPreset.self, forKey: .fontPreset) ?? .fangSong
        wordCount = try container.decodeIfPresent(Int.self, forKey: .wordCount) ?? 0
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        customCoverColorHex = try container.decodeIfPresent(String.self, forKey: .customCoverColorHex)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
    }
}

/// 资料库备份恢复时，将源资料库的目录、标签引用映射到本机新建的实体。
/// 恢复操作不能复用源 UUID，否则与现有资料库发生主键冲突时会破坏关系。
public enum LibraryRestoreReferenceMapping {
    public static func remap(
        categoryID: UUID?,
        tagIDs: [UUID],
        categoryIDs: [UUID: UUID],
        tagIDsBySourceID: [UUID: UUID]
    ) -> (categoryID: UUID?, tagIDs: [UUID]) {
        (
            categoryID: categoryID.flatMap { categoryIDs[$0] },
            tagIDs: tagIDs.compactMap { tagIDsBySourceID[$0] }
        )
    }
}

// MARK: - 全文搜索结果

/// 全文搜索的一条结果。
public struct LibrarySearchResult: Identifiable, Sendable, Equatable {
    public let documentID: UUID
    public let title: String
    /// FTS5 snippet() 生成的高亮片段。
    public let snippet: String
    public let categoryID: UUID?
    public let tagIDs: [UUID]
    public let updatedAt: Date
    /// bm25() 相关度，越低越相关。
    public var rank: Double

    public var id: UUID { documentID }

    public init(
        documentID: UUID,
        title: String,
        snippet: String,
        categoryID: UUID?,
        tagIDs: [UUID],
        updatedAt: Date,
        rank: Double
    ) {
        self.documentID = documentID
        self.title = title
        self.snippet = snippet
        self.categoryID = categoryID
        self.tagIDs = tagIDs
        self.updatedAt = updatedAt
        self.rank = rank
    }
}
