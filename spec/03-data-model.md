# 03 数据模型

适用范围：`panel/server/migrations`。字段级定义以迁移文件为准（起步为 `00001_init.sql`），本文件说明表的分组、关系与约束意图。

`00001_init.sql` 在 M0-05 提交之前可以直接修改；提交之后，所有改动都通过新的迁移完成（CONV-21）。M0-05 需要让 00001 满足本文件与 spec/02 的全部约束，包括删除 `-- +goose Down` 段，以及补齐 CONV-17 要求的列与触发器。

## 3.1 分组

| 分组 | 表 | 规格 |
|---|---|---|
| 账号与认证 | `accounts`、`roles`、`account_roles`、`staff_invitations`、`mfa_totp`、`mfa_webauthn`、`verification_codes`、`sessions`、`devices` | spec/10 |
| 凭据与导出 | `proxy_credentials`（`secret_enc` 的明文为 16 字节原始 UUIDv4，spec/21 AGT-15；00001 中的列注释“UUID / 密码等”已过时，由后续迁移以 `COMMENT ON COLUMN` 更正，见 backlog M1-03）、`export_tokens`（`token_hash` 与 `token_enc`） | spec/10、spec/23 |
| 节点 | `kernels`、`kernel_protocols`、`kernel_transports`、`machines`、`nodes`（含 `last_report_seq`）、`location_groups`、`node_group_members`、`inbounds`（非敏感配置在 `settings`，私钥在 `secrets_enc`）、`node_routes` | spec/20、spec/21 |
| 套餐与权益 | `plans`、`plan_groups`、`plan_prices`、`addon_prices`、`entitlements`、`entitlement_events`、`addons`、`usage_cycles` | spec/11 |
| 订单与支付 | `quotes`、`orders`（含 `payer_ref_hash`、累计退款）、`payment_providers`、`payment_notifications`、`refunds`、`credit_ledger`（视图 `account_balances`）、`coupons`、`coupon_redemptions`、`redeem_codes`、`redeem_redemptions` | spec/12 |
| 流量 | `ingest_batches`、`traffic_hourly`（按月分区，按账号、节点、小时）、`traffic_daily` | spec/22 |
| 运营 | `announcements`、`support_tickets`、`support_messages`、`support_attachments`、`articles`、`referral_earnings`、`notification_templates`、`notification_preferences`、`notification_outbox` | spec/13 |
| 基础设施 | `settings`（含只读键 `site_timezone`、`site_currency`）、`outbox`、`consumed_events`、`idempotency_keys`、`job_fencing`、`audit_logs`（含 `reason_id`、`request_id`）、`reason_texts` | spec/02、spec/40 |

## 3.2 关系

```mermaid
erDiagram
  accounts ||--o{ devices : has
  accounts ||--o{ proxy_credentials : has
  devices ||--o| proxy_credentials : owns
  accounts ||--o{ entitlements : has
  plans ||--o{ entitlements : instantiates
  plans ||--o{ plan_prices : priced_by
  plans }o--o{ location_groups : grants
  location_groups }o--o{ nodes : contains
  nodes ||--o{ inbounds : serves
  kernels ||--o{ kernel_protocols : supports
  kernels ||--o{ kernel_transports : supports
  entitlements ||--o{ addons : extends
  accounts ||--o{ orders : places
  orders ||--o{ payment_notifications : receives
  orders ||--o{ refunds : refunded_by
  entitlements ||--o{ entitlement_events : logged_by
  reason_texts ||--o{ entitlement_events : explains
  reason_texts ||--o{ audit_logs : explains
  accounts |o--o{ accounts : referred
  redeem_codes ||--o{ redeem_redemptions : used_by
```

## 3.3 数据库强制的约束

| 约束 | 实现方式 |
|---|---|
| 每个账号至多一个当前权益、至多一个下一段 | 部分唯一索引 `entitlements_current_uq`、`entitlements_scheduled_uq` |
| 到期扫描覆盖 `active`、`over_quota`、`suspended` | 部分索引 `entitlements_expiry` 的条件包含这三种状态（spec/11 BIL-13） |
| 每个账号同时至多一个未支付的变更类订单，以及至多一个未支付的新购订单 | 部分唯一索引 `orders_one_pending_change`、`orders_one_pending_new`（spec/12 ORD-02） |
| 价格行的金额、币种、周期、`period_days` 不可修改；`on_sale` 只能由真变假；不可删除 | 触发器 `plan_prices_immutable`（用 `IS DISTINCT FROM` 比较）、`plan_prices_nodelete`；`addon_prices` 同样处理 |
| 非免费套餐的价格金额大于 0 | 触发器或 CHECK（spec/11 BIL-01） |
| 入站协议与传输必须被节点内核支持，实验协议需要节点允许 | 触发器 `inbounds_kernel_guard`、`nodes_kernel_guard`，依据 `kernel_protocols` 与 `kernel_transports` |
| 只追加表不可修改、不可截断 | 行级触发器调用 `forbid_mutation()`，语句级 `BEFORE TRUNCATE` 触发器（CONV-18） |
| 可变表的 `updated_at` 自动维护 | 触发器 `touch_updated_at`（CONV-17） |
| 支付渠道交易号唯一 | 部分唯一索引 `orders_provider_txn_uq` |
| 每台设备至多一条有效凭据；每个账号至多一条共用凭据 | 部分唯一索引 |
| 同一账号对同一兑换码只能兑换一次 | 唯一约束 `redeem_redemptions (redeem_code_id, account_id)` |
| 百分比优惠券的 `value ≤ 10000` | CHECK |
| 幂等键按“账号或路由 + 键”唯一，未认证请求的 `account_id` 可以为空 | 唯一索引（CONV-12） |
| `site_timezone`、`site_currency` 初始化后只读 | 触发器 `settings_readonly`（CONV-08、CONV-26） |
| 只追加表不保存原因原文；`admin_adjust` 权益事件必须带原因 | `reason_id` 外键引用 `reason_texts`；CHECK `type <> 'admin_adjust' OR reason_id IS NOT NULL`（CONV-29） |
| `tier = 0` 只属于免费套餐 | CHECK `(kind = 'free') = (tier = 0)`（spec/11 11.1） |
| 余额流水的方向由原因决定 | CHECK：`order_payment`、`account_deletion` 为负；`referral`、`admin_adjust` 可正可负；其余为正（spec/12 ORD-16） |
| 加购报价引用加购价格，其他报价引用套餐价格 | `quotes` 的 CHECK：`(order_type = 'addon') = (addon_price_id IS NOT NULL)`，`price_id` 与 `addon_price_id` 恰有一个非空 |
| 原路退款不超过累计退款 | CHECK `refunded_original_minor <= refunded_minor` |

应用层还必须保证数据库无法表达的规则，见各规格中的编号规则。例如：余额扣减后不为负，由下单事务中的账号行锁保证（spec/12 ORD-15）。

## 3.4 M0-05 定稿时补入的列

以下列在 M0-05 修订 00001 时加入，字段级定义以 `00001_init.sql` 为准。

| 表 | 列 | 用途 |
|---|---|---|
| `accounts` | `referrer_id`（原 `referred_by`，按 CONV-17 改名） | 邀请人 |
| `roles` | `is_builtin` | 内置角色不可修改、不可删除（spec/10 AUTH-22），由应用层保证 |
| `sessions` | `audience`（`client` 或 `console`） | 令牌受众（spec/10 AUTH-06、AUTH-21） |
| `sessions` | `ip_prefix` | 来源 IP 的 /24 或 /48 前缀（CONV-24），用于 AUTH-07 |
| `mfa_totp` | `last_used_step` | 同一时间步内已用过的码不得再次使用（spec/10 AUTH-11） |
| `quotes`、`orders`、`addons` | `addon_price_id` | 加购项引用的加购价格 |
| `addons` | `paid_minor` | 加购项实付，单独退款的依据（spec/11 BIL-25） |
| `orders` | `refunded_original_minor` | 累计退款中原路退回的部分 |
| `refunds` | `addon_id` | 加购项单独退款（BIL-25） |
| `support_tickets` | `status_changed_at` | 自动关闭与重新打开的判定依据（spec/13 OPS-11） |
| `notification_outbox` | `retry_until`、`failed_at`、`secret_variables_enc` | 最长重试时间与最终失败（OPS-02）；含令牌、验证码或链接的变量（CONV-31） |
| `coupons`、`redeem_codes` | `disabled_at` | 停用时间 |
| `entitlement_events`、`audit_logs` | `reason_id` | 原因文本引用（CONV-29） |

## 3.5 内核基线

`kernel_protocols` 与 `kernel_transports` 的初始数据与 spec/21 21.2 的两张矩阵一致（不支持的组合没有行）：

| 内核 | 协议 | 传输 |
|---|---|---|
| `singbox` | 稳定：`vless`、`vmess`、`trojan`、`shadowsocks`、`hysteria2`、`tuic`、`anytls` | 稳定：`tcp`、`ws`、`grpc`、`httpupgrade`、`quic` |
| `xray` | 稳定：`vless`、`vmess`、`trojan`、`shadowsocks`；实验：`hysteria2` | 稳定：`tcp`、`ws`、`grpc`、`httpupgrade`、`xhttp`、`mkcp`；实验：`quic` |

两张表分别以（内核, 协议）与（内核, 传输）为键，表达不了“协议 + 传输”的组合限制，已知限制见 spec/21 21.2。

## 3.6 M1 补入的列与设置键

| 位置 | 名称 | 用途 |
|---|---|---|
| `sessions` 列 | `absolute_expires_at`（可空） | 会话链的绝对失效时间：客户端会话自首次登录起 90 天，管理会话 12 小时；轮换时继承，为空时以 `expires_at` 为准（spec/10 AUTH-07、AUTH-21）。可空以兼容上一版本二进制（spec/40 DEP-12） |
| `settings` 键 | `registration_policy` | `"open"`、`"invite_only"`、`"closed"`，默认 `"open"`（spec/10 AUTH-02）；管理接口字段同名 |
| `settings` 键 | `email_domain_allowlist`、`email_domain_denylist` | 邮箱域名白名单与黑名单，JSON 字符串数组，默认空（AUTH-02）；管理接口字段同名 |
| `settings` 键 | `smtp` | SMTP 投递设置（spec/13 OPS-01），JSON 对象 `{host, port, username, from_address, tls}`，字段与管理接口的 `settings.smtp` 同名。`tls` 取 `starttls`（缺省，要求 STARTTLS，服务器不支持即投递失败）、`implicit`（隐式 TLS，常用端口 465）、`none`（明文，只用于本机或可信内网中继，例如开发环境的 Mailpit）。保存时拒绝端口 465 与 `starttls` 的组合、`none` 与用户名的组合（`not_allowed`）。不提供跳过证书校验的选项 |
| `settings` 键 | `min_version` | 客户端最低版本（spec/30 API-03、API-11），JSON 对象，键为 `ClientPlatform`（`ios`、`android`、`windows`、`macos`、`linux`），值为 `x.y.z`，默认 `{}`；管理接口字段同名，更新时可选；平台或版本格式错误返回 `invalid_format`（`errors[].field` 如 `min_version.ios`）；更新时整体替换，提交 `{}` 解除全部限制 |
| `settings` 键 | `features` | 运营模块开关（spec/13 OPS-08），JSON 对象，键为模块名（`announcements`、`articles`、`support`、`referrals`、`diagnostics`），值为布尔。只有值为 JSON `true` 才算开启，`false` 与缺键等价；站点初始化时不写入，缺省即全部关闭。读取永不因此键失败：值不是对象时视为全部关闭，某键的值不是 `true` 时视为关闭，未知键忽略；值异常时记一条 warn 日志，只记键名（CONV-24）。管理接口字段同名，更新时可选；`features` 本身为 `null` 或非对象时返回 `invalid_format`（`errors[].field` 为 `features`）；按键合并：只修改提交的模块，未提交的保持原值（与 `min_version` 的整体替换不同：开关没有“删除”语义，整体替换只会让漏交的模块被意外关闭）；值为 `null` 或非布尔、模块名未知，返回 `invalid_format`（`errors[].field` 如 `features.support`）；实现须按键逐一校验，不得用生成的结构体解码而静默丢弃未知键。开启本二进制未实现的模块返回 `not_allowed`，提交 `false` 始终允许；读取时的有效值见 OPS-08 |
| `settings` 键 | `config_issued_at` | `/v1/config` 的 `issued_at`（spec/30 API-11），秒精度 RFC 3339 字符串；站点初始化时写入；`features`、`registration_policy`、`min_version` 的有效值实际变化时，在同一事务中写入 `max(当前时刻, 上一次的值 + 1 秒)`，严格递增，规则见 API-11；不在管理接口中暴露 |
| `settings` 键 | `smtp_password_enc` | SMTP 密码密文（CONV-19）；管理接口只返回 `smtp.has_password` |
