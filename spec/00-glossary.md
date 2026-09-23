# 00 术语与标识符

适用范围：全部仓库。中文术语与代码、数据库、接口、协议中的名称一一对应；写代码时使用“标识符”列。

| 术语 | 含义 | 数据库 | 客户端接口 | 管理接口 | 节点协议 |
|---|---|---|---|---|---|
| 控制面 | 账户、计费、编排的中心服务，即 `panel` | — | — | — | — |
| 账号 | 一个注册用户 | `accounts` | `me` | `accounts` | `account_id` |
| 管理员 | 拥有角色的账号 | `account_roles` | — | `staff` | — |
| 会话 | 一次登录，持有刷新令牌；与节点上的“代理连接”不同 | `sessions` | `me/sessions` | `accounts/{id}/sessions` | — |
| 代理连接 | 客户端与节点之间的一条代理连接；节点协议与内核接口中的 “session” 指它 | — | — | — | `Session` |
| 设备 | 自研客户端或用户中心所在的设备。`platform='web'` 的设备不生成代理凭据，不计入设备上限（spec/10 AUTH-10） | `devices` | `me/devices` | `accounts/{id}/devices` | — |
| 代理凭据 | 节点上认证用户的秘密值；每台非 web 设备一条，另有一条供第三方客户端共用 | `proxy_credentials` | `credential` | — | `Credential` |
| 导出令牌 | 第三方客户端导入链接中的令牌 | `export_tokens` | `configurations/{token}`、`me/export-link` | — | — |
| 套餐 | 在售商品模板 | `plans` | `plans` | `plans` | — |
| 价格 | 套餐某一周期的价格行，只增不改 | `plan_prices` | `prices` | `plans/{id}/prices` | — |
| 等级 | 套餐的 `tier`，用于判断升级或降级 | `plans.tier` | `tier` | `tier` | — |
| 权益 | 账号拥有的套餐实例 | `entitlements` | `me/entitlements` | `accounts/{id}/entitlements` | — |
| 本段 | 当前权益从 `starts_at` 到 `expires_at` 的区间；续费延长本段（spec/11 BIL-20） | `entitlements.starts_at`、`expires_at` | — | — | — |
| 本段实付 | 为本段支付的价值：现金、余额抵扣与带入的剩余价值之和，不含优惠 | `entitlements.paid_minor` | — | — | — |
| 下一段 | 排在当前权益之后的权益（到期后生效的降级） | `entitlements.status='scheduled'` | `me/entitlements/next` | — | — |
| 权益事件 | 权益的只追加变更记录 | `entitlement_events` | — | 时间线 | — |
| 锁定价格 | 续费时使用的价格；只对应一个周期 | `entitlements.locked_price_id` | `locked_price` | — | — |
| 免费账号 | 没有付费套餐（`kind≠free`）的生效中权益的账号；持有免费套餐权益的账号也属于免费账号 | 无付费的当前权益行 | `entitlement_status='none'` 或 `'free'` | — | — |
| 报价 | 下单前锁定的计价结果，15 分钟有效 | `quotes` | `quotes` | — | — |
| 订单 | 一次购买 | `orders` | `orders` | `orders` | — |
| 余额 | 账户内的预存金额，由流水求和 | `credit_ledger` | `me/credits` | `accounts/{id}/credits` | — |
| 流量周期 | 流量额度的计算区间；一段权益可以包含多个周期 | `entitlements.cycle_*`、`usage_cycles` | `usage` | — | — |
| 加购项 | 流量包或额外设备名额（spec/11 11.8） | `addons`，`kind` 为 `traffic` 或 `devices` | `addons`，`kind` 为 `data` 或 `devices` | `addon-prices` | — |
| 线路组 | 节点集合，权限的最小单位 | `location_groups` | — | `location-groups` | — |
| 节点 | 运行 Agent 的一个服务实例 | `nodes` | `locations`（面向用户的地区） | `hosts` | `node_id` |
| 机器 | 承载多个节点的一台服务器（机器模式，M5） | `machines` | — | — | — |
| 入站 | 节点上对用户开放的一个协议端口 | `inbounds` | `endpoints` | `hosts/{id}/inbounds` | `Inbound` |
| 传输 | 入站在协议之下使用的传输方式，如 `tcp`、`ws`、`grpc`、`xhttp`、`mkcp` | `inbounds.settings->>'transport'`、`kernel_transports` | — | — | `Inbound.settings_json` |
| 内核 | Agent 内嵌的代理实现：`singbox` 或 `xray` | `kernels`、`nodes.kernel_type` | — | `kernels` | `KernelType` |
| 接入令牌 | 节点首次注册用的一次性令牌 | `nodes.enroll_token_hash` | — | `hosts/{id}/enrollment-tokens` | — |
| 节点密钥 | 节点长期共享密钥（PSK） | `nodes.psk_enc` | — | `hosts/{id}/key-revocations` | 握手 MAC |
| 能力位 | 节点在 `Hello.capabilities` 中声明的可选能力；控制面只向声明了的节点发送对应消息 | `nodes.capabilities` | — | — | `Capabilities` |
| 配置版本 | 节点配置的单调版本号，每次下发变更加 1 | `nodes.config_version` | — | — | `config_version` |
| 配置快照 | 节点当前完整配置（内核、入站、凭据、路由），即 `SyncFull` 的内容 | — | — | — | `SyncFull` |
| 权限协调器 | 根据权益、套餐、线路组、账号状态计算每个节点应有的凭据并下发的 worker 组件 | — | — | — | — |
| 处置 | 因到期、超额、暂停、吊销等原因使凭据从节点移除并关闭其代理连接的过程 | — | — | — | `CredRemove` |
| 配额租约 | 控制面发给节点的按账号字节预算 | Valkey | — | — | `QuotaLease` |
| 流量报告 | 节点上报的增量用量 | `traffic_hourly` | — | — | `ReportTraffic` |
| 倍率 | 节点的计费流量倍数 | `nodes.traffic_multiplier` | `usage_multiplier` | `usage_multiplier` | — |
| 模拟 Agent | 完整实现节点协议但不运行内核的测试程序 | — | — | — | `panel/server/e2e/fakeagent` |

对外接口禁止使用的词：`subscribe`、`server`、`node`、`traffic`（见 spec/30 API-01）。数据库、节点协议与内部代码不受此限制。
