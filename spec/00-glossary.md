# 00 术语与标识符

适用范围：全部仓库。中文术语与代码、数据库、接口、协议中的名称一一对应；写代码时使用“标识符”列。

| 术语 | 含义 | 数据库 | 客户端接口 | 管理接口 | 节点协议 |
|---|---|---|---|---|---|
| 控制面 | 账户、计费、编排的中心服务，即 `panel` | — | — | — | — |
| 账号 | 一个注册用户 | `accounts` | `me` | `accounts` | `account_id` |
| 管理员 | 拥有角色的账号 | `account_roles` | — | `staff` | — |
| 会话 | 一次登录，持有刷新令牌 | `sessions` | `sessions` | `accounts/{id}/sessions` | — |
| 设备 | 自研客户端或用户中心所在的设备 | `devices` | `me/devices` | — | — |
| 代理凭据 | 节点上认证用户的秘密值；每台设备一条，另有一条供第三方客户端共用 | `proxy_credentials` | `credential` | — | `Credential` |
| 导出令牌 | 第三方客户端导入链接中的令牌 | `export_tokens` | `configurations/{token}` | — | — |
| 套餐 | 在售商品模板 | `plans` | `plans` | `plans` | — |
| 价格 | 套餐某一周期的价格行，只增不改 | `plan_prices` | `prices` | `plans/{id}/prices` | — |
| 等级 | 套餐的 `tier`，判断升级或降级 | `plans.tier` | `tier` | `tier` | — |
| 权益 | 账号当前拥有的套餐实例 | `entitlements` | `me/entitlements` | `accounts/{id}/entitlements` | — |
| 下一段 | 排在当前权益之后的权益（到期后生效的降级） | `entitlements.status='scheduled'` | `me/entitlements/next` | — | — |
| 权益事件 | 权益的只追加变更记录 | `entitlement_events` | — | 时间线 | — |
| 锁定价格 | 续费时使用的价格 | `entitlements.locked_price_id` | `locked_price` | — | — |
| 免费账号 | 没有生效中权益的账号 | 无当前权益行 | `entitlement_status='none'` | — | — |
| 报价 | 下单前锁定的计价结果，15 分钟有效 | `quotes` | `quotes` | — | — |
| 订单 | 一次购买 | `orders` | `orders` | `orders` | — |
| 余额 | 账户内的预存金额，由流水求和 | `credit_ledger` | `me/credits` | `accounts/{id}/credits` | — |
| 流量周期 | 流量额度的计算区间 | `entitlements.cycle_*`、`usage_cycles` | `usage` | — | — |
| 流量包 | 额外流量的加购项 | `addons` | — | — | — |
| 线路组 | 节点集合，权限的最小单位 | `location_groups` | — | `location-groups` | — |
| 节点 | 运行 Agent 的一个服务实例 | `nodes` | `locations`（面向用户的地区） | `hosts` | `node_id` |
| 机器 | 承载多个节点的一台服务器（机器模式） | `machines` | — | — | — |
| 入站 | 节点上对用户开放的一个协议端口 | `inbounds` | `endpoints` | `hosts/{id}/inbounds` | `Inbound` |
| 内核 | Agent 内嵌的代理实现：`singbox` 或 `xray` | `kernels`、`nodes.kernel_type` | — | `kernels` | `KernelType` |
| 接入令牌 | 节点首次注册用的一次性令牌 | `nodes.enroll_token_hash` | — | `hosts/{id}/enrollment-tokens` | — |
| 节点密钥 | 节点长期共享密钥（PSK） | `nodes.psk_enc` | — | — | 握手 MAC |
| 配额租约 | 控制面发给节点的按账号字节预算 | Valkey | — | — | `QuotaLease` |
| 流量报告 | 节点上报的增量用量 | `traffic_hourly` | — | — | `ReportTraffic` |
| 倍率 | 节点的计费流量倍数 | `nodes.traffic_multiplier` | `traffic_multiplier` | — | — |
| 模拟 Agent | 完整实现节点协议但不运行内核的测试程序 | — | — | — | `panel/server/e2e/fakeagent` |

对外接口禁止使用的词：`subscribe`、`server`、`node`、`traffic`（见 spec/30 API-01）。数据库与内部代码不受此限制。
