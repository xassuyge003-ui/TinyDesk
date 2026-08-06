# 工程结构

## 技术路线

TinyDesk 是一个单 target 的 macOS 菜单栏应用。可编辑能力由 AppKit `NSPanel` 提供，
内容由 SwiftUI 渲染。桌面卡片不运行在独立进程，因此不需要 App Group，也不受系统
小组件禁止任意文本输入的限制。

```text
菜单栏 / 控制中心 / 桌面卡片（SwiftUI）
                 │
       DesktopWindowManager（AppKit）
                 │
       DesktopWorkspaceStore（JSON）
                 │
       TinyDeskCore（纯 Foundation）
```

v2.5 增加资料库子系统，与桌面卡片系统并行、存储隔离：

```text
资料库窗口（三栏 SwiftUI）
         │
       LibraryStore（@MainActor ObservableObject）
         │            ├── LibraryFileManager（RTFD 文件包）
         │            └── FTSIndexer（SQLite FTS5）
         │
       TinyDeskCore（模型 + SQLite 封装）
```

## 目录

```text
TinyDesk/
├── Targets/TinyDesk/
│   ├── Sources/
│   │   ├── TinyDeskApp.swift              # Scene、菜单栏、应用命令
│   │   ├── ControlCenterView.swift         # 新建与管理卡片
│   │   ├── DesktopCardView.swift           # 三类响应式卡片 UI
│   │   ├── RichTextEditor.swift             # NSTextView 富文本编辑与格式控制
│   │   ├── DesktopWindowManager.swift      # NSPanel 生命周期和桌面层级
│   │   ├── DesktopWorkspaceStore.swift     # 本地 JSON 持久化
│   │   ├── SystemCalendarService.swift      # EventKit 导入、关联和同步
│   │   ├── TinyDeskSettings.swift           # 开机启动与偏好设置
│   │   ├── GlobalShortcut.swift             # 原生全局快捷键与录制控件
│   │   ├── ImportantDateNotificationScheduler.swift # 本地通知同步
│   │   ├── LibraryWindowView.swift          # 资料库三栏窗口与工具栏
│   │   ├── LibrarySidebarView.swift         # 目录/标签/收藏/最近/回收站
│   │   ├── LibraryDocumentListView.swift    # 中间文档列表
│   │   ├── LibraryEditorView.swift          # 纸张背景长文档编辑器
│   │   ├── LibraryStore.swift               # 资料库主 Store
│   │   ├── LibraryFileManager.swift         # RTFD 文件包读写
│   │   ├── LibraryBackupArchive.swift       # 最小 ZIP 归档（stored）
│   │   ├── LibraryBackup.swift              # 备份包打包/恢复
│   │   ├── LibraryImportExport.swift        # RTF/RTFD/TXT/Markdown 导入导出
│   │   ├── LibraryPDFRenderer.swift         # NSPrintOperation PDF 导出
│   │   └── PaperTheme.swift                 # 十二套国风花笺与自适应文字对比度
│   └── SupportingFiles/                    # Info.plist 与沙盒权限
├── TinyDeskCore/
│   └── Sources/
│       ├── TinyDeskCore/Models/DesktopCard.swift
│       ├── TinyDeskCore/Models/LibraryDocument.swift
│       ├── TinyDeskCore/Models/ChineseLunarCalendar.swift
│       ├── TinyDeskCore/Storage/FTSIndexer.swift
│       └── TinyDeskSelfTests/main.swift
├── project.yml                              # XcodeGen 单一事实来源
└── TinyDesk.xcodeproj                       # 由 project.yml 生成
```

## 窗口策略

- 卡片窗口层级为桌面图标层级加一，确保 Finder 不会截获点击；它仍低于普通应用窗口。
- 卡片可以成为 key window，因此 `TextField`、`TextEditor`、`DatePicker` 可直接操作。
- SwiftUI 根视图忽略透明标题栏安全区，窗口 frame 贴近菜单栏时不会再产生额外的视觉顶部偏移。
- 根 `NSHostingView` 接受 first mouse；直接点击后台卡片时会激活应用并把本次点击交给编辑控件。
- 取得编辑焦点或从控制中心定位时始终保持桌面层级，不会升到普通应用窗口上方。
- 窗口加入所有 Space，并记录 frame 与屏幕标识；显示器变化时自动夹回可见区域。
- 卡片提供 280×280、440×220、440×440 三种预设比例，同时保留边缘自由缩放；内容根据宽高切换紧凑布局。
- 背景风格与颜色按卡片持久化；旧版 JSON 没有 `surfaceStyle` 时回退为毛玻璃。
- 便签同时保存 `noteText` 纯文本和可选的 `noteRichTextData` RTF 数据；旧工作区缺少 RTF 时直接以纯文本创建富文本内容。
- 待办完成项按视图稳定分组到末尾，不改写原始数组顺序；无计划日期的旧事项以创建日期计算跨日状态。
- 重要日期卡片在小/中尺寸使用紧凑日历，在大尺寸展示选中日期事件；也可切换为按下一次日期排序的列表。
- 重要日期使用专属紧凑顶栏；通用外观和尺寸操作收进设置菜单，避免小尺寸横向拥挤。
- `isPositionLocked` 按卡片持久化；锁定时同时关闭 `NSWindow.isMovable`、背景拖动和自定义拖动柄。
- 快速便签在鼠标所在屏幕的顶部中央创建；默认置顶为 floating 层，用户可关闭置顶以恢复桌面层，状态随工作区保存。

## 数据策略

`DesktopWorkspaceStore` 在主 actor 上维护 `TinyDeskWorkspace`，变更后合并写入：

```text
~/Library/Containers/com.kai.tinydesk/Data/Library/Application Support/TinyDesk/workspace.json
```

写入使用原子替换。无法解码的工作区会先改名为带时间戳的 `corrupt` 备份，再创建默认工作区。
当前 schema 版本为 3。schema 1 中每张旧倒数日会迁移为一个一次性 `ImportantDateEvent`，卡片位置、外观、标题和目标日期保持不变；schema 3 为每张卡片补充可选的 `isAlwaysOnTop`，旧卡片默认维持桌面层。

重要日期存为工作区级事件库，多个日期卡片共享同一数据源。农历日期的换算由 Foundation 的中国历在核心层完成。`SystemCalendarLink` 为可选记录：系统来源读取并刷新系统日历事件，本地来源可写回用户选择的可写日历。为维持 TinyDesk 的“一次性/每年”模型，系统日历导入仅接受这两种重复规则，周/月等规则不会被错误转换。提醒由 `UNUserNotificationCenter` 在本机调度，不需要 App Group、推送证书或付费开发者能力；仅在用户为某条记录启用提醒时请求系统权限。

### 资料库（v2.5）

资料库是独立于桌面卡片的子系统，元数据与全文索引存于 SQLite，正文存于 RTFD 文件包：

```text
~/Library/Containers/com.kai.tinydesk/Data/Library/Application Support/TinyDesk/
├── workspace.json          # v2.0 工作区（不变）
└── Library/                # v2.5 新增
    ├── library.db          # SQLite：documents/tags/categories/document_tags + FTS5
    └── documents/          # <uuid>.rtfd 文件包（TXT.rtf + 图片附件）
```

- **存储隔离**：`LibraryStore` 只读写 `Library/library.db` 与 `Library/documents/`，与 `workspace.json` 完全分离，保证 v2.0 数据零回归。
- **全文搜索**：SQLite FTS5，索引标题、正文、标签名与目录名。由于 `unicode61` 分词器不切分中文，`FTSIndexer.segmentedForFTS` 在写入与查询时把 CJK 连续文本切分为单字（空格分隔），使中文可按单字命中；查询词也做同样切分并用双引号包裹走短语匹配。
- **RTFD 文件包**：正文通过 `NSAttributedString.fileWrapper` 保存为 `.rtfd` 目录（内含 `TXT.rtf` 与图片），读取用 `init(rtfdFileWrapper:)`，保证粗体、斜体、颜色、下划线、图片完整往返。
- **备份 ZIP**：`LibraryBackupArchive` 用原生代码生成标准 ZIP（stored 方法 0），不依赖外部 `zip` 命令，兼容 Finder/ditto/unzip。备份包含 `manifest.json`、`library.json`（全量元数据）与 `documents/<id>.rtf`（正文）。
- **回收站**：删除文档写入 `deleted_at` 软删除，保留 90 天；启动时自动清理过期条目。
- **桌面摘要卡片**：`kind == .deskRef` 的卡片只读展示文档标题、摘要与标签，双击经通知打开资料库对应文档；不在卡片内编辑长文档。

## 分层约束

- `TinyDeskCore` 只能依赖 Foundation，不得导入 SwiftUI 或 AppKit。（`FTSIndexer` 封装 SQLite C 接口，仍属系统框架调用。）
- 平台窗口与持久化实现留在主应用 target。
- 卡片内容不发起网络请求；项目默认零网络权限。
- `project.yml` 是工程配置源，修改 target 或源文件后需重新生成 `.xcodeproj`。
