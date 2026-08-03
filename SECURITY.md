# 安全政策 | Security Policy

## 支持范围

TinyDesk 当前处于早期版本阶段。安全修复会优先应用到 `main` 和最新的 `2.x` 版本，
旧开发快照不单独维护。

## 报告安全问题

请优先使用 GitHub 仓库 **Security → Report a vulnerability** 私下提交报告。不要在公开
Issue 中披露可直接利用的漏洞、私人卡片内容、签名材料或其他敏感信息。

报告最好包含：

- 受影响版本和 macOS 版本；
- 复现步骤及影响；
- 相关日志或最小示例（请先移除个人数据）；
- 如果已知，可行的修复或缓解建议。

## 数据与权限边界

- TinyDesk 使用 App Sandbox，仅把工作区写入自己的应用容器。
- 项目不包含账号、分析、遥测、广告、云同步或联网内容。
- 本地通知由 macOS `UNUserNotificationCenter` 调度，不使用远程推送。
- 系统日历访问仅在用户主动导入、关联或同步重要日期时经 EventKit 请求；TinyDesk 不传输日历内容。
- 工作区包含用户输入的便签、日期和待办。提交 Issue、日志或示例前，请勿上传真实工作区。

## Security policy

Please report vulnerabilities privately through **Security → Report a vulnerability**. Do not put
exploitable details, personal workspace data, signing credentials, or other sensitive information in
a public issue. Fixes target `main` and the latest `2.x` release.
