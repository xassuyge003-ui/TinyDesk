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
| 便签 | 多卡片、标题和正文直接编辑、空白占位、自动保存 |
| 重要日期 | 日历/列表视图、生日/纪念日/节日/其他分类、一次性或每年重复、年龄与周年、本地通知 |
| 待办 | 新增与编辑、完成删除线、完成项自动下移、全部/未完成/已完成筛选、昨日未完成和逾期提示 |
| 外观 | 石墨、暖沙、薄荷、玫瑰、海洋五种颜色；毛玻璃、透明、不透明三种背景 |
| 布局 | 小号方形、中号横向、大号方形预设，也可拖动边缘自由缩放 |
| 桌面体验 | 跨 Space、显示/隐藏、恢复默认位置、卡片位置锁定、菜单栏控制中心 |
| 隐私 | App Sandbox、本地 JSON、无账号、无遥测、无网络请求 |

## 当前状态

- 当前版本：`1.0.0`（build 10）
- 最低系统：macOS 14
- 发布阶段：可用的早期版本，数据格式带版本号并包含旧版迁移
- 自动验证：38 项核心模型与持久化自检，以及无签名 Xcode Debug 构建
- 已实机验证：直接编辑、窗口层级、尺寸预设、外观切换、锁定、待办筛选和重要日期双视图

参考资源占用来自一台开发机上的首个公开版本 Release 快照：应用约 `4.7 MB`，空闲时 RSS
约 `139 MB`，初始工作区约 `4 KB`。内存和数据大小会随系统版本、卡片数量及内容变化。

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

个人免费 Apple ID 足以在自己的 Mac 上构建和运行。本项目不依赖付费能力。公开仓库目前提供源码，
不提供经过 Apple Developer ID 公证的通用安装包。

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
- 未锁定卡片可拖动标题区域移动，也可拖动边缘自由缩放。
- 重要日期顶部左侧提供日历/列表切换、分类筛选和新增按钮。
- 点击锁图标，或在卡片/控制中心菜单选择“锁定位置”，可以防止误拖；锁定不影响编辑和缩放。
- 卡片获得编辑焦点后仍停留在普通应用窗口下方。

### 重要日期与提醒

重要日期支持一次性事件和每年重复事件。生日或纪念日填写起始年份后，会显示年龄或周年数。
提醒可设置为当天或提前 1、3、7 天，并选择提醒时间。首次启用提醒时，macOS 会请求 TinyDesk
的通知权限；若拒绝，可稍后在 **系统设置 → 通知 → TinyDesk** 中修改。

### 待办规则

- 勾选完成后显示删除线，并移动到当前列表底部。
- 可筛选全部、未完成和已完成事项。
- 昨日计划但未完成的事项显示“昨日未完成”，更早的事项显示逾期天数。
- 事项支持优先级和计划日期。

## 数据与隐私

TinyDesk 不包含账号、分析 SDK、广告、云同步或联网内容。便签、重要日期、待办和窗口布局写入：

```text
~/Library/Containers/com.kai.tinydesk/Data/Library/Application Support/TinyDesk/workspace.json
```

控制中心底部可以直接在 Finder 中定位该目录。写入采用原子替换；如果工作区无法解析，程序会先保存
带时间戳的损坏文件备份，再创建默认工作区。卸载应用或清理容器前，请先备份 `workspace.json`。

本地通知由 `UNUserNotificationCenter` 调度，日期内容不会发送给第三方。更完整的安全说明见
[SECURITY.md](./SECURITY.md)。

## 已知限制

- TinyDesk 不会出现在 macOS 系统小组件图库中；这是为了支持真正的桌面直接编辑。
- 当前没有 iCloud、多设备同步、导入/导出或多人协作。
- 未提供 Developer ID 公证的二进制安装包；普通用户需要通过 Xcode 从源码运行。
- 卡片不会覆盖全屏独占应用，也不会保持在普通应用窗口之上。
- 农历生日、闰月和系统日历导入尚未实现。

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
