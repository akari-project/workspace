# ADR 0008：对外接口命名

- 状态：已接受
- 日期：2026-09

## 背景
不希望接口路径与 V2Board、Xboard、SSPanel 雷同。

## 决定
采用 `/v1/` 资源式命名、`/v1/me/...`、标准 OAuth 端点、RFC 9457 错误；对外不使用 subscribe、server、traffic 等词。

## 影响
第三方客户端导入路径为 `/v1/configurations/{token}`，与常见面板不同，迁移用户需重新导入。
