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
