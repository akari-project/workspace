# 40 部署、高可用与降级

适用范围：`panel/deploy`、`panel/server/internal/webui`、`node-agent` 安装。

## 40.1 部署形态

| 形态 | 组成 | 适用 |
|---|---|---|
| 单机 | 一个 `panel all` 二进制 + PostgreSQL 18 + Valkey；可选 Caddy 负责自动 HTTPS | 几百到几千用户；`docker compose up` 10 分钟内完成 |
| 多实例 | api、gateway、worker 分别扩容；PostgreSQL 主从 + WAL 归档；Valkey 主从 + Sentinel | 更大规模（M5 提供 Helm Chart） |

## 40.2 前端内嵌

- **DEP-01** 用户中心与管理后台的构建产物通过 Go `embed` 编进 `panel`。`make build`：`pnpm -r build` → 复制到 `server/internal/webui/dist/{portal,admin}` → `go build`。CI 校验嵌入产物与源码为同一提交。
- **DEP-02** 按 Host 或路径前缀（配置项）分别提供两个应用；未命中静态文件时回退到对应 `index.html`。
- **DEP-03** 带哈希的资源 `Cache-Control: public, max-age=31536000, immutable`；`index.html` 为 `no-cache`；构建时预压缩 br 与 gzip。
- **DEP-04** 返回 `index.html` 时注入运行时配置（站点名称、接口地址、源代码链接、CSP nonce）。
- **DEP-05** 安全头：Content-Security-Policy、`X-Content-Type-Options: nosniff`、`Referrer-Policy: strict-origin-when-cross-origin`；管理后台另加 `X-Frame-Options: DENY`。
- **DEP-06** `-tags noui` 构建不含前端的二进制。开发时使用 Vite 开发服务器，不依赖嵌入产物。

## 40.3 多实例下的指令路由

- **DEP-07** 节点连接后，网关写入 `node:{id}:gw = <网关ID>`（带 TTL，随心跳续期）。任意实例把指令发布到 Valkey Stream `gw:{网关ID}`；目标网关转发，节点确认后再确认 Stream。网关宕机时由节点重连后的版本同步兜底。
- **DEP-08** 周期任务（到期扫描、分区维护、对账）使用 Valkey 租约锁保证单实例执行。

## 40.4 故障降级

| 故障 | 行为 |
|---|---|
| 控制面全部不可用 | 节点按最后快照服务，租约与到期继续生效，报告写 WAL；自研客户端用缓存配置连接 |
| Valkey 不可用 | 配置接口降级为直接查库（有并发上限）；报告暂不确认留在 WAL；不再续发租约，用完后按配置放行或停止 |
| PostgreSQL 主库不可用 | 用量在 Valkey 继续累积，落库重试并告警；写接口 503，读接口切从库 |
| 单个网关宕机 | 节点重连到其他实例并按版本收敛 |
| 节点失陷 | 吊销该节点密钥，批量轮换受影响凭据；自研客户端自动取得新凭据，第三方用户需重新拉取配置 |
| 支付宝通知丢失 | 查询兜底（spec/12 PAY-07） |

## 40.5 升级与备份

- **DEP-09** Agent 自升级：发布物签名，Agent 内置公钥验签；灰度 1% → 10% → 100%；新版本在 N 分钟内连不上控制面则回退。控制面至少兼容前两个 Agent 小版本。
- **DEP-10** PostgreSQL 每日基础备份 + 持续 WAL 归档（pgBackRest）；CI 定期执行恢复演练。加密主密钥与签名私钥不随数据库备份。

## 40.6 可观测性

- Prometheus 指标（默认只监听本地）：在线节点、重连次数、指令时延、入账延迟、落库积压、配置接口命中率、租约超额、支付通知结果分布。
- 结构化日志遵守 CONV-23、CONV-24；可选 OpenTelemetry 追踪。
- 仓库附带 Grafana 看板与告警规则。项目不回传任何遥测数据。
