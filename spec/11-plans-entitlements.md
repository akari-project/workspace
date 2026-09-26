# 11 套餐、权益与节点权限

适用范围：`panel/server/internal/billing`、`internal/access`。订单与支付见 spec/12。

## 11.1 概念

- **套餐** `plans`：可访问的线路组、每周期流量、设备上限、限速、流量重置规则、等级 `tier`（0 保留给免费套餐）、类型 `kind`（`recurring` 周期、`one_time` 一次性、`free` 免费）、状态 `status`（`draft`、`on_sale`、`hidden`、`archived`）。
- **价格** `plan_prices`：套餐的一个计费周期（`month`、`quarter`、`half_year`、`year`、`one_time`）与金额。一个周期可以有多个价格行，其中同时只有一行在售。
- **权益** `entitlements`：账号拥有的套餐实例，保存购买时的参数快照与锁定价格。状态：`scheduled`（下一段）、`active`、`over_quota`、`suspended`、`ended`。
- **免费账号**：没有“`kind≠free` 且状态为 `active`、`over_quota`、`suspended`”的权益的账号。持有免费套餐权益的账号也属于免费账号；接口中这两种情况分别为 `entitlement_status='none'` 与 `'free'`。
- **本段**与**本段实付**：见 BIL-20。

## 11.2 规则

- **BIL-01** 价格行一旦创建，金额、币种、周期、`period_days` 都不可修改。`on_sale` 只能从 true 改为 false，不能重新开售。改价的做法是停售旧行，再新建一行。
  - 非免费套餐的价格金额必须大于 0。免费套餐不设价格行，由 BIL-15 授予。
  - 数据库触发器用 `IS DISTINCT FROM` 比较上述字段（spec/03）。
  - 周期必须与套餐类型匹配：`recurring` 套餐只用 `month`、`quarter`、`half_year`、`year`，且 `period_days` 为空；`one_time` 套餐只用 `one_time`，`period_days` 为有效天数，为空表示长期有效（BIL-09）。不匹配返回 400 `invalid_request`（`errors[].code` 为 `not_allowed`，`field` 为 `period` 或 `period_days`）；数据库由插入触发器兜底（spec/03）。
  - 币种必须等于站点结算货币（CONV-08），否则返回 400 `invalid_request`（`currency`、`not_allowed`）；站点尚未初始化结算货币时返回 409 `invalid_state`。
  - `on_sale` 套餐至少保留一行在售价格：停售其最后一行在售价格返回 409 `invalid_state`，需先把套餐改为 `hidden` 或 `archived`。改价不受影响：新建价格行时，同一周期的旧行在同一事务中停售。
- **BIL-02** 购买时把流量、设备上限、限速、重置规则写入权益快照；之后修改套餐不影响已有权益。管理后台提供显式的“应用到现有用户”操作（敏感操作，spec/10 AUTH-19），执行前显示受影响人数。
  - 作用于该套餐状态为 `active`、`over_quota`、`suspended` 的权益，每个权益追加一条 `admin_adjust` 事件（BIL-03），全部事件共用一条 `reason_texts`（`account_id` 为空，CONV-29）。
  - 执行记录保存在表 `plan_rollouts`（spec/03 3.6，`kind='apply'`），由 worker 分批执行：
    - 所选字段的值在创建时从套餐冻结到 `plan_rollouts.target_values`，之后修改套餐不影响正在执行的记录。
    - 作用范围还包括该套餐的下一段（`scheduled`），否则下一段生效时仍带旧快照。
    - 同一套餐同时只能有一条 `queued` 或 `running` 的记录（不分 `kind`，包括 BIL-15 的 `free_grant`、`free_end`），再创建返回 409 `invalid_state`；修改 `free_plan_id` 同样受此约束（BIL-15）；`expected_affected_account_count` 在请求时与当时的受影响账号数（BIL-26 口径）比较，不一致返回 409 `conflict`。
    - 每批一个事务，由 `job_fencing` 租约保证同一时刻只有一个执行者；按权益 `id` 升序推进游标 `cursor`。快照已等于目标值的权益跳过，不写事件。
    - 调低 `bytes_per_cycle` 使本周期已用量达到新额度时，权益在同一事件中变为 `over_quota`（`suspended` 不变）；`reset_policy` 的修改从下一个周期起生效，不改变当前周期的起止。
    - 某一批失败时记录 `last_error` 并重试；连续失败 10 次后状态为 `failed`，已处理的权益保持已修改。
- **BIL-03** 权益只能通过追加 `entitlement_events`、并在同一事务中更新 `entitlements` 来改变，不存在其他修改路径。
  - 每追加一条事件，`entitlements.version` 加 1。
  - 同一事务中写入 `entitlement.changed` 到 outbox（CONV-22）。
  - 事件类型与状态转换见 11.6。
- **BIL-04** 权益的线路组访问关系实时跟随套餐，不做快照。从套餐移除线路组属于敏感操作，执行前显示受影响人数。
- **BIL-05** 每个账号同时至多一个当前权益与一个下一段。
- **BIL-21** 套餐状态决定各场景能否购买（报价时校验，不满足返回 400 `invalid_request`）：

| 套餐状态 | 新购 | 续费 | 升级、降级的目标 | 说明 |
|---|---|---|---|---|
| `draft` | 否 | 否 | 否 | 仅后台可见 |
| `on_sale` | 是 | 是 | 是 | 在 `/v1/plans` 中列出 |
| `hidden` | 否 | 是（BIL-07） | 否 | 不再列出；已持有的用户可以续费 |
| `archived` | 否 | 仅当 `allow_legacy_renew` 为真 | 否 | |

- **BIL-26** 套餐的管理约束（管理接口，spec/31）：
  - 按修改后的状态检查：任何修改之后，状态为 `on_sale` 的非免费套餐必须至少有一行在售价格，否则返回 409 `invalid_state`。这包括改为 `on_sale`、新建时指定 `on_sale`（此时还没有价格行，因此不能直接指定），以及 `on_sale` 的免费套餐把 `kind` 改为非免费。免费套餐的状态不受限制，也没有启用含义（BIL-15）。
  - 已产生权益的套餐不能改回 `draft`（`draft` 阻止续费，BIL-21），返回 409 `invalid_state`，请改用 `hidden` 或 `archived`。其他状态转换不受限制。
  - `kind` 只在套餐既没有价格行、也没有权益时可以修改，否则返回 409 `invalid_state`。`kind` 与 `tier` 不匹配（`free` 必须为 0，其他必须大于 0）返回 400 `invalid_request`（`tier`、`out_of_range`）。
  - 只有既没有价格行、也没有权益、且未被设置 `free_plan_id` 引用的套餐可以删除，否则返回 409 `invalid_state`，请改为 `archived`。价格行不可删除（BIL-01），因此曾经定价的套餐只能归档。
  - 被 `free_plan_id` 引用的套餐不能修改 `kind`，返回 409 `invalid_state`。
  - 套餐可以不关联任何线路组。
  - 影响预览（spec/31 CON-07）中的受影响账号数，是持有该套餐、状态为 `active`、`over_quota`、`suspended` 权益的不同账号数，与 `active_entitlement_count` 的统计口径相同：每个账号至多一个当前权益（BIL-05），这三种状态都是当前权益，因此权益数等于账号数。

  报价请求中的 `price_id` 只用来确定“套餐 + 周期”，金额一律由服务端按场景确定：新购、升级、降级使用该周期当前在售的价格行，续费按 BIL-07。

## 11.3 购买场景

场景由报价时的权益状态与目标套餐决定（报价与下单流程见 spec/12）。免费套餐权益不参与续费与升降级（BIL-15）。

| 场景 | 条件 | 生效 | 规则 |
|---|---|---|---|
| 新购 | 免费账号 | 支付后立即 | 按**当前在售价格**计价；锁定该价格；到期 = 现在 + 周期（BIL-16）；流量周期从现在开始 |
| 续费 | 权益生效中，购买同一套餐 | 支付后立即 | 按 BIL-07 计价；本段延长，到期时间在原到期时间上顺延；**不重置流量** |
| 升级 | 权益生效中，目标套餐不同且 `tier` 更高或相同 | 支付后立即 | 应付 = 新价格 − 剩余价值（11.4）；新权益从现在开始一个完整周期、全额流量（“只按时间”模式例外，BIL-12）；锁定新价格 |
| 降级（默认） | 权益生效中，目标 `tier` 更低 | 当前权益到期时 | 购买新套餐的一个周期作为下一段，到期时自动切换并锁定新价格 |
| 立即降级（可选） | 同上，用户选择立即 | 支付后立即 | 见 BIL-23 |

- **BIL-06** 续费、升级、降级只能在权益为 `active` 或 `over_quota` 时进行；免费账号只能新购，否则返回 `entitlement_required`。到期后再买同一套餐属于新购，锁定价格随到期失效。
- **BIL-07** 锁定价格只对应一个周期（锁定价格行的周期）。
  - 续费周期与锁定周期相同时：续费价格 = min(锁定价格, 该周期当前在售价格)。若当前价格更低，锁定改为当前价格行。
  - 一次性套餐（BIL-09）的周期是二元组（`period`、`period_days`）：只与 `period_days` 相同的在售价格行取 min；没有这样的在售行时按锁定价格计价。锁定永不改到 `period_days` 不同的价格行，BIL-08 不适用于一次性套餐。
  - 套餐已下架（`hidden`、`archived`）时，生效中的用户仍可按锁定价格续费；`archived` 且 `allow_legacy_renew` 为假时除外。
- **BIL-08** 续费周期与锁定周期不同时：按该周期当前在售价格计价，锁定改为该价格行，原锁定价格随之失效。报价明细必须提示“原锁定价格将失效”。该周期当前没有在售价格时不能续费。
- **BIL-09** 一次性套餐（`kind=one_time`）不参与升降级：
  - 免费账号可以新购。
  - 持有同一个一次性套餐时可以“叠加”，场景为续费（`order_type=renew`，事件 `renew`），计价按 BIL-07：
    - 到期时间顺延锁定价格行的 `period_days`（BIL-07）；长期有效（`expires_at` 为空）时保持为空。
    - 重置规则为 `never` 时，`bytes_limit` 增加一份套餐额度，不重置已用量；其他重置规则只顺延时间。
  - 持有其他付费套餐时购买一次性套餐，或持有一次性套餐时购买其他套餐，返回 409 `invalid_state`（`entitlement_required` 只表示需要生效中的权益，CONV-16）。
  - `period_days` 为空表示长期有效。长期有效的权益不可退款，只能由管理员调整。
- **BIL-10** 升级时若存在下一段，下一段取消，并将其实付全额退回余额。
- **BIL-22** 存在下一段时，续费、自动续费和再次排队降级都返回 `conflict`，用户需先取消下一段（`DELETE /v1/me/entitlements/next`）。当前权益以任何方式结束（到期、退款、管理员调整）时，下一段在同一事务中从该时刻开始生效，到期时间 = 开始时间 + 周期（周期取其锁定价格行，BIL-16）。
  - **结束规则**：当前权益结束、且同一操作没有产生新的当前权益（升级、立即降级、新购会产生）时，在同一事务中：有下一段则下一段生效（事件 `downgrade_applied`）；否则免费套餐启用时授予免费权益（事件 `free_grant`，BIL-15）。账号注销是例外（11.6）。
- **BIL-23** 立即降级：
  - 新段至多一个周期：剩余价值 ≥ 所选价格行金额时，新段时长为所选价格行的一个完整周期；否则新段时长（秒）= floor(剩余价值 × 所选价格行的周期秒数 ÷ 所选价格行金额)，再向下取整到整小时。周期秒数按 BIL-16 从当前时刻起计算。
  - 剩余价值超出所选价格行金额的部分 max(0, 剩余价值 − 金额) 在开通的同一事务中记入余额（原因 `downgrade_surplus`，spec/12 ORD-16），报价中为 `credit_refund_minor`。
  - 时长不足 1 小时时拒绝，返回 `invalid_request`。
  - 报价请求 `mode=downgrade_immediate` 而场景不是降级时，返回 400 `invalid_request`（`mode`、`not_allowed`）。
  - 新段锁定所选价格行，`paid_minor` = min(剩余价值, 所选价格行金额)，流量从当前时刻开始一个新周期（“只按时间”模式例外，BIL-12）；新段在周期中途结束时，最后一个周期的额度按 BIL-16 折算。
  - 失去的线路组立即收回。

## 11.4 剩余价值

- **BIL-20** 本段与本段实付：
  - 本段为当前权益从 `starts_at` 到当前 `expires_at` 的区间。续费会延长本段。
  - 本段实付（`entitlements.paid_minor`）= 为本段支付的现金 + 余额抵扣 + 带入的剩余价值中抵扣新价格的部分，不含优惠折扣。带入的剩余价值只计 min(剩余价值, 新价格)，超出部分记入余额（`upgrade_surplus`、`downgrade_surplus`），不计入本段实付。续费时加上该笔续费的计价金额（不含优惠）。
  - 兑换码开通的权益，实付为 0；立即降级生成的新段，实付为 min(剩余价值, 所选价格行金额)（BIL-23）。
  - 退款后，实付减去已退金额。
  - **分笔**：本段实付由若干笔组成，每笔只覆盖自己的时间区间，各笔实付之和等于本段实付。
    - 开通本段的一笔（新购、兑换码新购、升级、立即降级、下一段生效、ORD-06 临界续费的新行）覆盖 [`starts_at`, 首个 `expires_at`)；
    - 每次续费（包括一次性套餐的叠加与兑换码续费）覆盖其顺延的区间 [原 `expires_at`, 新 `expires_at`)；
    - 长期有效的一笔，区间终点为空。
    - 每笔记录在开通它的事件的 `diff.tranche` 中：`{paid_minor, covers_from, covers_to}`，事件为 `purchase`、`redeem`、`renew`、`upgrade`、`downgrade_immediate`、`downgrade_applied`（排队的下一段在 `downgrade_scheduled` 时还没有起止，在生效的 `downgrade_applied` 中记录）。
    - 退款（spec/12 ORD-10）与管理员修改 `expires_at`（11.6）调整已有的笔，事件的 `diff.tranches` 给出调整后的完整列表；当前的分笔以最近一条带 `tranches` 的事件为基础，再加上其后各事件的 `tranche`。

```
本段各周期额度 q_i = 本段内每个流量周期的额度（按重置规则与本段起止时间确定，被本段起点或终点截断的周期按 BIL-16 折算；
                   重置规则为 never，或长期有效的一次性套餐，本段只有 1 个周期）
本周期剩余流量   = max(0, 本周期额度 − 本周期已用量)，已用量含 usage_cycles.bytes_carried（BIL-12）
第 i 笔剩余比例  = 第 i 笔区间在当前时刻之后的秒数 ÷ 第 i 笔区间总秒数；已过去的笔为 0，尚未开始的笔为 1，区间终点为空时取 1
时间部分         = Σ_i 第 i 笔实付 × 第 i 笔剩余比例
流量剩余比例     = (当前周期之后各周期的 q_i 之和 + 本周期剩余流量) ÷ (本段全部 q_i 之和)
流量部分         = 本段实付 × 流量剩余比例
剩余价值         = floor(min(时间部分, 流量部分))，全程以整数分子分母精确计算，只在最后一步向下取整（CONV-06）
升级应付         = max(0, 新价格 − 剩余价值 − 优惠)
剩余价值超出新价格的部分 = max(0, 剩余价值 − 新价格)，记入余额；优惠永不转为余额
```

- 优惠在扣除剩余价值之后计算：百分比优惠的基数为 `max(0, 新价格 − 剩余价值)`（spec/12 ORD-13）。

- **BIL-11** 剩余价值必须在 [0, 本段实付] 之间，使用整数运算（CONV-06）。
  - 周期额度为 0 表示不限流量，此时流量剩余比例取 1。
  - 各周期额度相同时，上式化为 `(k × 周期额度 + 本周期剩余流量) ÷ (N × 周期额度)`，N 为本段周期数，k 为当前周期之后的完整周期数。
  - 流量包不计入剩余价值，另按 11.8 处理。
- **BIL-12** 运营者可将折算方式配置为“只按时间”（设置 `proration_mode='time_only'`，spec/03 3.6），即剩余价值 = floor(时间部分)（BIL-20）。这种模式下，升级与立即降级不重置已用量：新权益的周期仍从当前时刻开始，本周期的已用量以 `usage_cycles.bytes_carried` 预置：
  - 新周期额度为 0（不限流量）时，预置为旧权益本周期已用量；
  - 旧周期额度为 0、新周期额度不为 0 时，预置为 min(旧权益本周期已用量, 新周期额度)；
  - 其他情况预置为 ceil(旧权益本周期已用量 × 新周期额度 ÷ 旧周期额度)。
- 示例：
  - 50 元月付（假设本月 30 天）用了 10 天、流量用了一半：min(20/30, 1/2) = 0.5，剩余价值 25 元。升级到 80 元月付，应付 55 元，新权益本段实付 80 元。
  - 360 元年付、每月 100 GiB，第 20 天本月已用 90 GiB：N = 12，k = 11，流量剩余比例 = (11 × 100 + 10) ÷ 1200 ≈ 0.925，时间剩余比例 = 345/365 ≈ 0.945，剩余价值 = floor(36000 × 0.925) = 33300 分。
  - 分笔：50 元月付（假设 30 天）、不限流量，第 29 天改为年付续费 360 元（365 天，BIL-08），随即升级。时间部分 = 5000 × 1/30 + 36000 × 365/365 ≈ 36166.67 分，流量部分 = 41000 分，剩余价值 = 36166 分。若按整段比例计算，得 41000 × 366/395 ≈ 37989 分，多出约 18 元，这就是分笔计算要堵住的差额。

## 11.5 到期与流量周期

- **BIL-13** 没有宽限期。到期时刻，权益（包括 `over_quota` 与 `suspended` 状态的）变为 `ended`，账号回到免费账号，写入 `expire` 事件，所有凭据从节点移除（ACS-02）。账号、设备、订单、余额、导出令牌保留。
  - 权益暂停期间照常计时，不冻结。
  - 到期扫描覆盖 `active`、`over_quota`、`suspended` 三种状态，worker 每分钟执行一次。
  - 到期以 `expires_at` 为准：`expires_at` 不晚于当前时刻（注入的时钟，CONV-27）的权益，在报价、读取与开通校验（spec/12 ORD-05）中都视为已结束，即使 worker 尚未写入 `expire` 事件；`ended_at` 写 `expires_at`，下一段与免费权益的开始时间同样取 `expires_at`。
- **BIL-14** 到期时存在下一段的，下一段在同一事务中变为 `active`（BIL-22）。
- **BIL-15** 免费套餐（`kind=free`，`tier=0`，`expires_at` 为空）可选，默认不启用。
  - 一个站点至多一个免费套餐（部分唯一索引，spec/03）；再建一个返回 400 `invalid_request`（`kind`、`taken`）。
  - 启用与关闭由设置 `free_plan_id` 决定（spec/03 3.6）：为空表示不启用；非空时必须引用这个唯一的免费套餐，否则返回 400 `invalid_request`（`free_plan_id`、`not_allowed`）。
  - 免费套餐的 `status` 没有启用含义。无论状态如何，免费套餐都不在客户端 `GET /v1/plans` 中列出，也不能报价购买。
  - 不变式：`free_plan_id` 为 X 时，每个状态为 `active` 或 `suspended`、没有当前权益的账号都持有 X 的权益；`free_plan_id` 为空时不存在免费权益。修改 `free_plan_id` 之后的批量执行期间不变式暂时不成立，由 worker 分批执行与每小时对账最终达成。由以下途径共同维持：
    - 修改 `free_plan_id` 是敏感操作（spec/10 AUTH-19），请求必须带 `reason`。该免费套餐已有 `queued` 或 `running` 的 `plan_rollouts`（任何 `kind`，包括 BIL-02 的 `apply`）时返回 409 `invalid_state`，与 BIL-02 相互阻止。同一事务中写入 `reason_texts`（`account_id` 为空）、审计 `setting.update`（spec/31 CON-09），以及一条 `plan_rollouts`：由空变为 X 时 `kind='free_grant'`（`plan_id` = X），由 X 变为空时 `kind='free_end'`（`plan_id` = X）。
    - worker 按 BIL-02 的方式分批执行：`free_grant` 为每个符合条件的账号新建免费权益，事件 `free_grant`（`actor_id` 为空）；`free_end` 以 `admin_adjust` 结束每个免费权益，`reason_id` 取该记录的原因。
    - 注册、管理员创建账号、接受邀请新建账号时，在同一事务中授予（事件 `free_grant`）；付费权益按结束规则（BIL-22）结束后，在同一事务中重新授予。
    - 对账：worker 每小时检查不变式，补授予缺失的免费权益（`free_grant`）；结束不属于当前 `free_plan_id` 的免费权益时，`reason_id` 取最近一条 `free_end` 记录的原因。
    - 读取 `free_plan_id` 时值异常（3.6 读取总则）不触发结束，也不触发授予；只有管理接口写入的变化才创建记录。
    - 每次新建免费权益都先对套餐行取 `FOR KEY SHARE`（BIL-26 的并发约束）。
  - 免费权益的快照取免费套餐当时的值，`expires_at` 为空，流量周期从授予时刻开始。
  - 免费套餐权益不参与续费与升降级。购买付费套餐一律按新购处理，并在同一事务中结束免费权益。
  - 免费权益不能由管理员结束（`admin_adjust` 改为 `ended` 返回 409 `invalid_state`，需要停用时改为 `suspended`），否则对账会立即重新授予；管理员也不能以 `admin_adjust` 授予免费套餐（400 `invalid_request`，`plan_id`、`not_allowed`）。
- **BIL-16** 周期与流量重置：
  - 月、季、半年、年分别为 1、3、6、12 个日历月，按站点时区（CONV-26）计算，锚定首次开始日：目标月没有该日时取月末，之后的周期仍按原锚定日计算（1 月 31 日 → 2 月 28 日 → 3 月 31 日）。
  - 时长比例一律按秒计算。
  - 流量重置规则三选一：
    - 按购买日每月重置，锚定规则同上；
    - 按自然月 1 日重置；
    - 整个有效期不重置。
  - 被本段起点或终点截断的周期，额度 = floor(周期额度 × 该周期在本段内的秒数 ÷ 该周期完整秒数)。完整秒数：自然月重置为当月秒数，按购买日重置为从锚定日到下一个锚定日的秒数。适用于：
    - 自然月重置的首个不满月周期，以及本段在月中结束时的最后一个周期；
    - 立即降级生成的新段（BIL-23）在周期中途结束时的最后一个周期；
    - 有效天数不是周期整数倍的一次性套餐的最后一个周期。
  - 整个有效期不重置时本段只有一个周期，不截断。续费或管理员调整移动本段终点时，按新的终点重算当前周期的额度（`usage_cycles.bytes_limit`）。
  - 重置时切换用量键的周期编号（spec/22 ACC-06）；因流量用尽而处于 `over_quota` 的权益恢复为 `active`。
- **BIL-17** 流量包在周期额度用完之后才开始消耗，按到期时间从早到晚；默认在当前周期结束时失效（11.8）。
- **BIL-18** 到期提醒在到期前 7、3、1 天发送，内容说明“到期后锁定价格失效”。
- **BIL-19** 余额自动续费：
  - 是账号级开关（`accounts.auto_renew`，默认关），权益变更后保留。
  - 从到期前 24 小时起每小时检查一次，直到到期；余额足够支付续费价格时，自动创建并完成续费订单。
  - 存在下一段或存在未支付的变更类订单时跳过。
  - 到期前 1 小时仍因余额不足未能续费的，发送一次提醒。

## 11.6 状态与事件

事件类型：`purchase`、`renew`、`upgrade`、`downgrade_scheduled`、`downgrade_applied`、`downgrade_immediate`、`quota_exhausted`、`cycle_reset`、`addon`、`expire`、`suspend`、`resume`、`refund`、`redeem`、`scheduled_cancelled`、`free_grant`、`admin_adjust`。

**写入规则**：
- 一次操作改变的每一行权益各写一条事件，各自使该行 `version` 加 1，并各写一条 `entitlement.changed`（CONV-34）。同一操作涉及两行时（升级、立即降级、购买时结束免费权益、BIL-10 取消下一段、ORD-06 临界续费），两行写同一类型的事件，`diff.related_entitlement_id` 指向另一行。
- 当前权益结束时按结束规则（BIL-22）处理：旧行写其结束事件（`expire`、`refund`、`admin_adjust`），生效的下一段写 `downgrade_applied`，新授予的免费权益写 `free_grant`。
- `diff` 为 `{字段: [前值, 后值]}`，只包含变化的字段；另可带 `related_entitlement_id`、`cause`（如 `account_deletion`）。
- `redeem` 按其开通的场景（新购或续费）与 `purchase`、`renew` 相同。

下表的行为当前状态，列为事件；单元格为转换后的状态，“拒”表示拒绝（括号内为错误码），“—”表示该事件不作用于该状态。“无权益”指没有当前权益（`entitlement_status='none'`）。“免费权益”指免费套餐的当前权益：其 `quota_exhausted`、`cycle_reset`、`suspend`、`resume` 与同状态的付费权益相同，其余见该行。“付费”各行指 `kind≠free` 的权益。“结束”指按结束规则（BIL-22）结束。

购买类（用户或订单触发）：

| 当前状态 | purchase / redeem（新购） | renew / redeem（续费） | upgrade | downgrade_scheduled | downgrade_immediate | addon | refund | scheduled_cancelled |
|---|---|---|---|---|---|---|---|---|
| 无权益 | 新行 active | 拒（entitlement_required） | 拒（同左） | 拒（同左） | 拒（同左） | 拒（同左） | — | — |
| 免费权益（active、over_quota） | 免费行 ended，新行 active（BIL-15；两行都写 purchase） | 拒（entitlement_required） | 拒（同左） | 拒（同左） | 拒（同左） | 拒（同左） | —（实付为 0） | — |
| 免费权益（suspended） | 拒（invalid_state） | 拒（invalid_state） | 拒（invalid_state） | 拒（invalid_state） | 拒（invalid_state） | 拒（invalid_state） | — | — |
| 付费 active | 拒（invalid_state；BIL-09） | active（一次性套餐叠加见 BIL-09） | 旧行 ended，新行 active；有下一段则下一段 ended 并退回余额（BIL-10） | active，并新建 scheduled | 旧行 ended，新行 active；有下一段则下一段 ended 并退回余额 | active | active，或缩短至 0 后结束 | — |
| 付费 over_quota | 拒（invalid_state） | over_quota（续费不重置流量） | 同 active | over_quota，并新建 scheduled | 同 active | active（流量包使已用量低于额度时），否则 over_quota | 同 active | — |
| 付费 suspended | 拒（invalid_state） | 拒（invalid_state） | 拒（invalid_state） | 拒（invalid_state） | 拒（invalid_state） | 拒（invalid_state） | 同 active | — |
| scheduled | — | 拒（conflict，BIL-22） | ended，实付全额退回余额（BIL-10） | 拒（conflict） | ended，实付全额退回余额 | — | ended，全额退款 | ended，实付全额退回余额 |
| ended | — | —（ORD-06 例外，见下） | — | — | — | — | — | — |

系统与管理类：

| 当前状态 | downgrade_applied | quota_exhausted | cycle_reset | expire | suspend | resume | free_grant | admin_adjust |
|---|---|---|---|---|---|---|---|---|
| 无权益 | — | — | — | — | — | — | 新行 active（免费套餐启用时） | 授予新权益（见下） |
| 免费权益 | — | 同付费 | 同付费 | ended（仅注销，diff.cause='account_deletion'） | 同付费 | 同付费 | 拒（invalid_state；已持有，对账时跳过） | 可改为 active、over_quota、suspended 与快照字段；改为 ended 拒（invalid_state，BIL-15） |
| 付费 active | — | over_quota | active | 结束 | suspended | — | 拒（invalid_state） | 见下 |
| 付费 over_quota | — | — | active | 结束 | suspended | — | 拒（invalid_state） | 见下 |
| 付费 suspended | — | —（仍记录用量） | suspended（周期仍然切换） | 结束 | — | 按当前周期用量回到 active 或 over_quota | 拒（invalid_state） | 见下 |
| scheduled | active（当前段结束时，BIL-22） | — | — | ended（只在账号注销时，`diff.cause='account_deletion'`） | — | — | — | 只可改为 ended（不自动退款，退款另行调整余额） |
| ended | — | — | — | — | — | — | — | 拒（invalid_state；需要时授予新权益） |

- **暂停与恢复**：管理接口 `createEntitlementAdjustment` 只修改状态、且为 `active`/`over_quota` → `suspended` 时写 `suspend`；从 `suspended` 改为 `active` 或 `over_quota` 时写 `resume`，结果状态由服务端按当前周期用量决定。两者都必须带原因（`reason_id`，由应用校验）。暂停或恢复同时修改其他字段返回 400 `invalid_request`（`status`、`not_allowed`）。其他调整写 `admin_adjust`。
- **管理员调整（admin_adjust）**：
  - 授予新权益（不带 `entitlement_id`）：账号已有付费当前权益时返回 409 `invalid_state`；持有免费权益时在同一事务中以 `admin_adjust` 结束它（同一原因）；`plan_id` 为免费套餐时返回 400（`plan_id`、`not_allowed`）；`paid_minor` 为 0；`price_id` 可选，提供时必须属于该套餐，否则返回 400 `invalid_request`（`price_id`、`not_allowed`）。
  - 响应的 `event` 是写在目标权益（或新授予的权益）上的事件；同一事务中写在另一行上的事件（结束后生效的下一段、授予的免费权益、授予时结束的免费权益）在 `related_events` 中返回。
  - `expires_at` 不晚于当前时刻返回 400 `invalid_request`（`expires_at`、`out_of_range`）；要立即结束请改 `status=ended`，按结束规则处理。
  - 修改 `expires_at` 时调整分笔（BIL-20），事件的 `diff.tranches` 给出调整后的完整列表：
    - 延长：追加一笔 `{paid_minor: 0, covers_from: 原 expires_at, covers_to: 新 expires_at}`；
    - 缩短：越过新终点的各笔截到新终点，实付按保留秒数比例向下取整（floor(实付 × 保留秒数 ÷ 原秒数)），完全越过的笔删除；本段实付随之减少，差额不退回；
    - 终点为空的一笔改为有限终点时实付不变；有限终点改为空时追加一笔实付 0、终点为空的笔。
  - 调低 `bytes_limit` 使本周期已用量达到新额度时，状态同时变为 `over_quota`（`suspended` 不变）。
  - 改为 `scheduled` 不允许（请求枚举不含该值）。
- **免费权益授予（free_grant）**：只授予没有当前权益的账号。对已持有当前权益（免费或付费）的账号直接调用授予，返回 409 `invalid_state`，不写事件；对账与 `plan_rollouts` 的 `free_grant` 批次遇到这类账号时跳过，不视为失败。
- **账号注销**（spec/10 AUTH-05）：当前权益（包括免费权益）与下一段在同一事务中结束，每行都写 `expire`，`diff.cause='account_deletion'`；有下一段时两行的 `diff.related_entitlement_id` 互相指向。免费权益没有到期时间，与 `scheduled` 行一样只在这一场景下接受 `expire`（直接变为 `ended`）；其他 `cause` 或不带 `cause` 的 `expire` 作用于 `scheduled` 行时不适用（“—”），下一段只能由结束规则生效或按 BIL-10 取消。下一段不生效、不退回余额（余额随注销作废），也不授予免费权益。
- **临界续费**（spec/12 ORD-06）：支付时当前权益已结束（包括 worker 尚未写入 `expire`，BIL-13）的续费订单，先按到期处理旧行；若结束规则已授予免费权益，则以 `renew` 结束该免费行；再新建一行（事件 `renew`），从支付时刻开始、保留锁定价格。账号此时已持有其他付费当前权益时，场景不成立（ORD-05）。

## 11.7 节点权限

权限链：账号 → 当前权益 → 套餐 → 线路组 → 节点。

- **ACS-01** 节点只接收有权访问它的凭据，条件是同时满足：
  - 账号 `status='active'`；
  - 权益状态为 `active`（包括免费套餐权益，BIL-15；“免费账号”是计费概念，不影响访问判断）；
  - 其套餐包含该节点所属的任一线路组，且套餐 `tier` 不低于该线路组的 `min_tier`（ACS-05）；
  - 凭据未吊销，且未因设备上限被停发（spec/10 AUTH-14）。

  `over_quota` 与 `suspended` 权益的凭据不下发。
- **ACS-02** 权限协调器消费以下主题，计算每个节点上新增与失去的凭据，下发 `CredUpsert` / `CredRemove`（spec/20），并在同一事务中把节点 `config_version` 加 1：`entitlement.changed`、`plan.access_changed`、`location_group.changed`、`node.membership_changed`、`credential.changed`、`account.status_changed`（CONV-22）。
- **ACS-03** 所有下发都幂等；增量结果必须与全量重算一致（性质测试）。每晚执行一次全量对账，并输出差异指标。
- **ACS-04** 节点可设置流量倍率与限速上限；实际限速取套餐快照与节点上限中的较小值。线路组不设倍率与限速。
- **ACS-05** 线路组可设置最低等级 `min_tier`；套餐 `tier` 低于该值时，即使关联也不下发。修改 `min_tier` 写入 `location_group.changed`，修改套餐 `tier` 写入 `plan.access_changed`。
- **ACS-06** 仍被套餐引用、或仍有节点成员的线路组不可删除，删除时返回 409 `invalid_state`。

## 11.8 加购项（M4）

- **BIL-24** 加购项有两种：流量包与额外设备名额。数据库中 `addons.kind` 为 `traffic`、`devices`；对外接口中为 `data`、`devices`（spec/30 API-01）。
  - 以只增不改的 `addon_prices` 表定价，规则同 BIL-01。
  - 报价请求用 `addon_price_id` 指定，场景为 `addon`。
  - 只有权益为 `active` 或 `over_quota` 时可以购买。
- **BIL-25** 加购项挂在当前权益上。
  - 流量包按 BIL-17 消耗，用量由 worker 在落库时按顺序写入 `addons.bytes_used`（spec/22 ACC-18）。
  - 额外设备名额加到设备上限上，随所挂权益一同到期。
  - 升级或立即降级时，未用完、未到期的加购项迁移到新权益，到期时间不变。
  - 加购项不计入剩余价值，可以单独退款：可退金额 = 实付 × 未用比例。

## 11.9 测试要求

- 折算：rapid 性质测试，10 万个随机购买历史，覆盖月、季、年价格与三种重置规则。验证 BIL-11，以及以下价值守恒等式：

  ```
  现金实收 + 余额净支出 = 已消耗价值 + 当前剩余价值 + 余额退回 + 原路退回
  已消耗价值 = Σ 各段 paid_minor × (1 − 结束时的剩余比例)
  ```

  每次操作允许 1 个最小货币单位的取整误差。
- 状态机：逐格测试 11.6 的全部组合，确认没有未定义的转换；覆盖到期前 1 秒、到期瞬间、到期后 1 秒。
- 价格锁定：涨价、降价、下架、到期后再购买、续费改换周期五种情形。
- 权限协调：随机修改套餐、线路组、节点归属、账号状态、设备后，增量与全量结果一致。
