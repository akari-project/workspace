# 40 部署、高可用与降级

适用范围：`panel/deploy`、`panel/server/internal/webui`、`node-agent` 安装。

## 40.1 部署形态

| 形态 | 组成 | 适用 |
|---|---|---|
| 单机 | 一个 `panel all` 二进制 + PostgreSQL 18 + Valkey；可选 Caddy 负责自动 HTTPS | 几百到几千用户；`docker compose up` 10 分钟内完成 |
| 多实例 | api、gateway、worker 分别扩容；PostgreSQL 主从 + WAL 归档；Valkey 主从 + Sentinel | 更大规模（M5 提供 Helm Chart） |

- **DEP-13** TLS 与真实客户端 IP：
  - `panel` 默认只监听 HTTP，TLS 由前置代理终止；也可以配置 `tls.acme`，由内置的 certmagic 签发证书。gateway 域名必须通过 TLS 提供（spec/20 NODE-05）。
  - 只有来自 `trusted_proxies`（CIDR 列表，默认为空）的请求，才采信 `X-Forwarded-For`；其他请求一律使用 TCP 对端地址。按 IP 限流与记录 IP 前缀都以此为准。
  - 单机的 Compose 模板中，Caddy 按 Host 把主域名、`console.` 与 `gateway.` 都反向代理到同一个 `panel all` 端口。
  - 前置代理的访问日志不得记录路径中含令牌的请求的实际路径（`/v1/configurations/*`、`/v1/device-links/*`）。模板中的 Caddy 配置对这些路径只记录路由模板（CONV-24）。

## 40.2 前端内嵌

- **DEP-01** 用户中心与管理后台的构建产物通过 Go `embed` 编进 `panel`。`make build` 依次执行：`pnpm -r build` → 复制到 `server/internal/webui/dist/{portal,admin}` → `go build`。
  - 构建时把 git 提交写入 `dist/build.json`，二进制通过 `-ldflags` 写入同一提交。
  - 两者不一致时拒绝启动，CI 测试这一行为。
- **DEP-02** 按 Host 或路径前缀（配置项）分别提供两个应用；未命中静态文件时回退到对应的 `index.html`。
- **DEP-03** 带哈希的资源使用 `Cache-Control: public, max-age=31536000, immutable`，`index.html` 使用 `no-cache`；构建时预压缩 br 与 gzip。升级后，旧页面加载的分块可能已不存在，前端在分块加载失败时刷新 `index.html`（spec/32 UI-06）。
- **DEP-04** 返回 `index.html` 时注入运行时配置：站点名称、接口地址、源代码链接、CSP nonce。
- **DEP-05** 两个应用都返回以下安全头：
  - `Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-{n}'; style-src 'self' 'nonce-{n}'; img-src 'self' data:; connect-src 'self' {接口地址}; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`
  - `X-Frame-Options: DENY`
  - `X-Content-Type-Options: nosniff`
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `Strict-Transport-Security: max-age=31536000`（通过 TLS 访问时）
- **DEP-06** `-tags noui` 构建不含前端的二进制。开发时使用 Vite 开发服务器，不依赖嵌入产物。`noui` 部署中，运营者自行托管的前端必须保留页脚的源代码链接（spec/01 ARC-04），部署文档说明这一点。

## 40.3 多实例下的指令路由与周期任务

- **DEP-07** 指令路由：
  - 节点完成握手后，网关以比较并写入的方式写入 `node:{id}:gw = <网关ID>:<会话代次>`，带 TTL，随心跳续期；只有持有当前代次的网关可以续期（spec/20 NODE-21）。
  - 任意实例把指令发布到 Valkey Stream `gw:{网关ID}`，目标网关转发，节点确认后再确认 Stream。
  - Stream 中含凭据的指令按 CONV-19 加密。
  - 网关宕机时，由节点重连后的版本同步兜底。
- **DEP-08** 以下周期任务在多实例部署中只由一个实例执行：流量落库、到期扫描、周期重置、分区维护、outbox 投递与对账、支付查询兜底、全量权限对账、幂等键清理。
  - 使用 Valkey 租约锁；锁的值是单调递增的 fencing token。任务写 PostgreSQL 时，在同一事务中校验并推进 `job_fencing(job, token)`，发现 token 过期即中止。
  - Valkey 不可用时，改用 PostgreSQL advisory lock 选出执行者。

## 40.4 故障降级

| 故障 | 行为 |
|---|---|
| 控制面全部不可用 | 节点按最后快照服务，租约与到期继续生效，新连接按 spec/22 ACC-19 使用离线临时租约，报告写 WAL；自研客户端用缓存配置连接 |
| Valkey 不可用 | 配置接口降级为直接查库（有并发上限）；网关拒绝新握手（`hello_reject(busy)`），已建立的会话继续；报告暂不确认，留在 WAL；租约无法发放，节点按 ACC-19 处理；限流改用各实例的进程内令牌桶（每实例上限 = 正常值 ÷ 实例数）；outbox 在 PostgreSQL 中积压，恢复后补投，开通与权限协调随之延迟；周期任务改用 PostgreSQL advisory lock（DEP-08） |
| PostgreSQL 主库不可用 | 用量在 Valkey 中继续累积，落库重试并告警；写接口返回 503 `service_unavailable`，读接口切换到从库 |
| 单个网关宕机 | 节点重连到其他实例，并按版本收敛 |
| 节点失陷 | 按 spec/20 NODE-19 立即吊销该节点密钥，并关闭其全部会话；轮换曾下发到该节点的全部凭据（`credential.changed`）；自研客户端自动取得新凭据，第三方用户需要重新拉取配置 |
| 支付宝通知丢失 | 查询兜底（spec/12 PAY-07） |

## 40.5 升级与备份

- **DEP-09** Agent 自升级：
  - Agent 二进制由发布流程用固定的 Ed25519 密钥签名，签名输入为 `"akari-agent-upgrade-v1" | version | sha256`，其中 `sha256` 为制品的 32 字节摘要，作为字节串按 `|` 的规则加 4 字节长度前缀（编码见 panel-spec `envelope.proto` 文件头），`AgentUpgrade` 带签名 `key_id`。容器镜像与 SBOM 另用 cosign 签名（spec/41 41.4）。Agent 内置“当前”与“下一把”两个公钥：换钥时，先随一个版本发布新公钥，至少过一个小版本后才启用新私钥签名。
  - 灰度按 1% → 10% → 100% 推进。每档至少停留 30 分钟，满足以下条件后由管理员在后台确认晋级：该档节点在线率 ≥ 99%，且没有回退事件。
  - 新版本启动后 5 分钟内连不上控制面则自动回退。
  - 升级顺序固定为先控制面、后 Agent。控制面至少兼容前两个 Agent 小版本；Agent 比控制面新时，按 `HelloAck` 中的协议版本与控制面能力位运行，不使用控制面未声明的新能力（spec/20 NODE-16）。
- **DEP-10** 备份与恢复：
  - PostgreSQL 每日基础备份，加持续 WAL 归档（pgBackRest）。
  - 加密主密钥与签名私钥不随数据库备份，必须由运营者离线备份，与数据库备份分开存放。部署文档写明这一要求，以及主密钥丢失的后果：全部 `_enc` 值无法解密，需要重新接入节点、重置 TOTP、重新录入支付私钥、轮换全部代理凭据。
  - CI 每周用合成数据执行一次恢复演练。通过条件：恢复后迁移版本一致；用备份的主密钥能解密抽样的 `_enc` 列；`account_balances` 与备份前一致。
  - 从备份恢复后，按顺序执行：
    1. 对恢复点之后创建的订单调用 `alipay.trade.query` 补齐；
    2. 所有节点做一次全量同步（重连时强制 `config_version = 0`）；
    3. 按 spec/22 ACC-07 重建 Valkey 用量。
- **DEP-11** 可用性参考目标（写入部署文档，项目不承诺 SLA）：
  - 多实例形态：RPO ≤ 1 分钟，RTO ≤ 15 分钟。PostgreSQL 故障切换使用 Patroni 或运营者的等价方案，文档给出手工提升从库的步骤。
  - 单机形态：只提供 WAL 归档保证的 RPO，不承诺 RTO。
- **DEP-12** 控制面升级与迁移：
  - 迁移只由 `panel migrate` 执行（goose 自带锁）。`api`、`gateway`、`worker` 启动时只校验数据库版本不低于编译时的要求，不自动执行迁移。
  - 每个版本的迁移必须与上一个小版本的二进制兼容，采用扩展—收缩两阶段：只新增列与表；删除或改名分两个版本完成。
  - 回滚只回退二进制，不回退迁移（CONV-21）。
  - “可以在线执行”指持有 ACCESS EXCLUSIVE 锁的时间不超过 1 秒。发版说明列出每个迁移能否在线执行（spec/42 42.5）。

## 40.6 可观测性

- Prometheus 指标（默认只监听本地）：在线节点、重连次数、指令时延、入账延迟、落库积压、配置接口命中率、租约超额、支付通知结果分布、outbox 积压与死信数、`ingest_stale_total`。
- 结构化日志遵守 CONV-23、CONV-24；可选 OpenTelemetry 追踪。
- 仓库附带 Grafana 看板与告警规则。项目不回传任何遥测数据。
