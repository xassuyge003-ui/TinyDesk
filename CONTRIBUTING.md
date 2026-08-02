# 贡献指南 | Contributing Guide

感谢你为 TinyDesk 贡献。项目目标是提供轻量、免费、本地优先的 macOS 桌面卡片。

## 快速上手

1. 安装 macOS 14+ 与 Xcode 15+。
2. 安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen)，运行 `xcodegen generate`。
3. 打开生成的 `TinyDesk.xcodeproj`，选择 `TinyDesk` scheme。
4. 在 **Signing & Capabilities** 选择自己的 Personal Team；不要提交 Team ID 或签名文件。
5. 运行 `cd TinyDeskCore && swift run TinyDeskSelfTests`。
6. 在独立分支完成小而聚焦的改动。

## 工程约束

- `TinyDeskCore` 保持 Foundation-only。
- 卡片数据统一经 `DesktopWorkspaceStore` 更新，不绕过原子持久化。
- 不添加网络、App Group 或云端依赖，除非产品范围先明确调整。
- 新 UI 必须验证最小、默认和最大尺寸，并兼顾浅色/深色外观。
- 修改 `project.yml` 后使用 XcodeGen 重新生成 `TinyDesk.xcodeproj`。

新增卡片类型参见 [桌面卡片指南](./docs/DESKTOP_CARD_GUIDE.md)。

## 提交流程

- Commit 使用 Conventional Commits：`feat:`、`fix:`、`docs:`、`refactor:`、`test:`、`chore:`。
- PR 写明动机、改动与实际验证结果。
- 不提交 DerivedData、用户数据或签名凭据。
- 提交前执行核心自检和无签名构建：

```bash
cd TinyDeskCore && swift run TinyDeskSelfTests && cd ..
xcodegen generate
xcodebuild -project TinyDesk.xcodeproj -scheme TinyDesk \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

提交的贡献将以 [MIT 许可](./LICENSE) 发布。
