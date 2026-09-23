# 22 流量计量与入账

适用范围：`panel/server/internal/accounting`、`node-agent` 计量与 WAL 部分。

## 22.1 三层数据流

1. **节点**：按凭据计数，定期读出并清零，组成带 `report_seq` 的 `ReportTraffic`，先追加 WAL 再发送，收到确认后截断 WAL。
2. **Valkey**：一次 Lua 脚本调用完成去重、倍率换算、累加、写脏集合、超额判定。
3. **PostgreSQL**：worker 每 30 秒批量落库，是账本。

## 22.2 规则

- **ACC-01** Agent 用 `atomic.SwapUint64` 读出并清零计数器，不丢数。
- **ACC-02** WAL 格式变更必须兼容旧文件；进程重启后先重传 WAL 中未确认的报告。
- **ACC-03** Lua 脚本是唯一入账路径。去重键 `ingest:{node_id}:{report_seq}`（保留 7 天）；计费字节 = 原始字节 × 节点倍率（整数运算，倍率以百分比存储）。
- **ACC-04** 脚本返回达到或超过额度的账号；控制面据此把权益置为 `over_quota`（写权益事件）并由权限协调器移除凭据。
- **ACC-05** worker 用 `RENAME dirty → dirty:processing` 原子摘取脏集合，COPY 到临时表后合并到 `traffic_hourly` 与 `usage_cycles`；整批一个事务，以批次 ID 幂等（`ingest_batches`）。
- **ACC-06** 用量键带周期编号：`usage:{account_id}:{cycle_index}`。周期重置 = 切换到新编号，不做清零。
- **ACC-07** Valkey 开启 AOF（`appendfsync everysec`）与副本。Valkey 数据丢失时，用 PostgreSQL 已落库用量加节点 WAL 中未确认的报告重建。文档须说明极端情况下可能丢失约 1 秒已确认未落盘的增量。

## 22.3 配额租约

- **ACC-08** 账号在某节点建立首个连接时，节点发送 `LeaseRequest`；控制面发放 `clamp(剩余额度 ÷ 活跃节点数, 1 MiB, 256 MiB)`，记为未结算。
- **ACC-09** 节点在计数的同时扣减租约余额；低于 20% 时异步续租；耗尽且续租未批准时立即关闭该账号的全部会话并拒绝新连接，不等待控制面。
- **ACC-10** 流量报告与租约对账；未用完部分在租约过期或账号断开时归还。
- **ACC-11** 最大超额 ≤ 该账号所有未结算租约之和；默认参数下验收上限为 256 MiB。

## 22.4 设备数限制

- 自研客户端：按注册设备精确限制（spec/10 AUTH-14）。
- **ACC-12** 第三方共用凭据：按活跃来源地址估算，IPv4 按单个地址、IPv6 按 /64，活跃窗口 5 分钟（Valkey ZSET）。超限时拒绝新来源的新连接，已有连接不受影响。运营者可关闭或改为仅告警。来源地址只在 Valkey 中保存，不落库。

## 22.5 分区与保留

- **ACC-13** `traffic_hourly` 按月分区，始终预建未来 2 个月；存在 DEFAULT 分区兜底，其中出现数据即告警。
- **ACC-14** 明细汇总到 `traffic_daily` 后，明细默认保留 30 天，以 `DETACH PARTITION … CONCURRENTLY` 后删除。
- **ACC-15** 只记录每凭据每节点的字节数，不记录访问目标。保留期可配置，并在后台显示当前策略。

## 22.6 测试要求

- 混沌测试（`make chaos`）：随机断线、重启网关与 worker、重启 Valkey，最终 PostgreSQL 用量等于节点实际计数总和。
- 重复 `report_seq` 不重复计费；倍率换算正确；租约超额不超过上限。
