# TinyDesk

> 轻量、免费、本地优先的 macOS 桌面卡片：直接在桌面编辑便签、重要日期与待办。

[![CI](https://github.com/xassuyge003-ui/TinyDesk/actions/workflows/ci.yml/badge.svg)](https://github.com/xassuyge003-ui/TinyDesk/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

[English](./README_EN.md) · [更新记录](./CHANGELOG.md) · [贡献指南](./CONTRIBUTING.md)

TinyDesk 使用 SwiftUI 渲染内容、AppKit `NSPanel` 承载桌面窗口。它不是 WidgetKit
系统小组件，因此可以在桌面直接输入文字、勾选待办和编辑日期，也不需要 App Group、
iCloud 或付费 Apple Developer Program。

卡片位于桌面图标上方、普通应用窗口下方：点击卡片可以操作，但不会持续遮挡其他应用。
内容、外观、尺寸和位置会自动写入应用沙盒。

## 功能

| 模块 | 当前能力 |
|---|---|
| 便签 | 多卡片、标题和正文直接编辑、文字颜色、粗体、斜体、下划线、删除线、自动保存 |
| 重要日期 | 日历/列表视图、农历生日与闰月规则、系统日历导入/关联、一次性或每年重复、年龄与周年、本地通知 |
| 待办 | 新增与编辑、完成删除线、完成项自动下移、全部/未完成/已完成筛选、昨日未完成和逾期提示 |
| 外观 | 石墨、暖沙、薄荷、玫瑰、海洋五种颜色；毛玻璃、透明、不透明三种背景 |
| 布局 | 小号方形、中号横向、大号方形预设，也可拖动边缘自由缩放 |
| 桌面体验 | 跨 Space、显示/隐藏、恢复默认位置、卡片位置锁定、开机自启、全局快捷键快速便签 |
| 资料库 | 长文档整理：目录树、标签、收藏、最近打开、回收站、全文搜索、富文本编辑、十二套国风花笺主题 |
| 导入导出 | 资料库支持 RTF/RTFD/TXT/Markdown 导入，RTF/RTFD/TXT/Markdown/PDF 导出与 ZIP 备份包 |
| 隐私 | App Sandbox、本地 JSON + SQLite、无账号、无遥测、无网络请求 |

## 当前状态

- 当前版本：`2.5.0`
- 最低系统：macOS 14
- 发布阶段：可用的早期版本，数据格式带版本号并包含旧版迁移
- 自动验证：76 项核心模型与持久化自检 + ZIP/RTFD 附件备份往返测试；GitHub Actions 在每个与应用版本一致的标签构建通用 DMG
- 已覆盖的关键流程：直接编辑、窗口层级、尺寸预设、外观切换、锁定、待办筛选、重要日期双视图与农历换算

内存和数据大小会随系统版本、卡片数量及富文本内容变化；工作区始终仅保存在本机沙盒中。

## 系统要求

- macOS 14 Sonoma 或更高版本
- Xcode 15 或更高版本
- Swift 5.9 或更高版本
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

仓库不提交自动生成的 `.xcodeproj`，`project.yml` 是工程配置的单一事实来源。

## 从源码运行

```bash
git clone https://github.com/xassuyge003-ui/TinyDesk.git
cd TinyDesk

# 已安装 Homebrew 时
brew install xcodegen

xcodegen generate
open TinyDesk.xcodeproj
```

然后在 Xcode 中：

1. 选择 `TinyDesk` scheme 和 `My Mac`。
2. 打开 Target 的 **Signing & Capabilities**。
3. 选择自己的 Personal Team；如 Bundle ID 冲突，可在 `project.yml` 中改为自己的标识并重新运行 `xcodegen generate`。
4. 按 `⌘R` 运行。

个人免费 Apple ID 足以在自己的 Mac 上构建和运行。本项目不依赖付费能力。

## 安装 DMG

每个与 `Info.plist` 版本一致的标签都会在 [GitHub Releases](https://github.com/xassuyge003-ui/TinyDesk/releases) 发布通用
`TinyDesk-x.y.z.dmg`，同时提供 SHA-256 校验文件。下载后：

### 版本下载

| 版本 | 适合用途 | 下载 |
|---|---|---|
| V2.5.0 | 最新版：桌面卡片 + 长文档资料库、全文搜索、导入导出和国风花笺 | [发布说明与 DMG](https://github.com/xassuyge003-ui/TinyDesk/releases/tag/v2.5.0) |
| V2.0.0 | 农历生日、系统日历、开机自启和快捷便签 | [发布说明](https://github.com/xassuyge003-ui/TinyDesk/releases/tag/v2.0.0) · [直接下载 DMG](https://github.com/xassuyge003-ui/TinyDesk/releases/download/v2.0.0/TinyDesk-2.0.0.dmg) |
| V1.1.1 | 富文本便签稳定版 | [发布说明](https://github.com/xassuyge003-ui/TinyDesk/releases/tag/v1.1.1) · [直接下载 ZIP](https://github.com/xassuyge003-ui/TinyDesk/releases/download/v1.1.1/TinyDesk-v1.1.1-macOS-universal.zip) |
| V1.0.0 | 首个公开基础版本 | [发布说明](https://github.com/xassuyge003-ui/TinyDesk/releases/tag/v1.0.0) · [直接下载 ZIP](https://github.com/xassuyge003-ui/TinyDesk/releases/download/v1.0.0/TinyDesk-v1.0.0-macOS-universal.zip) |

旧版 Release、安装包、源码快照和原发布说明均长期保留，不会被新版覆盖。跨版本降级前请先备份本地数据。

1. 双击 DMG，将 `TinyDesk.app` 拖入“应用程序”。
2. 首次打开时，按住 Control 点击 `TinyDesk.app` 并选择“打开”，再在系统提示中确认。
3. 这是免费、ad-hoc 签名的安装包，不含 Developer ID 公证；系统不信任提示属于该签名边界，不会上传任何卡片数据。

若想自行验证或构建安装包：

```bash
./scripts/build-dmg.sh
```

构建产物会写入 `dist/`，脚本会生成通用二进制、验证架构与签名，并输出 SHA-256 文件。

### 命令行验证

```bash
cd TinyDeskCore
swift run TinyDeskSelfTests
cd ..

xcodegen generate
xcodebuild \
  -project TinyDesk.xcodeproj \
  -scheme TinyDesk \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 使用方法

### 创建和管理卡片

首次启动会创建便签、重要日期和待办各一张，并打开控制中心。关闭控制中心后，TinyDesk
仍驻留在菜单栏；点击菜单栏图标可以：

- 新建便签、重要日期或待办卡片；
- 定位、显示或隐藏已有卡片；
- 修改尺寸、背景和颜色；
- 锁定位置、恢复默认位置或删除卡片；
- 一次显示或隐藏全部卡片。

### 桌面操作

- 便签和待办可以直接点击文字区域编辑。
- 便签中选中文字后，可用正文上方工具栏设置颜色、粗体、斜体、下划线和删除线，也可清除格式。
- 未锁定卡片可拖动标题区域移动，也可拖动边缘自由缩放。
- 重要日期顶部左侧提供日历/列表切换、分类筛选和新增按钮。
- 点击锁图标，或在卡片/控制中心菜单选择“锁定位置”，可以防止误拖；锁定不影响编辑和缩放。
- 卡片获得编辑焦点后仍停留在普通应用窗口下方。
- 从菜单栏选择“快速便签”，或按设置的全局快捷键（默认 `⌥⌘N`），会在当前屏幕顶部中央创建新便签。可在卡片标题栏取消置顶；普通卡片仍保持桌面层，不遮挡应用。
- 控制中心右上角“设置”可打开“开机时启动”和快捷键设置；两项只写入本机设置。

### 重要日期与提醒

重要日期支持一次性事件和每年重复事件。生日或纪念日填写起始年份后，会显示年龄或周年数。
可切换公历或农历：选择闰月生日时，默认会在没有对应闰月的年份按同名普通月补过；也可以选“仅闰月”
而在没有闰月时不显示。提醒可设置为当天或提前 1、3、7 天，并选择提醒时间。首次启用提醒时，macOS
会请求 TinyDesk 的通知权限；若拒绝，可稍后在 **系统设置 → 通知 → TinyDesk** 中修改。

在重要日期卡片中点按日历图标可打开“系统日历”：先由用户授予日历权限，再选择要导入的日历。导入的
记录以系统日历为标题、日期和重复规则的来源；TinyDesk 仍可单独保存分类、置顶和本地提醒。也可以将
本地重要日期导出到一个可写日历，之后由 TinyDesk 写回同步。解除关联只停止同步，不会删除任一侧记录。
为避免语义被悄悄改变，导入仅接受一次性和每年重复的系统事件；周、月等重复规则由“日历”应用继续管理。

### 待办规则

- 勾选完成后显示删除线，并移动到当前列表底部。
- 可筛选全部、未完成和已完成事项。
- 昨日计划但未完成的事项显示“昨日未完成”，更早的事项显示逾期天数。
- 事项支持优先级和计划日期。

### 资料库

从控制中心或菜单栏的“打开资料库”进入。资料库是三栏长文档管理器：

- **左侧**：目录树、标签、收藏、最近打开、回收站。
- **中间**：当前筛选下的文档列表，显示标题、摘要、标签与更新时间。
- **右侧**：纸张背景上的长文档编辑器，支持粗体、斜体、下划线、删除线、颜色、字号、中文字体预设（仿宋/宋体/系统）；字体入口会直接显示当前字体，并使用与花笺一致的色彩和中文排版。

操作：

- `⌘N` 新建文档，`⌘⇧O` 导入，`⌘⇧E` 导出，`⌘F` 聚焦全文搜索框。
- 标题栏的“花笺材料”入口可切换十二套主题：素笺、宣纸、竹简、墨青、朱砂、夜墨、梅影笺、青花笺、兰亭笺、敦煌笺、松烟笺、云锦笺。切换后，左侧资料导航、中部文档列表、右侧编辑器和格式工具栏会作为一个完整界面同步换肤。
- 所有主题均采用无横线纸面；正文会根据纸张底色临时增强低对比度文字，原始富文本颜色与格式不会被改写，PDF 导出采用相同可读性规则。
- 文档列表右键可将文档“添加到桌面”，创建只读摘要卡片；双击摘要卡片回到资料库对应文档。
- 回收站文档保留 90 天后自动清理；也可手动恢复或永久删除。
- “导出资料库备份”生成 ZIP 备份包，“恢复资料库备份”可完整还原全部目录、标签、文档与 RTFD 附件；旧版备份包也可继续恢复。

资料库的快速记录、资料整理与花笺语义调研参考了 MIT 许可的 [Achilng/floral-notepaper](https://github.com/Achilng/floral-notepaper)。TinyDesk 使用原生 Swift/AppKit 独立实现，不引入 Tauri/React 运行时，也未复制其图片素材。

## 数据与隐私

TinyDesk 不包含账号、分析 SDK、广告、云同步或联网内容。便签纯文本和富文本格式、重要日期、
待办及窗口布局写入：

```text
~/Library/Containers/com.kai.tinydesk/Data/Library/Application Support/TinyDesk/workspace.json
```

资料库元数据与全文索引写入：

```text
~/Library/Containers/com.kai.tinydesk/Data/Library/Application Support/TinyDesk/Library/library.db
~/Library/Containers/com.kai.tinydesk/Data/Library/Application Support/TinyDesk/Library/documents/
```

资料库与 `workspace.json` 完全隔离，互不影响。控制中心底部可以直接在 Finder 中定位工作区目录。
写入采用原子替换；如果工作区无法解析，程序会先保存带时间戳的损坏文件备份，再创建默认工作区。
卸载应用或清理容器前，请先备份 `workspace.json` 与资料库备份包。

本地通知由 `UNUserNotificationCenter` 调度，日期内容不会发送给第三方。日历访问仅在用户主动导入、
关联或同步时请求，并且只通过本机 EventKit 与所选系统日历交互。更完整的安全说明见 [SECURITY.md](./SECURITY.md)。

## 已知限制

- TinyDesk 不会出现在 macOS 系统小组件图库中；这是为了支持真正的桌面直接编辑。
- 当前没有 iCloud、多设备同步、通用工作区导入/导出或多人协作；系统日历关联是例外。
- DMG 使用 ad-hoc 签名，尚未经过 Developer ID 公证；首次启动需要按上述方式在 Finder 中确认。
- 卡片不会覆盖全屏独占应用，也不会保持在普通应用窗口之上。
- 系统日历的账号、共享、冲突解决仍由 macOS 日历管理；TinyDesk 不提供云端合并策略。
- v1.0.0、v1.1.1 与 v2.0.0 均可继续单独下载。旧版本不了解后续版本新增的数据字段，降级前请备份工作区和资料库。

## 架构

```text
菜单栏 / 控制中心 / 桌面卡片（SwiftUI）
                 │
       DesktopWindowManager（AppKit）
                 │
       DesktopWorkspaceStore（JSON）
                 │
       TinyDeskCore（纯 Foundation）
```

`TinyDeskCore` 不依赖 SwiftUI 或 AppKit，负责模型、日期规则、待办排序和工作区迁移；主应用负责
窗口、输入、持久化和本地通知。详细设计见 [工程架构](./docs/ARCHITECTURE.md) 与
[桌面卡片扩展指南](./docs/DESKTOP_CARD_GUIDE.md)。

## 参与项目

欢迎提交 Issue 和 Pull Request。开始前请阅读 [贡献指南](./CONTRIBUTING.md) 和
[行为准则](./CODE_OF_CONDUCT.md)。安全问题请按照 [安全政策](./SECURITY.md) 私下报告。

## 许可证

TinyDesk 使用 [MIT License](./LICENSE)。
