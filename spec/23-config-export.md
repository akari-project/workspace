# 23 第三方客户端配置导出

适用范围：`panel/server/internal/export`。自研客户端不使用本功能，见 spec/30。

- **EXP-01** 地址为 `GET /v1/configurations/{token}`，令牌只按 SHA-256 查找（CONV-20）。无效令牌返回 404。
  - 限流默认值：每个令牌每分钟 30 次，每个 IP 每分钟 60 次；无效令牌的请求同样计入 IP 限流。
  - 超限返回 429 并带 `Retry-After`。
- **EXP-02** 格式：`singbox`（JSON，`application/json`）、`mihomo`（YAML，`application/yaml`）、`base64`（分享链接，`text/plain`）。省略 `format` 时等同于 `auto`。
  - `format=auto` 时按 User-Agent 识别：

| User-Agent 包含（不区分大小写） | 格式 |
|---|---|
| `sing-box`、`SFA`、`SFI`、`SFM`、`SFT` | `singbox` |
| `clash`、`mihomo`、`Stash` | `mihomo` |
| 其他 | `base64` |

  - User-Agent 以 `Mozilla/` 开头且 `Accept` 包含 `text/html` 的，视为浏览器，返回 302，重定向到用户中心的导入页。
  - 识别表维护在 `internal/export/ua.go`，修改需同步本表。
- **EXP-03** 所有格式由同一个节点中间表示生成。每个适配器都有 golden 测试，覆盖 spec/21 协议矩阵中的全部协议、空配置、名称含特殊字符的节点，并用对应内核或解析库加载校验。mihomo 适配器与自研客户端共用 golden 数据（spec/30 API-08）。
- **EXP-04** ETag 为强 ETag，等于哈希(账号状态版本, 节点拓扑版本, 格式, 模板版本)，支持 `If-None-Match` 与 304。
  - 账号状态版本由三部分组成：当前权益的 `version`、共用凭据 ID、账号状态。
  - 节点拓扑版本是全局计数器 `settings.export_topology_version`。以下情况加 1：节点加入或离开线路组、入站变更、节点状态变化影响可见性（spec/20 NODE-20）、节点倍率或地区信息变更。
- **EXP-05** 响应头：
  - `Subscription-Userinfo`：上传、下载（计费字节）、总量、到期。每次请求都按 Valkey 实时用量生成，304 响应同样携带。
  - `Profile-Update-Interval`：默认 24 小时。
  - `Cache-Control: private, no-cache`。
  - `ETag`。
- **EXP-06** 以下账号返回不含节点的配置：没有任何权益的账号（`entitlement_status='none'`）、权益为 `over_quota` 或 `suspended` 的账号、账号状态不是 `active` 的账号。持有状态为 `active` 的免费套餐权益（接口中 `entitlement_status='free'`，BIL-15）的账号按该套餐可访问的线路组返回节点（spec/11 ACS-01）。
  - `Subscription-Userinfo` 的到期时间：有权益时取权益的到期时间，权益没有到期时间（免费套餐权益，`expires_at` 为空）时省略 `expire`；没有权益的账号取上一次付费权益的到期时间，从未购买过的取当前时间。
- **EXP-07** 同一实例内以 `account_id:format:etag` 做 singleflight。生成的响应体按 ETag 缓存在 Valkey 中：
  - 用派生自主密钥的密钥做 AEAD 加密后存储（CONV-19），TTL 不超过 1 小时；
  - 导出令牌重置或共用凭据轮换时，同步删除缓存。
- **EXP-08** 适配器跳过目标格式或目标客户端不支持的入站，并在 golden 测试中覆盖：
  - `mihomo` 格式跳过 Xray-core v26.7.11 及以上内核上的 Reality 入站，以及 AnyTLS 与 Reality 组合的入站（spec/30 API-09）；
  - `base64` 格式跳过没有标准分享链接格式的协议或传输。
- **EXP-09** 各协议凭据形式：导出配置中的用户凭据与节点上的值完全相同，按 `panel-spec` `proto/node/v1/messages.proto` 中 `Credential` 注释的规则由凭据的 `secret`（16 字节 UUIDv4）生成（spec/21 AGT-15）：
  - uuid_text 为 `secret` 按 RFC 9562 的标准文本形式（32 个小写十六进制数字按 8-4-4-4-12 用连字符分隔，共 36 个字符）。
  - VLESS、VMess 的用户 id 与 TUIC 的 uuid 填 uuid_text；VMess 的 alterId 为 0（AEAD）。
  - Trojan、Hysteria2、AnyTLS、TUIC 的密码，以及 Shadowsocks 非 2022 方式的密码，为 uuid_text。
  - Shadowsocks 2022 的用户密钥：
    - `ss2022_key_16 = HKDF-SHA256(ikm = secret, salt = 空（等价于 32 个零字节）, info = "akari-ss2022-user-key-16-v1", L = 16)`，用于 `2022-blake3-aes-128-gcm`；
    - `ss2022_key_32 = HKDF-SHA256(ikm = secret, salt = 空（等价于 32 个零字节）, info = "akari-ss2022-user-key-32-v1", L = 32)`，用于 `2022-blake3-aes-256-gcm`；
    - 客户端的密码为 `settings.inbound_key`（原样，已是 base64）`+ ":" + base64(ss2022_key_16 或 ss2022_key_32)`（SIP022 多用户格式，标准 base64、带填充）；完整示例见向量 `credential.ss2022_client`。
  - 生成结果必须与 `panel-spec` `testdata/node-v1-vectors.json` 的 `credential` 向量一致，由适配器的 golden 测试覆盖。
  - mKCP 入站按 `settings.mkcp.finalmask` 写出与节点相同的 `finalmask`（`panel-spec` `testdata/mkcp-finalmask.json`）。
