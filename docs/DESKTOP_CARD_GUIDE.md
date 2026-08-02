# 如何新增一种桌面卡片

## 1. 扩展核心模型

在 `DesktopCardKind` 增加类型，并为 `DesktopCard` 提供默认工厂。模型必须保持 `Codable`、
`Sendable`、`Equatable`，且只能依赖 Foundation。若 JSON 结构发生不兼容变化，应提升
`TinyDeskWorkspace.currentSchemaVersion` 并实现迁移。

## 2. 添加卡片视图

在 `DesktopCardHostView.cardContent` 添加对应分支。视图至少覆盖两种布局：

- 紧凑：接近该类型 `contentMinSize`；
- 常规：默认尺寸到最大尺寸。

还需验证 `DesktopCardSizePreset` 的三种标准尺寸：小号方形、中号横向和大号方形。

编辑绑定统一调用 `DesktopWorkspaceStore.updateCard`，不要在视图中直接写文件。

## 3. 配置窗口尺寸

在 `DesktopWindowManager` 中补充默认尺寸与最小/最大尺寸。验证：

- 新建时不会遮挡已有默认卡片；
- 外接显示器断开后会回到可见区域；
- 标题栏隐藏后仍能通过左上角拖动柄移动；
- 取得焦点及失焦后均停留在桌面层，不遮挡普通应用。

## 4. 接入入口

同步更新控制中心的新建按钮、菜单栏新建项、管理卡片的图标与摘要。

## 5. 验证

```bash
cd TinyDeskCore && swift run TinyDeskSelfTests
xcodebuild -project TinyDesk.xcodeproj -scheme TinyDesk -configuration Debug build
```

最后在真实桌面验证直接编辑、移动、位置锁定/解锁、缩放、隐藏/恢复、三种背景风格、五种颜色、待办筛选、完成项下移、重要日期日历/列表切换、编辑弹窗和重启后的数据恢复。通知还需在系统设置中允许 TinyDesk 通知后，以未来时间的测试事件做一次真实投递验证。
