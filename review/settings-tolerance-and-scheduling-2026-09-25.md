<!-- SPDX-License-Identifier: Apache-2.0 -->

# settings 读取容错与后续排期评审（2026-09-25）

背景：workspace `backlog/M1.md` M1-01“后续”中的三个待排期项：settings 键 `registration_policy` 与 `min_version` 值异常时 `GET /v1/config` 与登录返回 500；两个批准接口与 AUTH-24 的其余部分没有 backlog 条目；`diagnostics` 模块没有排期。负责人已批准方向，lead 提出方案，`spec-owner` 代理作为反方评审，做法与 `features-spec-debate-2026-09-25.md` 相同，先辩论再改规格。本轮只改 workspace，不产生契约版本。

| # | lead 方案 | 反方意见 | 定案 |
|---|---|---|---|
| G1 | 比照 `features` 定容错读取：`registration_policy` 非枚举视为 `open`；`min_version` 非对象视为 `{}`，非法平台或版本忽略；warn 日志只记键名。疑点：`registration_policy` fail-open 是否安全、`min_version` fail-open 是否合理 | 修改疑点一：区分缺键与值异常，缺键按 `open`（AUTH-02 默认），值异常按 `closed`；现有实现对未知字符串已是 fail-open（`account.go` 注册校验只判断 `closed` 与 `invite_only`）；值异常只来自直接改库或回滚，回滚时新版本可能新增枚举值，按关闭处理是安全方向；关闭可恢复，错误开放放进的注册不可撤回。同意疑点二：`min_version` 依据自报的 User-Agent，不是安全控制（API-03），fail-closed 会让自研客户端全部无法登录。契约不需要改 | 采纳：缺键 `open`，值异常 `closed`；`min_version` 可用性优先；spec/03 3.6 表前加读取总则（安全相关的键按关闭方向，可用性相关的键按不限制方向），AUTH-02 补一句；API-11 写明下发有效值；因值异常导致的有效值变化不写 `config_issued_at`；契约不发版本，console 返回有效值的描述下次改契约时顺带写上（backlog 记录） |
| G2 | 两个批准接口并入 M1-03，验收含 401 `mfa_required` 与 CONV-12 前置约束 | AUTH-24 的六个接口都在契约中（`startDeviceAuthorization`、`issueToken` 的 device_code grant、`approveDeviceAuthorization`、`createDeviceLink`、`getDeviceLink`、`approveDeviceLink`），与规格一致；`issueToken` 目前对 device_code 返回 `unsupported_grant_type`。模式应为团队 + security-reviewer（两个 portal 页面、签发 90 天会话）；依赖只有 M1-01；M1-03 已较大，建议另立任务以便并行 | 选另立：新增 M1-03b“设备授权与扫码登录”，依赖 M1-01，团队（panel-backend、frontend）+ security-reviewer；spec/32 的 M1 标注与之一致，不需要改 |
| G3 | `diagnostics` 推迟到 M1 之后，位置待定 | 诊断日志由自研客户端提交，客户端在 1.0 之后；放进 M4 会被误以为要排期；spec/13 没有该模块的小节（保存期限、查看权限、个人信息处理未定义） | M5.md 新增“1.0 之后（随自研客户端）”一节，写明先补 spec/13 小节；M1.md 的待排期项划掉并指向这一节 |
| N1 | — | `email_domain_allowlist`、`email_domain_denylist` 值异常时注册同样返回 500（`account.go` 的 `settingList` 严格解码） | 纳入 G1，规则统一：三个注册控制键中任一值异常，有效注册策略为 `closed`（`/v1/config` 下发 `closed`，注册返回 403 `registration_closed`），不为名单单独设计错误表达；名单异常指非数组或含非字符串元素；缺键按空名单；管理接口返回有效值约束 M1-09 |
| N2 | — | 设备授权与扫码登录请求的存储位置（Valkey 或表）未定义，迁移中没有相关表；`device_code`、`poll_token` 是令牌（CONV-20） | 本轮不定；写入 M1-03b“开工前先经 spec-change 定案”，参考建议只存 SHA-256 |
| N3 | — | API-04 没有 `user_code` 输入的限流（RFC 8628 §5.1）；契约只写“多次失败后作废”，次数未定；候选数字只有 3 个 | 本轮不定；写入 M1-03b 前置，参考建议一次错误即作废 |
| N4 | — | 契约示例 `qr_content` 为 `…/link/{id}`，与 API-02 要避开的旧面板导入路径 `/link/{token}` 雷同；spec/32 未定义扫码批准页路由，也未规定非 web 批准方如何从 `qr_content` 解析 `id` | 本轮不定（避免产生契约版本）；写入 M1-03b 前置，参考建议路由避开 `/link/` |
| N6 | security-reviewer（panel 实现审查 S2）：3.6 读取总则要求读取不因值异常失败，但 `config_issued_at` 行未规定异常取值，panel `issuedAt()` 遇到 `null` 等返回 500 | — | 值异常（不是 `YYYY-MM-DDTHH:MM:SSZ` 形式的 JSON 字符串，或不是合法日历时刻）按缺键处理：`GET /v1/config` 以当前时刻条件覆盖（与惰性初始化同一路径），warn 只记键名；异常值若覆盖了更晚的时刻，客户端会暂时拒绝新文档，只有直接改库才会出现，可以接受；写入路径的递增保持 fail-closed（spec/03 3.6、API-11） |
| N5 | — | 未配置 GeoIP 时 `region` 为 null（契约 `RequestingDevice`），AUTH-24 却写“必须显示所在地区” | 本轮修改措辞：地区有则显示（spec/10 AUTH-24） |

## G1 的最终规则

- 读取总则（spec/03 3.6）：settings 键读取永不因值异常而失败；缺键取默认值；值异常按各行规定处理并记 warn 日志（只记键名，CONV-24）；安全相关的键按关闭方向，可用性相关的键按不限制方向；因值异常导致的有效值变化不写 `config_issued_at`；管理接口 `GET /v1/settings` 返回有效值（M1-09）。
- 注册控制键：`registration_policy` 值不是 `"open"`、`"invite_only"`、`"closed"` 之一（含非字符串），或 `email_domain_allowlist`、`email_domain_denylist` 值不是数组或含非字符串元素，有效注册策略为 `closed`。缺键按 `open` 与空名单。
- `min_version`：非对象视为 `{}`；非法平台或版本忽略；未知平台忽略；426 判断使用同一有效值。

## 迁移

- 只改规格与 backlog，不涉及契约、proto 与数据库。
- panel 的容错读取与测试列为跟进项（待实现，backlog M1-01“后续”）。在此之前，值异常时 `GET /v1/config`、注册与带自研客户端 User-Agent 的登录仍可能返回 500；未知的 `registration_policy` 字符串仍会放行注册。
