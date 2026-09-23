# 02 数据与接口约定

适用范围：全部仓库。实现任何表、接口、事件之前必须阅读。

## 2.1 标识符与时间

- **CONV-01** 主键使用 UUIDv7（PostgreSQL 18 `uuidv7()`）。
- **CONV-02** 对外展示的短编号另设字段，格式 `前缀-YYYYMMDD-6位随机`，例如订单 `ORD-20261001-K7Q2XM`、工单 `TCK-...`。
- **CONV-03** 时间在数据库中为 `timestamptz`，接口中为 RFC 3339 并带时区。业务时间点（到期、周期重置）按站点时区计算，界面按用户时区显示。
- **CONV-04** 业务代码禁止直接调用 `time.Now()`，一律通过注入的时钟取得时间。

## 2.2 金额与流量

- **CONV-05** 金额为最小货币单位的整数（`bigint` / `int64`），接口字段以 `_minor` 结尾并附 `currency`（ISO 4217）。禁止浮点数。
- **CONV-06** 比例计算使用整数分子分母，只在最后一步向下取整。
- **CONV-07** 流量为字节数（`bigint` / `uint64`），接口字段以 `bytes_` 开头。
- **CONV-08** 一个站点只有一种结算货币，初始化后不可更改。

## 2.3 REST 接口

- **CONV-09** 路径为 `/v1/` 加复数名词；当前用户的资源在 `/v1/me/` 下；动作用子资源表达（`POST /v1/orders/{id}/cancel`）。命名约束见 spec/30。
- **CONV-10** 字段 `snake_case`；布尔字段以 `is_` 或 `has_` 开头；枚举值为小写字符串。
- **CONV-11** 分页为游标分页：`?limit=50&cursor=...`，响应 `{ "items": [...], "next_cursor": "..." }`，`limit` 最大 200。
- **CONV-12** 产生副作用的 `POST` 接受 `Idempotency-Key`（UUID），服务端保存 24 小时，相同键返回相同结果。
- **CONV-13** 配置类资源返回 `ETag`，支持 `If-None-Match` 与 304。
- **CONV-14** `/v1` 在 1.0 之后只增加可选字段；破坏性变更进入 `/v2`。
- **CONV-15** 访问他人资源与资源不存在一律返回 404，不区分。

## 2.4 错误

- **CONV-16** 错误响应为 RFC 9457 `application/problem+json`，包含 `type`、`title`、`status`、`code`、`request_id`，参数错误附 `errors[]`。客户端依据 `code` 显示本地化文案。

| code | HTTP | 含义 |
|---|---|---|
| `invalid_request` | 400 | 参数错误，`errors` 给出逐项原因 |
| `unauthenticated` | 401 | 未登录或令牌失效 |
| `mfa_required` | 401 | 需要二次验证，附 `challenge_id` |
| `forbidden` | 403 | 无权限 |
| `email_unverified` | 403 | 邮箱未验证，不能下单 |
| `not_found` | 404 | 不存在或无权查看 |
| `conflict` | 409 | 版本冲突，重新读取后重试 |
| `quote_expired` | 409 | 报价过期或权益已变化 |
| `entitlement_required` | 409 | 需要生效中的权益（续费、升降级） |
| `device_limit_reached` | 409 | 设备数已达上限 |
| `payment_unavailable` | 409 | 支付渠道未启用或配置无效 |
| `kernel_protocol_unsupported` | 409 | 节点内核不支持该协议（管理接口） |
| `upgrade_required` | 426 | 客户端版本过低 |
| `rate_limited` | 429 | 附 `Retry-After` |
| `internal` | 500 | 附 `request_id` |

新增错误码必须先加入此表。

## 2.5 数据库

- **CONV-17** 表名复数 `snake_case`；外键 `{单数}_id`；所有表有 `created_at`，可变表有 `updated_at`（触发器维护）。
- **CONV-18** 只追加表（`entitlement_events`、`credit_ledger`、`audit_logs`、`payment_notifications`）由触发器禁止 UPDATE 与 DELETE。
- **CONV-19** 敏感值（节点密钥、TOTP 密钥、支付私钥、DNS 服务商凭据、代理凭据）用应用层 AEAD 加密，列名以 `_enc` 结尾；加密主密钥来自环境变量或外部 KMS，不入库。
- **CONV-20** 令牌、兑换码、导出令牌只存 SHA-256，列名以 `_hash` 结尾。
- **CONV-21** 迁移只前进，文件名 `NNNNN_描述.sql`；已提交的迁移不可修改；加索引使用 `CREATE INDEX CONCURRENTLY` 并标记 `-- +goose NO TRANSACTION`。

## 2.6 事件

- **CONV-22** 业务事件写入 `outbox`，与业务数据同一事务；worker 投递到 Valkey Stream `events:{topic}`；消费方以事件 ID 幂等。载荷带 `schema_version`，只增字段。
- 主题：`order.paid`、`entitlement.changed`、`plan.access_changed`、`node.membership_changed`、`device.revoked`、`account.suspended`、`notification.requested`。

## 2.7 日志与隐私

- **CONV-23** 结构化日志（`slog`）字段：`request_id`、`account_id`、`node_id`、`route`、`status`、`duration_ms`。
- **CONV-24** 禁止记录：密码、令牌、导出链接、代理凭据、密钥、完整 IP（需要时只记录 /24 或 /48 前缀）、访问目标。
- **CONV-25** 每个源文件第一行为 SPDX 许可证标识，与所在仓库一致；node-agent 中来自 Xboard-Node 的文件保留原声明。
