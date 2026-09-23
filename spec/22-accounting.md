# 22 流量计量与入账

适用范围：`panel/server/internal/accounting`、`node-agent` 计量与 WAL 部分。

## 22.1 三层数据流

1. **节点**：按凭据计数，定期读出并清零，组成带 `report_seq` 的 `ReportTraffic`；先追加 WAL 再发送，收到确认后截断 WAL。
2. **Valkey**：一次 Lua 脚本调用完成去重、倍率换算、累加、写脏集合、超额判定。
3. **PostgreSQL**：worker 每 30 秒批量落库，是账本。

## 22.2 规则

- **ACC-01** Agent 用 `atomic.SwapUint64` 读出并清零计数器，不丢数。
- **ACC-02** WAL 格式变更必须兼容旧文件；进程重启后，先重传 WAL 中未确认的报告。WAL 中的报告最多保留 6 天，超过的丢弃并告警（保留期必须短于 ACC-03 去重键的 7 天）。
- **ACC-03** Lua 脚本是唯一的入账路径。
  - **去重**：去重键为 `ingest:{node_id}:{report_seq}`，保留 7 天。
    - `report_seq` 在同一节点 ID 下严格递增，永不回退，包括 Agent 重启、重装、重新接入之后；Agent 把计数器持久化到本地状态（spec/21 AGT-05）。
    - 控制面在落库事务中，把每个节点已入账的最大 `report_seq` 写入 `nodes.last_report_seq`，并在 `HelloAck` 中下发（spec/20 20.3）。新装的 Agent 从该值加 1 开始计数。
    - `report_seq` 不大于 `nodes.last_report_seq` 且去重键已过期的报告，确认但不入账，计入指标 `ingest_stale_total`。
  - **倍率**：数据库中节点倍率为 `numeric(4,2)`，Lua 中以整数百分比表示（倍率 × 100）。计费字节 = floor(原始字节 × 百分比 ÷ 100)，按每个 `TrafficItem` 计算，使用报告到达时的倍率。“误差为 0”的判据针对原始字节；计费字节允许每项有不超过 1 字节的取整差。
  - **归属**：Valkey 中维护 `cred:{credential_id} → account_id` 与 `acct:{account_id}:current → {entitlement_id, cycle_index, 额度}`，由开通、周期重置、到期、凭据变更经 outbox 更新。报告按到达时的映射入账。映射不存在（凭据已吊销、权益已结束）时，只累加原始字节写入 `traffic_hourly`，不计入任何周期。
- **ACC-04** 超额判定：
  - 额度保存在 `quota:{entitlement_id}` 中（周期额度与各流量包剩余量），由开通、加购、周期重置事件经 outbox 同步。
  - 脚本返回本次达到或超过额度的账号。控制面把权益置为 `over_quota`（事件 `quota_exhausted`），由权限协调器移除凭据。
  - 已处于 `over_quota` 的账号不重复写事件。
- **ACC-05** 落库：
  1. worker 为每一批生成 `batch_id`，用 `RENAME dirty → dirty:processing:{batch_id}` 原子摘取脏集合。键名不固定，不会覆盖尚未处理完的批次。
  2. 把数据 COPY 到临时表后，合并到 `traffic_hourly`、`usage_cycles`，并按 BIL-17 的顺序更新 `addons.bytes_used`。
  3. 整批在一个事务中完成，以 `batch_id` 幂等（`ingest_batches`）；提交后删除对应的键。
  - 脏集合保存按小时区分的增量。
  - worker 启动时，先处理残留的 `dirty:processing:*`，再摘取新批次。
  - 落库由单实例执行（spec/40 DEP-08）。
- **ACC-06** 用量键按权益区分并带周期编号：`usage:{entitlement_id}:{cycle_index}`。周期重置就是切换到新编号，不做清零。新权益的周期编号从 0 开始，与同一账号的旧权益互不影响。
- **ACC-07** Valkey 开启 AOF（`appendfsync everysec`）与副本。数据丢失分三种情况：
  - 正常重启（`SHUTDOWN SAVE`）：不丢数，混沌测试要求误差为 0。
  - 主节点被强杀：可能丢失约 1 秒已确认的增量；混沌测试中单独统计，要求不超过 1 秒峰值入账量。
  - AOF 与副本同时丢失：用 PostgreSQL 已落库的用量，加节点 WAL 中未确认的报告重建。去重水位取 `nodes.last_report_seq`，不大于水位的报告不再入账。已确认、尚未落库的增量（最多一个落库周期加积压）会丢失。

  部署文档必须说明以上三种情况。

## 22.3 配额租约

- **ACC-08** 发放：
  - 账号在某节点建立首个连接时，节点发送 `LeaseRequest`。
  - 控制面发放 `clamp(剩余额度 ÷ 活跃节点数, 1 MiB, 256 MiB)`，记为未结算，默认有效期 10 分钟。
    - 剩余额度 = 周期额度 + 流量包剩余量 − 已入账用量 − 该账号在其他节点上的未结算租约之和。
    - 活跃节点数 = 该账号 5 分钟内持有租约或有流量报告的节点数，至少为 1。
  - 在同一节点上，新租约替换旧租约：`LeaseRequest` 携带 `current_lease_id` 与旧租约的剩余字节，控制面据此结算旧租约。`LeaseRequest` 以 `(account_id, current_lease_id, is_release)` 幂等。
  - 在租约获批之前，首个连接可以先放行，最多使用 1 MiB；5 秒内未获批即关闭该连接。
  - 节点收到全量同步（spec/20 NODE-14）后，为仍有连接的账号重新申请租约。
- **ACC-09** 执行：节点在计数的同时扣减租约余额；余额低于 20% 时异步续租；耗尽且续租未获批时，立即关闭该账号的全部连接，并拒绝新连接，不等待控制面。
- **ACC-10** 结算：
  - 账号在该节点的最后一条连接关闭时，节点发送带释放标志的 `LeaseRequest`，引用该节点上最新的 `lease_id` 并报告剩余字节；控制面结算并释放，回复 `QuotaLease{bytes = 0}`。只在控制面声明 `supports_lease_release` 时发送，否则等租约过期。
  - 租约过期未续的，过期时释放。
  - 实际用量以流量报告为准。
- **ACC-11** 最大超额：
  - 在线时：超额 ≤ max(0, 该账号未结算租约之和 − 剩余额度)。按 ACC-08 发放时，这个值不超过“活跃节点数 × 2 MiB”，即每个节点的租约下限与首连临时额度各 1 MiB。
  - 离线临时租约（ACC-19）另计。
  - 验收上限为 256 MiB（spec/42 42.4，单位为 MiB）。
- **ACC-19** 控制面不可达时的离线行为：
  - 适用条件：Agent 无法连上控制面，或网关因 Valkey 不可用而无法发放租约（spec/40 40.4）。
  - 已有租约照常执行。没有租约的账号，节点在本地发放临时租约，每个账号不超过 `offline_lease_bytes`（默认 64 MiB）。
  - 连续离线超过 `offline_max`（默认 24 小时）后，拒绝新连接，已有连接继续。
  - 两个参数随 `SyncFull` 下发。
  - 恢复连接后，临时租约的用量随流量报告对账。

## 22.4 设备数限制

- 自研客户端：按注册设备精确限制（spec/10 AUTH-14）。
- **ACC-12** 第三方共用凭据（M4-06）：
  - 按活跃来源地址估算：IPv4 按单个地址，IPv6 按 /64，活跃窗口 5 分钟。来源地址只在 Valkey（ZSET）与节点内存中保存，不落库。
  - 上限 = 权益设备上限 − 已注册的非 web 设备数，最小为 1。
  - 执行：
    - 控制面在 `Credential.max_sources` 中下发上限（0 表示不限）；
    - 声明了能力位 `supports_source_limit` 的节点，还会收到全局活跃来源集合 `SourceSet{credential_id, prefixes, version}`，汇总延迟不超过 35 秒。
    - 节点在本地活跃来源与全局集合的并集达到上限时，拒绝新来源的新连接，已有连接不受影响。
  - 策略由设置项 `shared_credential_source_limit` 决定，取值为 `enforce`、`warn`、`off`，默认 `enforce`。没有声明 `supports_source_limit` 的节点无法执行限制，按 `warn` 处理，后台节点页显示提示。

## 22.5 分区与保留

- **ACC-13** `traffic_hourly` 按月分区，始终预建未来 2 个月。存在 DEFAULT 分区兜底，其中出现数据即告警。
- **ACC-14** 明细汇总到 `traffic_daily` 之后才能删除。以整月分区为删除单位：分区内的全部数据都早于“当前时间 − 保留期”时才删除，因此实际保留期在 [保留期, 保留期 + 1 个月) 之间。删除时使用非并发的 `DETACH PARTITION` 与 `DROP`：表上有 DEFAULT 分区，不能使用 CONCURRENTLY。在低峰期执行，锁等待超时 5 秒，超时则稍后重试。
- **ACC-15** 只记录每账号、每节点、每小时的原始与计费字节数，不记录凭据级明细与访问目标。明细默认保留 30 天，汇总默认保留 13 个月，可以配置，并在后台显示当前策略。
- **ACC-18** 流量包用量由 worker 在落库时写入 `addons.bytes_used`：周期额度用完后，按到期时间从早到晚依次扣减（spec/11 BIL-17）。

## 22.6 测试要求

- 混沌测试（`make chaos`）：随机断线，重启网关与 worker，正常重启与强杀 Valkey；最终 PostgreSQL 用量与节点实际计数总和的差，按 ACC-07 的情况分别判定。
- 重复 `report_seq` 不重复计费；Agent 重装后的报告不被误判为重复；倍率换算正确；升级后新权益从 0 开始计量。
- 租约：5 个节点并发满速时，超额不超过 ACC-11 的上限；控制面离线时按 ACC-19 执行。
