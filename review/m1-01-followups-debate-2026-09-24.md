<!-- SPDX-License-Identifier: Apache-2.0 -->

# M1-01 剩余后续评审（2026-09-24）

背景：workspace `backlog/M1.md` M1-01“后续”中的两项规格缺口：绑定 TOTP 是否需要重新验证（AUTH-23），以及 `/v1/config` 的数据来源与 API-03 的 426。lead 提出方案，`spec-owner` 代理作为反方评审，lead 核实了反方引用的证据（`internal/session/mfa.go` 的重新验证分支、client v1.yaml 中列出 426 的四个操作与 `startTotpEnrollment` 的 401 引用、`internal/config` 的 `ui.portal.api_base_url` 与 `PANEL_TOKEN_KEY` 格式）。负责人要求继续处理后续事项；做法与 v0.4.0 相同，先辩论再改规格。

| # | lead 方案 | 反方意见 | 定案 |
|---|---|---|---|
| A1 | 开始绑定 TOTP 需要重新验证 | 同意；另建议待确认密钥绑定发起会话 | AUTH-23 加入“开始绑定二次验证（TOTP；M4 的 Passkey 注册）”；AUTH-11 写明待确认密钥绑定发起会话，确认须来自同一会话 |
| A3 | 契约只改描述 | 修改：`startTotpEnrollment` 的 401 应引用 `MfaRequired`，与 `disableTotp` 一致 | 采纳，panel-spec v0.5.0 |
| A4 | 登录成功是否视为重新验证（开放问题） | 同意但收窄；lead 所说的“M1-02 管理员首次绑定受益”不成立（AUTH-21 在登录流程内完成绑定） | 只有以密码完成的 `POST /v1/sessions` 登录写入 5 分钟状态；AUTH-24 的设备授权与扫码登录不写（否则被盗会话可借新设备免密码绑定 TOTP）；刷新只沿用剩余时间 |
| B1 | settings 键 `min_version` | 同意；补字段路径、可选字段、与已发布版本的关系 | 采纳，spec/03 3.6；M1 只在界面提示不高于已发布版本 |
| B2 | 新增 `http.public_url` 作为主地址，备用地址放 settings | 修改：已有 `ui.portal.api_base_url`（DEP-04）；备用地址放 settings 等于允许后台把全部客户端引到任意域名 | 主地址取 `ui.portal.api_base_url`，否则取用户中心公开地址；备用地址放部署配置 `client.api_endpoints`，不进 settings 与管理接口；每项语义同 `api_base_url`，可带路径前缀（spec/30 API-11） |
| B3 | settings 计数器 `announcement_version`，公告写入时加 1 | 反对：无法反映按时生效与失效；公告写入会改变 Settings 的 ETag，使管理员编辑设置时收到 409 | M1 只定义语义（单调不减，生效集合可能变化时增大），公告模块实现前恒为 0；不新增 settings 键 |
| B4 | `PANEL_CONFIG_SIGNING_KEY`，字符串 `key_id`，缺失时 503 | 修改：CONV-30 要求与主密钥同格式；缺失不是“依赖暂时故障” | `PANEL_CONFIG_KEY`，格式同 `PANEL_TOKEN_KEY`（key_id 1–255，输出十进制字符串）；api 角色缺失时拒绝启动；公钥须与令牌签名密钥不同；无 `_PREVIOUS`，写明换钥流程（CONV-30） |
| B5 | 按输入哈希在 Valkey 中 `SET NX` 缓存签名文档 | 反对：设置 X→Y→X 时命中旧文档，`issued_at` 回退；按 `issued_at` 防回滚的客户端会拒绝 | 确定性生成：`issued_at` 取应用在相关设置修改同一事务中写入的 settings 键 `config_issued_at`；Ed25519 签名确定，各副本 ETag 一致，不用 Valkey；客户端按 `issued_at` 防回滚；`Cache-Control: no-cache` |
| B6 | 除 `GET /v1/config` 外所有接口返回 426 | 反对：契约只在四个入口操作上列出 426；会拦住 `/v1/releases/latest`（旧客户端无法升级）与 `/v1/oauth/token`（CONV-16 例外） | 426 只用于 `createSession`、`createSessionNonce`、`createDeviceLink`、`getMyConfiguration`；`AppName` 来自部署配置 `client.app_name`（默认 `Akari`，RFC 9110 token）；平台不区分大小写，`iPadOS` 对应 `ios`；只比较主、次、修订号 |
| B7 | panel-spec v0.5.0 | 同意，调整内容 | 包含 A3、console `Settings`/`SettingsUpdate` 的 `min_version`（可选）、`getConfig` 描述（`api_endpoints` 构成、防回滚、`Cache-Control`）、`key_id` 示例改为 `"1"` |
| C1 | — | 安全缺陷：账号没有密码时，任意密码都能完成重新验证（`ok` 已由限流结果置为 true） | 已修复并有测试（panel e4314bf 之后的提交 6a030d9）；AUTH-23 写明无密码时返回 `incorrect`、耗时一致 |
| C2 | — | 批准设备授权与扫码登录也应要求重新验证：短期被盗会话可换成攻击者设备上 90 天有效、不随原会话吊销的会话 | 未定：涉及产品体验（每次扫码登录都要输密码），留给负责人决定，见下 |
| C3 | — | 刷新时复制重新验证状态是正确的 | 已实现（panel e4314bf） |

## 契约审查（protocol-reviewer）

v0.5.0 草稿的两个阻塞问题已修复：console 的 `info.version` 未升；client 文档总述仍写“任何接口都可能返回 426”，与 API-03 冲突。另采纳：
- 规格中“确认必须来自同一会话”改为同一会话链，否则绑定途中一次正常刷新就会使确认失败；`activateTotp` 写明 409 `invalid_state`。
- 新规则原编号 API-10 与已有的 API-10（OpenAPI 覆盖页面字段）重复，改为 API-11。
- `SettingsUpdate.min_version` 整体替换；`SignedConfig.key_id` 加约束；`issued_at` 描述补全；版本号不允许前导零；“不高于已发布版本” M1 不校验。
- 后续：`Release` 示例的 `key_id`（`rel-2026-01`）若按 CONV-30 同格式应改为十进制字符串，不在本次范围。

## 待负责人决定

- C2：批准设备授权（`POST /v1/me/device-authorizations`）与批准扫码登录（`POST /v1/device-links/{id}/approve`）是否列入 AUTH-23。两个接口尚未实现（M1-03 之后），不阻塞本次变更。

## 迁移

- AUTH-23 的新增要求：已登录但未在 5 分钟内重新验证的会话，开始绑定 TOTP 时会收到 401 `mfa_required`；用户中心已有重新验证对话框，行为一致。
- `/v1/config` 尚未实现，本次为首次定义，无兼容问题。部署需新增环境变量 `PANEL_CONFIG_KEY`，升级说明写入 CHANGELOG 与部署文档。
