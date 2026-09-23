# 23 第三方客户端配置导出

适用范围：`panel/server/internal/export`。自研客户端不使用本功能，见 spec/30。

- **EXP-01** 地址：`GET /v1/configurations/{token}`，令牌只存 SHA-256。无效令牌返回 404。按令牌与来源 IP 限流，超限 429。
- **EXP-02** 格式：`singbox`（JSON）、`mihomo`（YAML）、`base64`（分享链接）。`format=auto` 时按 User-Agent 识别，无法识别返回 base64；浏览器访问重定向到用户中心导入页。
- **EXP-03** 所有格式由同一个节点中间表示生成；每个适配器有 golden 测试（覆盖 7 种协议、空配置、特殊字符节点名），并用对应内核或解析库加载校验。mihomo 适配器与自研客户端共用 golden 数据（spec/30 API-08）。
- **EXP-04** ETag = 哈希(账号状态版本, 节点拓扑版本, 格式, 模板版本)，支持 304。
- **EXP-05** 响应头：`Subscription-Userinfo`（上传、下载、总量、到期）、`Profile-Update-Interval`（默认 24 小时）、`Cache-Control: private, no-store`。
- **EXP-06** 免费账号返回不含节点的配置，`Subscription-Userinfo` 标明已到期。
- **EXP-07** 同一实例内以 `account_id:format:etag` 做 singleflight；结果按 ETag 缓存在 Valkey。
