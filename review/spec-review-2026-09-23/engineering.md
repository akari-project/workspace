# 架构与工程组明细：spec/00、01、02、40、41、42、43

核对依据：spec/03、10、11、12、20、21、22、30、31；adr/、backlog/、workflows/、.claude/settings.json、三个子仓库的 settings、scripts/hooks、00001_init.sql、client/v1.yaml、compose.dev.yaml。

编号 E-xx 与主报告一致。每条都经过发现者自我反驳。全部条目都已完成独立对抗复核，结论标在标题后，详见主报告第 3、7、8 节。

---

## 严重

### E-01 加密主密钥的备份、恢复与轮换都没有定义 ｜遗漏｜严重 → 复核后降为重要（见主报告 3.2）
- 位置：spec/02 CONV-19；spec/40 DEP-10
- 原文：「加密主密钥来自环境变量或外部 KMS，不入库」；「加密主密钥与签名私钥不随数据库备份」
- 问题：
  - 规格没有要求单独备份主密钥。
  - 主密钥没有轮换流程；`_enc` 列不带 key id，轮换后无法区分新旧密文。
  - `/v1/config` 签名密钥（客户端内置公钥）与 Agent 发布签名公钥也没有轮换流程。
- 影响：
  - 主密钥丢失：数据库能恢复，但节点 PSK、TOTP、支付宝私钥、代理凭据全部无法解密。
  - 主密钥泄露：无法轮换。
- 建议修改：
  > **CONV-19a** 密文格式为 `key_id(1B) ‖ nonce ‖ ciphertext`。运行时加载当前主密钥与至多一把旧主密钥；`panel keys rotate` 分批重新加密。
  >
  > **DEP-10a** 部署文档要求离线备份主密钥与签名私钥，并与数据库备份分开存放；恢复演练包括用备份的主密钥解密抽样的 `_enc` 列。
  >
  > **DEP-09a** 内置公钥支持「当前 + 下一把」两把；新公钥至少随一个小版本发布之后，才启用对应的新私钥签名。

## 重要

### E-02 对外字段 `traffic_multiplier` 违反 API-01 ｜矛盾｜重要 → 复核后降为一般（见主报告 7.1）
- 位置：spec/00「倍率」；OpenAPI `Location.traffic_multiplier`。与 A-17 合并，与 N-21 相关。
- 问题：
  - 术语表把含禁用词的名称定为接口标识符。
  - 取值是十进制字符串 `"1.50"`，而 ACC-03 规定使用百分比。
- 建议修改：术语表中的对外名称改为 `usage_multiplier_percent`，取整数百分比（150 表示 1.5 倍）；OpenAPI 同步修改。M0-03 增加禁用词 lint，检查路径、属性、枚举值和错误码。

### E-03 已提交的 00001 迁移大面积不符合 CONV-17 ｜矛盾｜重要 → 复核后降为一般（见主报告 8.1）
- 位置：spec/02 CONV-17；00001_init.sql
- 问题：
  - 缺少 `created_at`：settings、roles、account_roles、mfa_totp、export_tokens、kernels、kernel_protocols、node_group_members、plan_groups、usage_cycles、payment_providers、payment_notifications、traffic_hourly、articles。
  - 数据可变但缺少 `updated_at`：sessions、devices、proxy_credentials、inbounds、coupons、redeem_codes、usage_cycles。
  - 有 `updated_at` 但缺少 touch 触发器：settings、payment_providers、articles。
  - 规格没有定义什么是「可变表」。
- 建议修改：
  > **CONV-17** 所有表都有 `created_at timestamptz NOT NULL DEFAULT now()`。除只追加表、分区明细表和纯关联表之外，其余表都视为可变表，必须有 `updated_at` 和 `touch_updated_at` 触发器。

  M0-05 中新增 00002 迁移补齐上述列与触发器；或者在 v0.1 之前允许重写 00001，并记入 ADR。

### E-04 只追加表与「注销后删除个人数据」冲突 ｜矛盾｜重要（复核维持，见主报告 8.1）
- 位置：spec/02 CONV-18；spec/10 AUTH-05
- 问题：
  - `payment_notifications` 中有买家标识，`audit_logs` 中有 IP 前缀，这两张表都禁止 UPDATE，注销时无法删除这些个人数据。
  - 行级触发器挡不住 TRUNCATE。
- 建议修改：
  > **CONV-18a** 只追加表不保存可直接识别个人的明文。个人字段放入可变的关联表，或放入 `_enc` 列：用按账号派生的密钥加密，注销时销毁该密钥，实现加密擦除。另加 `BEFORE TRUNCATE` 语句级触发器禁止 TRUNCATE。

### E-05 幂等键（CONV-12）的语义缺失，表结构不支持匿名请求 ｜遗漏｜重要（复核维持，见主报告 7.1）
- 位置：spec/02 CONV-12；迁移中的 `idempotency_keys`。与 A-23 合并。
- 问题：以下情况都没有定义：
  - 同一个键对应不同请求体；
  - 同一个键的并发请求；
  - 失败响应是否缓存；
  - 匿名请求（主键中的 `account_id` 为 NOT NULL）；
  - 过期记录的清理；
  - 外部回调是否受此约束。
- 建议修改：
  > **CONV-12** 键的作用域为（账号，或匿名 + 路由）+ 键，服务端保存请求体的 SHA-256。
  > - 同一个键、请求体不同：返回 422 `idempotency_key_reused`。
  > - 同一个键的请求正在处理中：返回 409 `conflict` 并附 `Retry-After`。
  > - 只缓存 2xx 和 4xx 响应。
  > - worker 每小时清理超过 24 小时的键。
  > - 外部回调不使用该请求头。
  >
  > 新错误码先加入错误码表。

### E-06 ETag、写入时的版本控制与 409 `conflict` 之间缺少机制 ｜遗漏｜重要 → 复核后降为一般（见主报告 7.1）
- 位置：spec/02 CONV-13、错误码 `conflict`
- 建议修改：
  > **CONV-13** 明确列出带 ETag 的资源：`GET /v1/config`、`/v1/me/configuration`、`/v1/configurations/{token}`，以及管理接口中可修改的单个资源。使用强 ETag。对这些资源的写操作必须带 `If-Match`：缺少时返回 428 `precondition_required`，不匹配时返回 409 `conflict`。

### E-07 错误码表中没有 503；Problem 的 `request_id` 不是必填 ｜矛盾｜重要 → 复核后降为一般（见主报告 7.1）
- 位置：spec/02 CONV-16；spec/40 40.4；spec/20 NODE-07；OpenAPI `Problem`
- 建议修改：
  - 错误码表增加 `service_unavailable | 503 | 依赖故障暂时不可写，附 Retry-After`。
  - `Problem.required` 加入 `request_id`。
  - 为 `errors[].code` 另建一张取值表。

### E-08 outbox 投递失败、丢失与清理都没有定义；通知走了两条路径 ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/02 CONV-22；spec/13 OPS-02；`outbox`、`notification_outbox`。与 A-25 部分合并。
- 影响：`order.paid` 事件丢失时，用户已付款但不会开通。
- 建议修改：
  > **CONV-22a** worker 用 `FOR UPDATE SKIP LOCKED` 按顺序取事件，XADD 成功后再写 `published_at`。Stream 设 `MAXLEN ~ 100000`，消费组以角色命名。消费失败 10 次的事件移入 `events:dead:{topic}` 并告警。每 5 分钟对账：已发布超过 10 分钟但没有 `consumed_events` 记录的事件重新投递。outbox 中的记录保留 7 天。
  >
  > 通知只走 `notification_outbox`，删除 `notification.requested` 主题。

### E-09 站点时区没有定义 ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/02 CONV-03、CONV-02。与 B-21 合并。
- 建议修改：
  > **CONV-03a** 站点时区存于 `settings.site_timezone`（IANA 名称），默认 `Asia/Shanghai`，在初始化时设定。修改时区只影响之后新建的权益，已有权益保存建立时的时区快照。CONV-02 的日期按站点时区计算。遇到夏令时导致本地时刻不存在或重复时，取当日第一个合法时刻。

### E-10 Valkey 不可用时的行为与 ACC-09 矛盾，并漏掉了多项依赖 ｜矛盾｜重要（复核维持，见主报告 8.1）
- 位置：spec/40 40.4；spec/22 ACC-09；spec/20 NODE-09；spec/30 API-04；spec/40 DEP-08。与 N-22 合并。
- 问题：
  - 40.4 写「按配置放行或停止」，ACC-09 写「立即关闭」，两者矛盾。
  - 没有说明以下依赖 Valkey 的功能如何降级：防重放、限流、事件投递、租约锁。
- 建议修改：
  > 续租失败时按 ACC-09 关闭会话，不提供放行选项。网关拒绝新的握手（返回 503），已建立的会话继续。限流改用进程内令牌桶。outbox 在 PostgreSQL 中积压，Valkey 恢复后补投。周期任务改用 PostgreSQL advisory lock。

### E-11 控制面不可用时，没有租约的账号能否接入 ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/40 40.4；spec/22 ACC-08；spec/21 AGT-05。与 N-22 合并。
- 建议修改：
  > **ACC-09a** 节点对没有租约的账号发放本地临时租约，额度不超过 `offline_lease_bytes`（默认 64 MiB），恢复连接后对账。离线超过 `offline_max`（默认 24 小时）后拒绝新连接，已建立的会话继续。两个参数随快照下发。

### E-12 多 worker 下落库任务没有互斥；租约锁没有 fencing ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/40 DEP-08；spec/22 ACC-05。与 N-23 部分合并。
- 建议修改：
  > **DEP-08** 需要单实例执行的任务包括：落库、到期扫描、周期重置、分区维护、对账、幂等键清理。锁使用单调递增的 fencing token，写库时在同一事务中校验并推进 `job_fencing` 表。
  >
  > **ACC-05** 摘取时使用的键为 `dirty:processing:{worker_id}:{batch_id}`。

### E-13 「误差 0 字节」与 ACC-07 相矛盾 ｜矛盾｜重要
- 与 N-24 合并，建议修改见 N-24。

### E-14 高可用目标、故障切换与 RPO/RTO 没有量化 ｜无法测试｜重要 → 复核后降为一般（见主报告 8.1）
- 位置：spec/40 40.1、40.4、DEP-10
- 建议修改：
  > **DEP-11** 多实例部署的目标：月可用性 99.9%，RPO ≤ 1 分钟，RTO ≤ 15 分钟。故障切换使用 Patroni 或同等方案。单机部署只承诺 RPO。
  >
  > **DEP-10** 每周在 CI 中用合成数据做恢复演练，判据为：迁移版本一致；`_enc` 可以解密；余额视图与备份前一致。恢复后执行三项补救：补查支付宝订单、所有节点做一次全量同步、重建 Valkey 用量。

### E-15 控制面升级、迁移回滚与滚动升级兼容没有定义 ｜遗漏｜重要 → 复核后降为一般（见主报告 8.1）
- 位置：spec/02 CONV-21；spec/40 40.5、DEP-01、DEP-03；spec/42 42.5
- 建议修改：
  > **DEP-12** 迁移只由 `panel migrate` 执行；各角色启动时只校验 schema 版本。每个版本的迁移必须与上一个小版本的二进制兼容（扩展—收缩两阶段）。回滚时只回退二进制。「在线执行」指持有 ACCESS EXCLUSIVE 锁不超过 1 秒。
  >
  > **DEP-03a** 嵌入的前端产物保留上一版本的哈希资源；或者在 chunk 加载失败时刷新页面。

### E-16 Agent 自升级（DEP-09）没有量化判据，版本兼容只规定了一个方向 ｜无法测试｜重要 → 复核后降为一般（见主报告 8.1）
- 位置：spec/40 DEP-09；spec/42 ENG-03；spec/41 41.4。与 N-19 部分合并。
- 建议修改：
  > **DEP-09** N 取 5 分钟。每档灰度至少停留 30 分钟，晋级条件为在线率 ≥ 99% 且没有回退，晋级由管理员确认。升级顺序：先控制面，后 Agent。Agent 版本高于控制面时，关闭新增的能力位。签名使用固定密钥（`cosign sign --key`）。

### E-17 缺少 TLS 终止与可信代理的规则 ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/40 40.1；spec/41 41.4
- 影响：部署在反向代理之后时，所有请求的来源 IP 都是代理，按 IP 限流会全部失效；也可以伪造 `X-Forwarded-For`。
- 建议修改：
  > **DEP-13** 默认只监听 HTTP，也可以配置 `tls.acme`。只有来自 `trusted_proxies` 的请求才采信 `X-Forwarded-For`。单机部署时，Caddy 按 Host 把多个域名反代到同一个 `panel all` 端口。

### E-18 「完成的定义」与 CI 要求不一致 ｜矛盾｜重要 → 复核后降为一般（见主报告 8.1）
- 位置：workspace/CLAUDE.md「完成的定义」第 1 条；spec/42 42.2；panel/CLAUDE.md
- 问题：`make test` 只包含单元测试，不含性质测试、端到端测试、静态检查、许可证扫描，也不含 Redocly lint。
- 建议修改：
  - 「完成的定义」第 1 条改为「`make ci` 通过」，其检查项与 42.2 一一对应；涉及 proto 时还要通过 `buf breaking`；涉及 OpenAPI 时还要通过 lint 和破坏性变更检查。
  - 42.2 要求每个仓库都提供 `make ci`。

### E-19 OpenAPI「只增可选字段」没有自动检查 ｜无法测试｜重要 → 复核后降为一般（见主报告 8.1）
- 位置：spec/42 ENG-02；spec/02 CONV-14
- 建议修改：
  > **ENG-02** CI 用 `oasdiff breaking --fail-on ERR` 与上一个 tag 比较。1.0 之前允许破坏性变更，但必须写入 CHANGELOG。

### E-20 billing-adversarial 工作流中的规格路径与代理配置不成立 ｜矛盾｜重要 → 复核后降为一般（见主报告 8.1）
- 位置：workflows/billing-adversarial.md；workflows/README.md；spec/43 43.1、43.6
- 问题：
  - 工作流引用了不存在的 `spec/11-plans-orders-entitlements.md`。
  - 从 `panel/` 启动时，路径应以 `../` 开头。
  - `billing-verifier` 只存在于 workspace 的 `.claude/agents/` 中，从 `panel/` 启动时可能找不到。
- 建议修改：
  - 把路径改为 `../spec/11-plans-entitlements.md` 与 `../spec/12-orders-payments.md`。
  - 43.6 增加要求：在子仓库启动的工作流所用的代理，必须同步放一份到该仓库的 `.claude/agents/`，由 CI 校验内容一致。

### E-21 对抗工作流要求合入失败的测试，会让 CI 变红 ｜矛盾｜重要 → 复核后降为一般（见主报告 8.1）
- 位置：workflows/billing-adversarial.md；spec/42 42.2；「完成的定义」
- 建议修改：
  > 反例测试放入 `//go:build adversarial` 标签下，默认的 `make test` 不包含它。CI 另设非阻塞任务 `make test-adversarial`；问题修复后去掉标签，转为常规测试。

## 一般

### E-22 分页游标的语义不完整 ｜遗漏｜一般 → 复核后降为轻微（见主报告 8.1）
- 建议修改：
  > **CONV-11** 默认 limit 为 50。游标为不透明的 base64url 字符串，由「排序键 + id」编码而成，排序必须稳定。非法游标返回 400。最后一页省略 `next_cursor`。游标不过期。

### E-23 注入时钟与数据库 `now()` 并存 ｜遗漏｜一般（复核维持，见主报告 8.1）
- 建议修改：
  > **CONV-04a** 参与业务判断的时间列必须由应用按注入的时钟显式写入。`DEFAULT now()` 只用于审计性质的 `created_at` 和 `updated_at`。

### E-24 CONV-21 的 CONCURRENTLY 要求在字面上也覆盖了新建表 ｜矛盾｜一般（复核维持，见主报告 8.1）
- 建议修改：注明该要求只适用于给已有数据的表加索引；在同一迁移中新建的表不受限制。

### E-25 SPDX 规则与 shebang、上游文件、CI 覆盖范围冲突 ｜矛盾｜一般（复核维持，见主报告 8.1）
- 问题：
  - 带 shebang 的脚本，第一行无法放 SPDX。
  - workspace 下的脚本本身也没有 SPDX 头。
  - 上游 fork 中的原有文件没有 SPDX 头，也没有登记例外的机制。
- 建议修改：
  > **CONV-25** SPDX 标识位于文件前两行之内。上游文件在 `REUSE.toml` 或 `.spdx-exceptions` 中登记。两个内核 fork 只检查本组织新增的文件。

### E-26 依赖许可证扫描没有允许清单 ｜无法测试｜一般（复核维持，见主报告 8.1）
- 建议修改：
  - Apache 仓库只允许 MIT、BSD、Apache-2.0、ISC。
  - GPL 与 AGPL 仓库另外允许 MPL-2.0、LGPL、GPL-3.0。
  - 禁止 SSPL、BUSL，以及没有许可证的依赖。
  - 例外依赖登记在 `LICENSE-EXCEPTIONS` 中。

### E-27 42.4 的指标不是发版门槛，测量口径也不完整 ｜无法测试｜一般（复核维持，见主报告 8.1）
- 建议修改：
  - 任一指标退化超过 20% 或未达标时，必须在 CHANGELOG 中说明。
  - 补全口径：「处置」以写入 PostgreSQL 为准；内存指 RSS；「收敛」指全部节点 online 且 `config_version` 一致。

### E-28 前端内嵌规则中有几处无法验证 ｜无法测试｜一般（复核维持，见主报告 8.1）
- 建议修改：
  > **DEP-01** 提交号同时写入 `dist/build.json` 和 ldflags，两者不一致时拒绝启动。
  >
  > **DEP-05** 给出完整的 CSP（含 `frame-ancestors 'none'`），并加上 HSTS。
  >
  > **DEP-06** noui 部署也必须保留源代码链接（ARC-04）。

### E-29 架构图缺少 gateway 到 PostgreSQL 的连线；多项职责没有归属 ｜遗漏｜一般（复核维持，见主报告 8.1）
- 建议修改：
  - 架构图增加 `GW --> PG`。
  - gateway 增加职责：接入、租约发放、Lua 入账。
  - worker 增加职责：权限协调器、超额处理。

### E-30 Helm 所在里程碑、Valkey 与 Node.js 版本、Agent 本地存储前后不一致 ｜矛盾｜一般 → 复核后降为轻微（见主报告 8.1）
- AGT-05 部分与 N-16 合并。
- 建议修改：
  - 41.4 改为「Helm Chart（M5）」。
  - 41.1 增加「Valkey 8+」。
  - 41.2 增加「Node.js 22 LTS」。

### E-31 Claude Code 配置与 43.3 的描述不完全一致 ｜矛盾｜一般（复核维持，见主报告 8.1）
- 位置：spec/43 43.3；.claude/settings.json；scripts/hooks/guard-paths.sh
- 问题：
  - 允许规则 `Bash(git status:*)` 匹配不到 CLAUDE.md 要求使用的 `git -C <仓库> status`。
  - hooks 只拦截编辑工具，Bash 命令可以绕过。
  - sqlc 的输出目录没有定义。
- 建议修改：
  - 43.3 的允许清单增加 `git -C * status`、`git -C * diff`、`git -C * log`，把 sqlc 输出目录固定为 `server/internal/db/sqlc/`，并写明 Bash 的写入由 deny 规则与代码审查兜底。
  - 规格改定后再同步修改 settings.json。本次评审不改配置。

### E-32 术语表中「设备」的范围不清，部分术语缺失 ｜遗漏｜一般 → 复核后降为轻微（见主报告 8.1）
- 「设备」部分与 A-01 合并。
- 建议修改：补充以下术语：处置、权限协调器、能力位、配置快照、`config_version`。

### E-33 两个工作流标为「只读」，却要写入报告 ｜矛盾｜一般 → 复核后降为轻微（见主报告 8.1）
- 建议修改：
  - workflows/README.md 改为「只写 `review/`」。
  - 43.1 的目录树中加入 `review/`。

### E-34 core-sync 的测试矩阵包含不支持的组合 ｜矛盾｜一般（复核维持，见主报告 8.1）
- 建议修改：
  - 测试组合取自 spec/21 协议矩阵中「稳定」和「实验」的格子，跳过不支持的组合。
  - 实验格子的失败不阻塞。
  - 加入 XHTTP 与 mKCP。

## 已排除的疑点
- 子仓库 settings 中没有 Agent Teams 环境变量，这正是 43.2 所要求的。
- settings.json 中多出的 `go vet` 是只读命令，无害。
- 43.6 列出的代理与 Skills 和实际一致：代理 10 个，Skill 共 4 + 7 + 2 个。
- 43.2 的工作流列表与 workflows/ 目录一致。
- 43.1 中的 FORK_PLAN 和 UPSTREAM 两个文件由 bootstrap 从 templates 复制生成。
- ENG-03 与 DEP-09 的内容一致。
- CONV-20 用 SHA-256 保存兑换码：兑换码熵约 78 位，足够安全。
- ACC-12 在 Valkey 中存完整地址：CONV-24 只约束日志。
- Valkey 的持久化已经配置。
- PSK 与 PASETO 的轮换已由 NODE-10 和 AUTH-06 覆盖。
- `/v1/accounts` 由 CON-01 按域名或前缀区分。
- ARC-02 目前不构成问题。
- ADR 0002 中的 SDK 许可证是另一份产物，与本项目 SDK 不同；建议在 spec/01 中写明。
- PostgreSQL 主库不可用时登录失败，属于可接受的降级。
- 网关宕机后，Stream 中的指令由重连后的版本同步覆盖。

## 范围外发现
- backlog M0-05 把 webui 的依据写成 spec/41，实际应为 spec/40 的 DEP-01 到 DEP-06。
- backlog M0-03 引用的「第 18.4 节」不存在，应为 spec/31。
