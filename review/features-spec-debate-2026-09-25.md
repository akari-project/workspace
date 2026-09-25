<!-- SPDX-License-Identifier: Apache-2.0 -->

# settings 键 `features` 规格评审（2026-09-25）

背景：workspace `backlog/M1.md` M1-01“后续”中安全审查余留的规格缺口：settings 键 `features` 的存储格式与默认值未定义（spec/03 3.6、spec/13 OPS-08）。lead 提出方案，`spec-owner` 代理作为反方评审，lead 核实了反方引用的证据（`internal/clientapi/config.go` 的 `map[string]bool` 解码与按秒截断的 `issuedAt`、backlog M1-09、API-11 的“不早于”规则、`diagnostics` 只出现在 spec/30 的接口表中）。做法与 `m1-01-followups-debate-2026-09-24.md` 相同，先辩论再改规格。

| # | lead 方案 | 反方意见 | 定案 |
|---|---|---|---|
| F1 | JSON 对象，键为五个模块名，值为布尔；缺键视为 `false` | 同意；补“只有 JSON `true` 算开启” | 采纳：只有 `true` 算开启，`false` 与缺键等价（spec/03 3.6） |
| F2 | 站点初始化不写入该键 | 同意，与 `registration_policy`、`min_version` 的缺省做法一致 | 采纳 |
| F3 | 未知键忽略 | 同意方向；现有实现解码到 `map[string]bool`，任一值非布尔或整体非对象时 `GET /v1/config` 返回 500 | 读取永不因此键失败：非对象视为全部关闭，某键不是 `true` 视为关闭，未知键忽略；值异常时记 warn 日志，只记键名（CONV-24） |
| F4 | 更新按键合并；未知模块名、非布尔值返回 `invalid_format`（`features.<name>`） | 同意，有 `smtp` 合并先例；补 `null` 同样 `invalid_format`；契约不加 `additionalProperties: false`（请求收窄，oasdiff 可能判为破坏性），实现不得用生成的结构体静默丢弃未知键 | 采纳；规格写明与 `min_version` 整体替换不同的理由（开关没有“删除”语义）；契约只改描述 |
| F5 | 只有 `features` 有效值实际变化时写 `config_issued_at` | 扩大到三个键；另发现 `issued_at` 须严格递增：按秒截断时同一秒两次修改得到相同值，客户端按“不早于”会接受旧文档；副本时钟偏差可能写入更早的值，客户端长期拒绝新文档 | 三个键统一“有效值实际变化才写”；写入值 `max(当前时刻, 上一次的值 + 1 秒)`，秒精度，同一事务中锁行读写（`SELECT … FOR UPDATE` 或带 `GREATEST` 的 `UPDATE`）；客户端仍按“不早于”，相同文档重复获取必须接受；惰性初始化只是兜底（API-11） |
| F6 | 管理接口拒绝开启未实现的模块（`not_allowed`），响应不加字段 | 修改：只拒绝写入不够，回滚或直接改库后残留的 `true` 会使旧二进制下发“开启”而接口 404；须在读取时屏蔽。响应不加字段可接受：后台嵌入同一二进制（ADR 0016），构建时知道已实现的模块 | 有效值 = 存储为 `true` 且本二进制已实现；`/v1/config` 与 `GET /v1/settings` 都返回有效值；开启未实现模块返回 400 `invalid_request`（`features.<name>`、`not_allowed`），提交 `false` 始终允许；残留的 `true` 保留，重新升级后恢复生效；屏蔽导致的变化不写 `issued_at`；前端按构建时清单置灰，以服务端为准；约束 M1-09 的实现（OPS-08） |
| F7 | 描述澄清发补丁版本，行为变化再评估 | F4、F6 为语义变更，按 ENG-04 与 v0.4.0、v0.5.0 的先例升小版本 | panel-spec v0.6.0：console `Settings.features` 响应加 `required`；两处 `features` 描述补合并语义、错误码、未实现模块；`getConfig` 的 `features` 与 `issued_at` 描述补充；console 示例改为全部关闭 |
| N1 | — | `issued_at` 严格递增（见 F5） | 并入 F5 |
| N2 | — | 读取健壮性（见 F3） | 并入 F3 |
| N3 | — | `diagnostics` 没有任何 backlog 条目 | 不新建条目（不凭空编验收标准）；OPS-08 注明尚未排期、实现前不可开启；backlog M1-01“后续”提示负责人排期 |
| N4 | — | OPS-08 未说明模块关闭时管理接口的行为 | 管理接口不受模块开关影响，运营者可先准备内容再开启（OPS-08） |
| N5 | — | 关闭 `referrals` 与账号邀请码的关系已在 spec/10 AUTH-02 中规定 | OPS-08 只加引用，不改 spec/10 |
| N6 | — | backlog 中 `config_issued_at` 惰性初始化一项与 F5 相关 | 规格写明由站点初始化写入，惰性初始化只是兜底；实现归 M1-09 |

## 迁移

- 本次为规格与契约描述的补全，不涉及数据库迁移与 proto。
- panel 现有实现（缺省全部关闭、忽略未知键）在 M1 阶段的对外结果不变：五个模块都未实现，屏蔽后恒为 `false`。容错解码、屏蔽、`issued_at` 严格递增与测试作为 panel 跟进项，在负责人为 panel-spec 打 v0.6.0 tag 后进行（backlog M1-01“后续”）。
- 设置管理接口尚未实现（M1-09），F4、F6 的写入规则在该任务中首次实现，无兼容问题。

## C2 定案

`review/m1-01-followups-debate-2026-09-24.md` 中留给负责人的 C2（批准设备授权与扫码登录是否列入 AUTH-23），负责人已定案：**列入**。该记录已提交，不修改，定案记录于此。

- 规格：spec/10 AUTH-23 的覆盖范围加入“批准设备授权与批准扫码登录（AUTH-24）”；AUTH-24 注明批准方需要重新验证，理由是批准会为账号新增一个 90 天有效、不随批准方会话吊销的会话。被批准的新设备登录不算重新验证，不变。
- 契约：client `approveDeviceAuthorization`（`POST /v1/me/device-authorizations`）与 `approveDeviceLink`（`POST /v1/device-links/{id}/approve`）的 401 改为引用 `MfaRequired`，与 `disableTotp`、`startTotpEnrollment` 一致；并入 panel-spec v0.6.0。
- 迁移：两个接口尚未实现，也没有 backlog 条目，无兼容影响；backlog M1-01“后续”提示负责人排期。

### 与 CONV-12 幂等缓存的冲突（已定案）

`spec-owner` 核实契约时发现：这两个操作接受 `Idempotency-Key`（其余七个需要重新验证的操作都不接受）。CONV-12 原规定缓存 2xx 与 4xx，处理器返回的 401 `mfa_required` 会被缓存；客户端按 UI-09 重新验证后用同一键重试，24 小时内都会得到缓存的 401，批准永远无法成功。lead 核实：panel `internal/clientapi` 中认证（401 `unauthenticated`）与限流（429）在幂等中间件之前执行，不进入记录；`internal/idempotency` 只跳过 5xx。因此会被缓存的是处理器返回的 401 `mfa_required`，以及今后可能由处理器返回的 401 或 429。

| # | 做法 | 结论 |
|---|---|---|
| a | CONV-12 增加例外：401 与 429 同 5xx 一样不缓存 | **采纳**：通用规则，契约不破坏，实现只改幂等中间件 |
| b | 重新验证检查放在幂等中间件之前 | 不选：依赖实现中的执行顺序，不能作为规格 |
| c | 客户端重新验证后换新键重试 | 不选：与“重试原请求”相反，客户端容易实现错 |
| d | 两个操作不再接受 `Idempotency-Key` | 不选：批准不是幂等的，需要幂等键；去掉参数有破坏性风险 |

定案：CONV-12 改为 5xx、401、429 不缓存，删除记录，允许同键重试。理由：401 与 429 反映调用方当时的认证状态或配额，不是请求本身的结果；重新验证或等待 `Retry-After` 后，客户端按 UI-09 用原键重试原请求必须成功。同处注明鉴权与限流先于幂等处理，本条覆盖的是处理器内部产生的 401 与 429。契约在 client 文档总述中同步，记入 panel-spec v0.6.0；panel 幂等中间件的修改列为 v0.6.0 发布后的跟进项（backlog M1-01“后续”）。

## protocol-reviewer 审查

结论：修复 1 处阻塞后可以合并。负责人决定 B1 与 S1–S5 在本轮修复，S6 只记录。

| # | 意见 | 处理 |
|---|---|---|
| B1（阻塞） | CONV-10 的例外只写了 `/v1/config`，管理接口 `settings.features` 同样使用模块名作键 | spec/02 CONV-10 改为“`/v1/config` 与管理接口 `settings.features` 的键名是模块名” |
| S1 | CHANGELOG v0.6.0 的语义变更应按先例单列“变更（破坏性）” | 拆为“变更（破坏性）”（批准操作需要重新验证、features 返回有效值、拒绝开启未实现模块、按键合并时未知键报错）与“变更” |
| S2 | CHANGELOG 的在线执行说明中“回滚下发 `false`”只对已实现屏蔽规则的二进制成立 | 限定为回滚到 panel 跟进 v0.6.0 之后的二进制；跟进之前的实现下发存储值；M1 阶段只有直接改库才会出现 |
| S3 | 屏蔽导致的变化不写 `issued_at`，会出现 `issued_at` 相同而 `features` 不同的文档 | OPS-08 与 CHANGELOG 安全条目注明这是已知且接受的例外；严格递增不等于“`issued_at` 相同则内容相同” |
| S4 | CONV-12 “只缓存 2xx 与 4xx”与随后的 401、429 例外字面矛盾 | 改为“缓存 2xx 与 4xx 响应（401、429 除外）；5xx、401、429 不缓存” |
| S5 | 未规定 `features` 本身为 `null` 或非对象时的错误 | spec/03 3.6 与 console `SettingsUpdate.features` 补：返回 `invalid_format`，`field` 为 `features` |
| S6 | spec/32 把 `/activate` 页面标为 M1，而 backlog 没有 AUTH-24 的实现任务 | 不改规格；backlog 的 AUTH-24 排期提示注明排期时需与 spec/32 对齐 |
