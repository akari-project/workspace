# 节点组明细：spec/20、21、22、23

核对依据：spec/00、01、02、03、10、11、30、31、40、42；`panel-spec/proto/node/v1/*.proto`、`panel-spec/openapi/client/v1.yaml`、`panel/server/migrations/00001_init.sql`。

编号 N-xx 与主报告一致。每条都经过发现者自我反驳。全部条目都已完成独立对抗复核，结论标在标题后，详见主报告第 3、7、8 节。

---

## spec/20 节点协议

### N-01 `report_seq` 起点与跨重装延续未定义 ｜矛盾｜严重（复核维持，见主报告 3.1）
- 位置：spec/22 ACC-03；spec/20 NODE-03；spec/21 21.4
- 原文：ACC-03「去重键 `ingest:{node_id}:{report_seq}`（保留 7 天）」；NODE-03「重新签发接入令牌时保留节点 ID」
- 问题：重新接入会保留 `node_id`，但新装的 Agent 没有 WAL，`report_seq` 可能从 1 重新计数，与 7 天内的旧去重键冲突，导致新报告被静默丢弃。另一种情况：节点离线超过 7 天，去重键已过期，已入账但确认丢失的报告重传后会被重复入账。
- 影响：静默少计或多计，违反 42.4「误差 0 字节」。
- 建议修改：
  > **ACC-03a** `report_seq` 在同一节点 ID 下严格递增，永不回退。控制面在 `nodes.last_report_seq` 持久化已入账的最大值，并通过 `HelloAck` 下发，Agent 之后的 `report_seq` 必须大于该值。小于或等于该值、且去重键已过期的报告拒绝入账，同时计入指标 `ingest_stale_total`。WAL 中报告的最长保留时间必须短于去重键的保留期（7 天），超期的报告丢弃并告警。

### N-02 指令乱序：重传的旧版本会复活已移除的凭据 ｜遗漏｜严重 → 复核后降为重要（见主报告 3.2）
- 位置：spec/20 NODE-13、NODE-15；proto `CredUpsert`、`CredRemove`、`InboundApply`、`RoutesApply` 的 `config_version`
- 原文：「发送方保留未确认的信封，重连后重传；接收方以 `idem_key` 去重。所有指令写成幂等形式」
- 问题：幂等不能防止乱序。例如 `CredUpsert(v5)` 未被确认，重连后按版本同步到了 v7（v7 已移除该凭据），此时重传的 v5 到达，凭据会被复活。多实例部署（DEP-07）下，一个实例先发 v8、另一个实例后发 v7，问题相同。规格没有规定 Agent 遇到版本号不大于当前版本的指令时如何处理，也没有规定版本号必须连续。
- 影响：权限被绕过，ACS-01「增量与全量一致」无法保证。
- 建议修改：
  > **NODE-13a** 带 `config_version` 的指令，若其版本号不大于 Agent 当前的 `config_version`，只确认、不应用。控制面在同一事务内为每个节点的版本号单调加 1。Agent 收到的版本号若不等于「当前版本 + 1」，不应用该指令，并请求全量同步。重传的指令保持原 `config_version`。

### N-03 HKDF 与 nonce 构造未定义 ｜遗漏｜重要（复核维持，见主报告 7.1）
- 位置：spec/20 20.3 第 4、5 步；NODE-11；proto `Frame.sealed`
- 问题：HKDF 的 salt 和 info 的字节排列、输出长度、两个方向是否分用密钥、XChaCha20 的 24 字节 nonce 的来源与存放位置、方向字节的取值都没有定义。模拟 Agent 与真实 Agent 无法按规格独立实现并互通。
- 影响：一致性套件缺少字节级依据；nonce 可能被重用。
- 建议修改：
  > **NODE-11a** `K = HKDF-SHA256(ikm=X25519(a,B), salt=hello.nonce, info="node-session-v1"|node_id|agent_pubkey|server_pubkey, L=64)`，前 32 字节用于 Agent→控制面方向，后 32 字节用于控制面→Agent 方向。方向字节：Agent→控制面为 0x01，控制面→Agent 为 0x02。`sealed = nonce(24B 随机) || 密文 || tag`。同一会话内出现重复的 `seq` 即关闭连接。

### N-04 `seq` 作用域、单连接重传、`idem_key` 格式与去重期限未定义 ｜遗漏｜重要（复核维持，见主报告 7.1）
- 位置：spec/20 NODE-12、NODE-13
- 问题：以下几点都没有规定：`seq` 是每次连接重置还是跨连接延续；同一连接内出现空洞时有没有超时重传；`idem_key` 的格式和去重保留时长；Agent 重启后去重记录丢失时，`LeaseRequest`、`AgentUpgrade` 这类不是「设为」型的消息会被重复执行。
- 影响：「断线 100 次后指令不丢不重」无法实现。
- 建议修改：
  > **NODE-12a** `seq` 在一次握手的会话内从 1 开始。重连后，发送方把未确认的信封用新的 `seq` 重发，`idem_key` 保持原值。`idem_key` 为 UUIDv7，接收方至少保留 24 小时去重记录，Agent 侧写入本地持久化存储。同一连接内 30 秒未被确认的信封按原 `seq` 重发。

### N-05 NODE-14 丢弃积压未限定方向；`SyncFull` 无法重建全部状态 ｜遗漏｜重要（复核维持，见主报告 7.1）
- 位置：spec/20 NODE-14；spec/22 ACC-02；proto `SyncFull`
- 原文：「待确认窗口有上限（默认 1,000 条或 8 MiB）；超出时丢弃积压并改发一次全量同步」
- 问题：
  - 规则没有限定方向。若也适用于节点→控制面，丢弃的就是 `ReportTraffic`，节点离线较久时 WAL 很容易超过 1,000 条，与 ACC-02 矛盾。
  - `SyncFull` 不含 `QuotaLease`、`AgentUpgrade` 和 `dns_provider_secret`，丢弃积压后这些状态无法恢复。
- 影响：可能丢账；证书续期可能失败；租约状态不一致。
- 建议修改：
  > **NODE-14** 仅适用于控制面→节点方向。节点→控制面的报告不丢弃，从 WAL 分批重传，每批不超过窗口上限。`SyncFull` 必须能重建节点的全部配置状态，proto 增加 `SyncFull.dns_provider_secret`。丢弃积压后，控制面把该节点的未结算租约全部视为已回收，全量同步完成后按 ACC-08 重新发放。

### N-06 `SyncDelta` 只能表达凭据变化 ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/20 NODE-15；proto `SyncDelta`
- 问题：`config_version` 是入站、路由、内核、凭据共用的计数器，但增量同步只能表达凭据变化。如果中间变更包含入站、路由或内核切换，增量同步无法表达。规格也没有规定控制面保留多少中间变更。
- 影响：版本号已追平，但节点的入站和路由仍是旧的。
- 建议修改：
  > **NODE-15a** 只有当中间变更全部是凭据变化时才可以发 `SyncDelta`，否则发 `SyncFull`。控制面至少保留每个节点最近 24 小时或最近 10,000 个版本的凭据变更。

### N-07 规格要求移除必关会话，proto 的 `close_sessions` 却是可选布尔 ｜矛盾｜重要 → 复核后降为一般（见主报告 7.1）
- 位置：spec/20 20.5 `CredRemove`；proto `CredRemove.close_sessions`；spec/21 AGT-12
- 问题：规格要求移除凭据时关闭会话，契约却允许 `close_sessions=false`，且没有定义其语义。`SyncDelta.removals` 以及全量同步时从快照中消失的凭据，是否关闭会话也没有规定。
- 影响：欠费或被吊销的用户可以保留已建立的连接。
- 建议修改：
  > **NODE-18** 凭据经任何途径被移除（`CredRemove`、`SyncDelta.removals`、全量快照中缺失）时，必须在 1 秒内关闭其全部会话。1.0 之前 `close_sessions` 必须为 true，收到 false 时按 true 处理。

### N-08 PSK 轮换期未定义，与「节点失陷时立即吊销」矛盾 ｜矛盾｜严重 → 复核后降为重要（见主报告 3.2）
- 位置：spec/20 NODE-03、NODE-10；spec/40 40.4；spec/20 20.6
- 问题：轮换期多长、何时清空 `psk_prev_enc` 都没有规定。规格也没有在线轮换消息，20.6 却要求测试 PSK 轮换。节点失陷时，旧 PSK 在「轮换期」内仍然有效。重新接入后，旧 Agent 的会话是否会被踢下线也没有规定。
- 影响：已泄露的密钥可能继续被接受；PSK 轮换的测试无法编写。
- 建议修改：
  > **NODE-10a** 只有管理员发起在线轮换时才保留 `psk_prev_enc`，最长保留 24 小时，或在新 PSK 首次握手成功后立即清空。重新接入与失陷吊销不保留旧 PSK：在写入新 PSK 的同一事务中清空旧 PSK，并立即断开用旧 PSK 建立的会话。在线轮换通过新增消息 `PskRotate` 完成，需要能力位。

### N-09 校验失败或应用失败时没有回报途径 ｜遗漏｜重要 → 复核后降为一般（见主报告 7.1）
- 位置：spec/20 20.5、NODE-15
- 问题：快照校验失败、`CredUpsert` 应用失败、内核切换失败时，Agent 应如何处理没有规定；节点→控制面方向也没有「请求全量同步」或「执行失败」的消息。
- 影响：节点卡在错误状态，控制面却以为已经同步。
- 建议修改：
  > **NODE-19** 校验或应用失败时，Agent 保留原配置，发送 `SyncRequest{reason, config_version}`，控制面收到后下发 `SyncFull`。同一节点连续失败 3 次，置为 `offline` 并告警。proto 增加该消息，需要能力位。

### N-10 接入接口没有契约；机器模式无法表达 ｜遗漏｜重要（复核维持，见主报告 7.1）
- 位置：spec/20 NODE-02、20.1；spec/21 21.1；迁移中的 `machines` 表
- 问题：
  - `POST /v1/enrollments` 与 `POST /v1/sync` 在 panel-spec 中没有契约，违反 ARC-01。
  - 接入令牌作废后如果响应丢失，Agent 无法重试。
  - 机器模式下一条连接要对应多个节点，但握手只带一个 `node_id`，信封里也没有 `node_id`。
- 建议修改：
  > **NODE-02a** 接入接口的请求与响应定义在 `enrollment.proto` 中。首次成功后 10 分钟内，以相同主机指纹重复提交返回相同结果。
  >
  > **NODE-02b** 机器模式下接入与握手以 `machine_id` 进行，信封增加 `node_id` 字段。若 1.0 不支持机器模式，在 21.1 中写明。

### N-11 长轮询备用通道的帧分隔与会话关联未定义 ｜遗漏｜重要 → 复核后降为一般（见主报告 7.1）
- 位置：spec/20 NODE-06
- 问题：请求体中 Frame 序列的分隔方式、多次 POST 之间如何关联同一个会话密钥、多实例部署时请求落到其他网关实例怎么办，都没有规定。
- 影响：备用通道无法实现。
- 建议修改：
  > **NODE-06a** 请求体与响应体由多个 `uint32 大端长度 || Frame` 组成。首个请求只含 `hello`，响应含 `hello_ack`，并在 `Session-Id` 头中返回会话 ID。后续请求带上该头。会话状态存放在 Valkey 中（TTL 60 秒），任何网关实例都能取用。

### N-12 「确定性序列化」不是规范序列化，新增能力字段会破坏 MAC ｜遗漏｜重要 → 复核后降为一般（见主报告 7.1）
- 位置：spec/20 20.3；proto `Hello.mac`、`SyncFull.checksum`
- 问题：protobuf 的确定性序列化在不同版本、不同语言之间不保证一致，遇到未知字段也不稳定。旧网关重新序列化新 Agent 发来的能力字段后，得到的 MAC 输入与 Agent 不同。
- 影响：违反 ENG-03 的向后兼容要求。
- 建议修改：
  > **NODE-08a** `Hello` 增加 `bytes capabilities_raw`，MAC 覆盖这段原始字节，网关不重新序列化。`SyncFull.checksum` 同样覆盖原始字节，并在 proto 注释中写明字段的拼接顺序。

### N-13 握手失败没有关闭码，`proto_version` 协商未定义 ｜遗漏｜一般（复核维持，见主报告 7.1）
- 位置：spec/20 20.3
- 问题：握手失败时 Agent 无法区分失败原因，只能无限重连；两个 PSK 并存时 `HelloAck.mac` 用哪一个也没有规定。
- 建议修改：
  > **NODE-08b** 握手失败时按原因使用关闭码：4001 时钟偏差，4002 MAC 或 PSK 无效，4003 协议版本不支持，4004 重放。长轮询返回对应的 problem+json。Agent 收到 4002 后指数退避，上限 1 小时；收到 4003 后停止重连。`HelloAck.mac` 使用验证成功的那个 PSK。

### N-14 心跳与节点状态转换无法测试 ｜无法测试｜重要 → 复核后降为一般（见主报告 8.1）
- 位置：spec/20 20.1
- 问题：「心跳」指 WebSocket Ping 还是 `ReportStatus` 没有定义；`ReportStatus` 的发送频率没有规定；「入站就绪」的判据没有给出；状态转换不完整。
- 建议修改：
  > **NODE-20** 心跳指控制面收到该节点的任意有效信封。Agent 每 30 秒发送一次 `ReportStatus`。状态转换规则：
  > - `pending_config` → `online`：至少一个启用的入站处于 `listening=true`；
  > - `online` → `offline`：90 秒内无心跳；
  > - `offline` → `online`：恢复心跳，且至少一个入站就绪；
  > - `maintenance`：只能由管理员设置和解除。

### N-15 同一 `node_id` 同时存在两条连接 ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/20；spec/40 DEP-07
- 问题：`node:{id}:gw` 会被后来的连接覆盖，之后指令只发往其中一条连接，而两条连接都会上报流量。
- 建议修改：
  > **NODE-21** 同一 `node_id` 最多保持一条已认证会话。新会话握手成功后，旧会话以关闭码 4005 关闭，其未确认的指令转交给新会话。

## spec/21 节点 Agent

### N-16 AGT-05「本地只保存」与实际持久化内容矛盾；快照没有加密要求 ｜矛盾｜一般（复核维持，见主报告 8.1）
- 位置：spec/21 AGT-05、21.4；spec/41 41.3。与 E-30 重复，已合并。
- 问题：AGT-05 说本地只保存少量内容，但 Agent 实际持久化了快照、WAL 与租约。快照中含全部凭据，规格对其文件权限和加密都没有要求。
- 建议修改：
  > **AGT-05** 本地持久化控制面地址、节点密钥、最后快照、WAL 与租约状态。快照使用由 PSK 派生的密钥做 AEAD 加密。这些文件的权限为 0600，所在目录为 0700。

### N-17 内核切换失败、`InboundApply` 的语义、能力校验未定义 ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/21 AGT-07、AGT-09
- 建议修改：
  > **AGT-07a** `InboundApply` 采用全量替换语义。内核切换失败时回退到原内核与原入站，并通过 `ReportStatus` 上报。
  >
  > **AGT-09a** 目标内核必须出现在节点最近一次上报的 `Capabilities.kernels` 中。从未上报过能力的节点只做基线校验。

### N-18 XHTTP、mKCP 等传输没有基线校验 ｜遗漏｜一般（复核维持，见主报告 8.1）
- 位置：spec/21 21.2；迁移中的 `kernel_protocols`
- 问题：传输方式存放在 `settings_json` 中，不经过触发器和 AGT-09 的校验。sing-box 节点配置 XHTTP 时，要到下发后才会失败。
- 建议修改：
  > **AGT-09b** 新增 `kernel_transports(kernel, transport, status)` 表，由触发器按 `settings->>'transport'` 校验。`Capabilities.KernelSupport` 增加 `transports` 字段。

### N-19 「计量误差为 0」没有计量口径 ｜无法测试｜一般（复核维持，见主报告 8.1）
- 位置：spec/21 AGT-12
- 问题：没有说明计的是哪一层的字节。DEP-09 的 N 未取值，这一部分与 E-16 合并。
- 建议修改：
  > **AGT-12** 计量口径为解密后的代理载荷字节，不含 TLS、QUIC 与协议头。测试时用已知大小的载荷逐个协议验证，计数必须完全相等。

## spec/22 流量计量与入账

### N-20 用量键按账号区分，升级后新权益会继承旧用量 ｜矛盾｜严重（复核维持，见主报告 3.1）
- 位置：spec/22 ACC-06；迁移中的 `usage_cycles` 主键 `(entitlement_id, cycle_index)`；spec/11 升级规则
- 问题：Valkey 中的键是 `usage:{account_id}:{cycle_index}`。新权益的周期编号从 0 开始，会与旧权益的 `usage:{acct}:0` 冲突，旧用量被带进新权益，与「升级后获得全额流量」矛盾。worker 落库时也无法判断这些用量属于哪一个权益。
- 建议修改：
  > **ACC-06** 用量键改为 `usage:{entitlement_id}:{cycle_index}`。另维护 `acct:{account_id}:current → {entitlement_id, cycle_index, bytes_limit}`，由开通、周期重置、到期的事务通过 outbox 更新。

### N-21 倍率的类型、取整方式、线路组倍率未定义 ｜矛盾｜重要（复核维持，见主报告 8.1）
- 位置：spec/22 ACC-03；迁移中的 `nodes.traffic_multiplier numeric(4,2)`；spec/11 ACS-04。与 A-17、E-02 相关。
- 问题：规格说倍率存为整数百分比，迁移却用 numeric。线路组没有倍率列，节点属于多个线路组时取哪一个也没有规定。按条目向下取整会产生累积损失。
- 建议修改：
  > **ACC-03** 倍率存为 `traffic_multiplier_pct int`，100 表示 1 倍。计费字节 = floor(raw × pct / 100)，按每个 TrafficItem 计算，使用报告到达时的倍率。「零误差」判据针对原始字节，计费字节允许每项有 1 字节的取整误差。线路组不设倍率，或规定取最大值。

### N-22 租约的额度扣减、替换与归还、离线策略未定义 ｜遗漏｜重要（复核维持，见主报告 7.1）
- 位置：spec/22 ACC-08 至 ACC-11；spec/42 42.4。离线策略部分与 E-10、E-11 合并。
- 问题：
  - 「剩余额度」是否扣除其他节点上未结算的租约没有规定。不扣除时，5 个节点同时持有租约，超额可达 1,280 MiB，与 256 MiB 的验收值不符。
  - 没有归还租约的消息，也没有投递丢失时的纠正办法。
  - 首个连接到来时如何放行没有规定；离线策略没有配置项名称。
- 建议修改：
  > **ACC-08** 剩余额度 = 周期额度 + 流量包 − 已入账用量 − 其他节点的未结算租约。活跃节点数按 5 分钟内的报告计，至少为 1。租约默认有效期 10 分钟，新租约替换同一节点上的旧租约，`LeaseRequest` 用 `idem_key` 去重。
  >
  > **ACC-10** `TrafficItem` 增加 `lease_id` 与 `lease_remaining_bytes`；到期未上报的租约按全额计为已用。
  >
  > **ACC-09a** 没有租约的首个连接先放行，上限 1 MiB；5 秒内未获批准则关闭连接。离线时由 `quota.offline_policy` 决定，默认 `deny`。

### N-23 额度同步、流量包入账、迟到报告、worker 崩溃恢复未定义 ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/22 ACC-03 至 ACC-05；spec/11 BIL-17；迁移中的 `addons.bytes_used`。worker 并发部分与 E-12 合并。
- 建议修改：
  > **ACC-04a** Valkey 中的 `quota:{entitlement_id}` 通过 outbox 同步。worker 按 BIL-17 的规定写入 `addons.bytes_used`。账号已处于 `over_quota` 时不重复写事件。
  >
  > **ACC-05a** 迟到的报告按到达时的映射入账；映射已不存在时，只写入 `traffic_hourly` 的原始字节。
  >
  > **ACC-05b** worker 启动时若发现上一批 `dirty:processing` 未处理完，先完成该批再继续。`batch_id` 在 RENAME 之前用 `SET NX` 生成。脏集合保存按小时的增量。

### N-24 「误差 0 字节」与 ACC-07 允许丢失约 1 秒数据相矛盾；重建会重复计费 ｜矛盾｜重要（复核维持，见主报告 8.1）
- 位置：spec/22 ACC-07、22.6；spec/42 42.4。与 E-13 合并。
- 问题：Valkey 被强杀时可能丢失约 1 秒数据；AOF 与副本同时丢失时，最多丢失 30 秒以上。重建时 `ingest:*` 去重键一并丢失，WAL 中的报告会被再次入账。
- 建议修改：
  > **ACC-07** 分两种场景：`SHUTDOWN SAVE` 要求零误差；kill -9 允许丢失不超过 1 秒，并在测试报告中单列。重建时，根据 `ingest_batches` 记录的 `(node_id, max_report_seq)` 恢复去重水位，低于水位的报告不再入账。

### N-25 DEFAULT 分区与 `DETACH … CONCURRENTLY` 不能同时使用 ｜矛盾｜重要 → 复核后降为一般（见主报告 8.1）
- 位置：spec/22 ACC-13、ACC-14
- 问题：PostgreSQL 不允许在带 DEFAULT 分区的表上执行 DETACH CONCURRENTLY。另外，按月分区时实际保留期在 30 到 61 天之间，不是正好 30 天。
- 建议修改：
  > **ACC-14** 以整月分区为删除单位，实际保留期为 [保留期, 保留期 + 1 个月)。使用非并发的 DETACH 加 DROP，锁等待超时 5 秒，超时后重试。或者去掉 DEFAULT 分区，改为在写入失败时告警。

### N-26 设备数限制（ACC-12）无法在节点上执行 ｜遗漏｜严重 → 复核后降为重要（见主报告 3.2）
- 位置：spec/22 ACC-12；proto `Credential`、`TrafficItem.source_prefixes`
- 问题：活跃来源集合存放在控制面，而拒绝新连接的动作发生在节点上。现有协议中没有任何字段或消息能把上限传给节点。跨节点汇总的延迟、共用凭据如何计数，也没有规定。
- 建议修改：
  > **ACC-12a** `Credential` 增加 `max_sources` 字段。新增消息 `SourceAllowlist{credential_id, prefixes, version}`，需要能力位。节点据此拒绝新来源。汇总延迟不超过 35 秒。共用凭据的上限 = 权益设备上限 − 已注册设备数，最小为 1。

## spec/23 第三方客户端配置导出

### N-27 ETag 不含用量；版本号的递增条件未定义；`no-store` 与 304 冲突 ｜矛盾｜重要（复核维持，见主报告 8.1）
- 位置：spec/23 EXP-04、EXP-05、EXP-07；spec/42 42.4
- 建议修改：
  > **EXP-04a** 明确账号状态版本与节点拓扑版本的递增条件。Valkey 只缓存响应体，`Subscription-Userinfo` 在每次请求（包括 304）时用实时的计费字节生成。`Cache-Control` 改为 `private, no-cache`。

### N-28 导出缓存以明文存放在 Valkey ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/23 EXP-07；spec/02 CONV-19
- 建议修改：
  > **EXP-07a** 导出缓存使用主密钥派生的密钥做 AEAD 加密，TTL 不超过 1 小时。导出令牌重置或共用凭据吊销时同步删除缓存。

### N-29 不兼容的入站是否剔除、非 active 账号返回什么，都未定义 ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/23 EXP-02、EXP-03、EXP-06；spec/30 API-09
- 建议修改：
  > **EXP-06** 权益状态不是 `active` 的账号（免费、`over_quota`、`suspended`）返回不含节点的配置。
  >
  > **EXP-03a** 适配器跳过目标客户端不支持的入站，包括 mihomo 格式下 Xray v26.7.11+ 的 Reality 入站，以及 AnyTLS+Reality，并用 golden 测试覆盖。

### N-30 OpenAPI 缺少 304、302、429、响应头与格式默认值 ｜矛盾｜一般（复核维持，见主报告 7.1）
- 位置：spec/23；OpenAPI `/v1/configurations/{token}`
- 建议修改：OpenAPI 补充 304、302、429 响应，补充 `ETag`、`Subscription-Userinfo`、`Profile-Update-Interval` 三个响应头，按格式区分媒体类型，`format` 参数设 `default: auto`。

### N-31 限流数值与 UA 识别表缺失 ｜无法测试｜一般（复核维持，见主报告 8.1）
- 位置：spec/23 EXP-01、EXP-02
- 建议修改：
  > **EXP-01a** 每个令牌每分钟 30 次，每个 IP 每分钟 60 次，无效令牌也计入。
  >
  > **EXP-02a** 附录列出 UA 映射：sing-box、SFA、SFI → singbox；clash、mihomo、Stash → mihomo。UA 为 `Mozilla/` 开头且 `Accept` 含 `text/html` 时视为浏览器。

## 已排除的疑点
- NODE-08 的 60 秒与 NODE-09 的 180 秒并不冲突：nonce 保留 180 秒，已覆盖 ±60 秒的窗口。
- HelloAck 的 MAC 虽然不覆盖 Hello 的 nonce，但覆盖了每次新生成的临时公钥，无法重放。
- 会话密钥不混入 PSK 没有问题：临时公钥已经过 PSK MAC 认证。
- `expires_at_ms` 依赖节点时钟，但握手限定偏差在 ±60 秒以内，影响有上限。
- 独立模式不需要进入协议。
- ACC-12 允许在 Valkey 中保存完整地址；CONV-24 约束的是日志。
- 协议矩阵与 `kernel_protocols` 的种子数据一致。
- 「不丢不重」应理解为效果上不重复，与幂等的要求一致。
- 重连收敛已有判据：42.4 规定 P99 < 60 s。
- `Capabilities.protocols` 是冗余字段，不构成矛盾。
- singflight 的键中重复包含 format，无害。
