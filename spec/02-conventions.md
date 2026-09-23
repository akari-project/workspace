# 02 数据与接口约定

适用范围：全部仓库。实现任何表、接口、事件之前必须阅读。

## 2.1 标识符与时间

- **CONV-01** 主键使用 UUIDv7（PostgreSQL 18 `uuidv7()`）。
- **CONV-02** 对外展示的短编号另设字段，格式为 `前缀-YYYYMMDD-6位随机`，例如订单 `ORD-20261001-K7Q2XM`、工单 `TCK-...`。日期部分按站点时区（CONV-26）计算。
- **CONV-03** 时间在数据库中为 `timestamptz`，在接口中为 RFC 3339 并带时区。业务时间点（到期、周期重置）按站点时区计算，界面按用户时区显示。
- **CONV-04** 业务代码禁止直接调用 `time.Now()`，一律通过注入的时钟取得时间。
- **CONV-26** 站点时区保存在 `settings` 的键 `site_timezone`：
  - 取值为 IANA 名称，默认 `Asia/Shanghai`；
  - 在站点初始化时设定，之后只读（与 CONV-08 相同）；
  - 本地时刻因夏令时不存在或重复时，取该日期内第一个合法时刻。
- **CONV-27** 参与业务判断的时间列（如 `expires_at`、`starts_at`、`next_attempt_at`、报价与订单有效期）必须由应用使用注入的时钟显式写入。数据库的 `DEFAULT now()` 与触发器中的 `now()` 只用于审计性质的 `created_at`、`updated_at`，业务逻辑不得读取这两列来做判断。

## 2.2 金额与流量

- **CONV-05** 金额为最小货币单位的整数（`bigint` / `int64`），接口字段以 `_minor` 结尾并附 `currency`（ISO 4217）。禁止使用浮点数。
- **CONV-06** 比例计算使用整数分子与分母，只在最后一步向下取整。
- **CONV-07** 流量为字节数（`bigint` / `uint64`），接口字段以 `bytes_` 开头。
- **CONV-08** 一个站点只有一种结算货币，初始化后不可更改。

## 2.3 REST 接口

- **CONV-09** 路径为 `/v1/` 加复数名词。当前用户的资源在 `/v1/me/` 下。动作用子资源表达，例如 `POST /v1/orders/{id}/cancel`。单例资源（如 `/v1/me/usage`、`/v1/config`）用单数。命名约束见 spec/30。
- **CONV-10** 字段 `snake_case`；布尔字段以 `is_` 或 `has_` 开头；枚举值为小写字符串。例外：`/v1/config` 中 `features` 的键名是模块名（spec/13 OPS-08），不加前缀。
- **CONV-11** 分页为游标分页：请求 `?limit=50&cursor=...`，响应 `{ "items": [...], "next_cursor": "..." }`。
  - `limit` 默认 50，最大 200。
  - 游标是不透明的 base64url 字符串，由“排序键 + id”编码而成；列表必须按唯一且稳定的键排序；游标不过期。
  - 非法游标返回 400 `invalid_request`。最后一页的 `next_cursor` 为 `null`。
  - 条目数可能超过 200 的列表必须分页。以下列表可以不分页，但必须在 OpenAPI 描述中写明上限：数量受设备上限约束的设备列表（只返回未吊销的设备），由运营者维护、只返回生效中内容的公告（≤ 100）与文章（≤ 200）列表，在售套餐（≤ 200）与可用地区（≤ 500）列表，以及管理接口的角色列表（≤ 100）。
- **CONV-12** 产生副作用的 `POST` 接受 `Idempotency-Key`（UUID）：
  - 作用域：已认证请求为“账号 + 键”，未认证请求为“路由 + 键”。
  - 服务端保存键、路由、请求体的 SHA-256 与最终响应，保存 24 小时。
  - 相同的键、相同的请求体，返回相同结果；相同的键、不同的请求体，返回 422 `idempotency_key_reused`。
  - 首个请求仍在处理时，同键的请求返回 409 `conflict` 并附 `Retry-After`。
  - 只缓存 2xx 与 4xx 响应；5xx 不缓存，允许用同一键重试。
  - 过期记录由 worker 每小时清理。
  - 外部回调（如支付宝通知）不使用此请求头，以各自的业务键保证幂等（spec/12 PAY-05）。
  - 响应中含秘密值的接口（登录与令牌、一次性 nonce、TOTP 密钥与恢复码、导入链接、重新验证、节点接入令牌与安装命令、兑换码明文）不接受此请求头，以免秘密值随幂等记录保存 24 小时。
- **CONV-13** 配置类资源返回强 `ETag`，支持 `If-None-Match` 与 304。配置类资源包括：
  - 客户端接口：`GET /v1/config`、`GET /v1/me/configuration`、`GET /v1/configurations/{token}`；
  - 管理接口：可修改的单个资源，包括套餐、价格、线路组、节点、入站、路由、支付渠道、设置、角色、通知模板。
- **CONV-28** 对 CONV-13 所列管理接口资源的 `PUT`、`PATCH`、`DELETE` 必须携带 `If-Match`：缺少时返回 428 `precondition_required`，与当前 ETag 不一致时返回 409 `conflict`。ETag 可由 `updated_at` 或版本列生成。客户端接口中只修改本人单个开关的操作（如自动续费开关）不要求携带 `If-Match`。
- **CONV-14** `/v1` 在 1.0 之后只增加可选字段；破坏性变更进入 `/v2`。
- **CONV-15** 访问他人资源与资源不存在一律返回 404，不加区分。

## 2.4 错误

- **CONV-16** 错误响应为 RFC 9457 `application/problem+json`，必须包含 `type`、`title`、`status`、`code`、`request_id`。参数错误附 `errors[]`，每项为 `{field, code}`。客户端依据 `code` 显示本地化文案。

| code | HTTP | 含义 |
|---|---|---|
| `invalid_request` | 400 | 参数错误，`errors` 给出逐项原因 |
| `unauthenticated` | 401 | 未登录或令牌失效 |
| `mfa_required` | 401 | 需要二次验证，附 `challenge_id` 与 `methods`（spec/10 AUTH-20） |
| `forbidden` | 403 | 无权限 |
| `email_unverified` | 403 | 邮箱未验证，不能下单 |
| `registration_closed` | 403 | 注册已关闭，或当前策略要求邀请码而请求未提供 |
| `account_suspended` | 403 | 账号已暂停或正在注销 |
| `not_found` | 404 | 不存在或无权查看；模块关闭时对应接口同样返回此码 |
| `conflict` | 409 | 版本冲突（ETag 或乐观锁），或同一幂等键的请求仍在处理；重新读取后重试 |
| `invalid_state` | 409 | 资源当前状态不允许该操作（例如订单已支付不能取消） |
| `quote_expired` | 409 | 报价过期，或报价时的权益状态已变化 |
| `entitlement_required` | 409 | 需要生效中的权益（续费、升降级） |
| `device_limit_reached` | 409 | 设备数已达上限 |
| `payment_unavailable` | 409 | 支付渠道未启用或配置无效 |
| `kernel_protocol_unsupported` | 409 | 节点内核不支持该协议或传输（管理接口） |
| `payload_too_large` | 413 | 请求体或附件超过上限 |
| `idempotency_key_reused` | 422 | 同一幂等键用于不同的请求体 |
| `upgrade_required` | 426 | 客户端版本过低 |
| `precondition_required` | 428 | 缺少 `If-Match`（CONV-28） |
| `rate_limited` | 429 | 附 `Retry-After` |
| `internal` | 500 | 服务端错误 |
| `service_unavailable` | 503 | 依赖故障导致暂时不可用，附 `Retry-After`（spec/40 40.4） |

`errors[].code` 的取值：

| code | 含义 |
|---|---|
| `required` | 缺少必填项 |
| `invalid_format` | 格式错误（邮箱、UUID、枚举值等） |
| `too_short`、`too_long` | 长度越界 |
| `out_of_range` | 数值越界 |
| `not_allowed` | 取值不被当前策略允许（如邮箱域名不在白名单） |
| `invalid_code` | 验证码、重置链接、邀请码、优惠码或兑换码无效 |
| `incorrect` | 密码或二次验证码不正确（重新验证，spec/10 AUTH-23） |
| `expired` | 验证码、链接、优惠码或兑换码已过期 |
| `exhausted` | 尝试次数或使用次数已用完 |
| `taken` | 取值已被占用（只用于管理接口，如管理员新建账号时邮箱重复；客户端接口为防枚举不使用） |

新增错误码或 `errors[].code` 取值，必须先加入以上两张表。

**例外**：`/v1/oauth/*` 端点按 RFC 6749 §5.2 与 RFC 8628 返回 `application/json` 的 `{error, error_description}`，不使用 problem+json。这是 CONV-16 唯一的例外；这些端点的限流（429）与依赖故障（503）仍返回 problem+json。

## 2.5 数据库

- **CONV-17** 表名为复数 `snake_case`；外键为 `{单数}_id`。
  - 所有表都有 `created_at timestamptz NOT NULL DEFAULT now()`。
  - 除只追加表（CONV-18）、分区明细表与纯关联表外，其余表都是可变表，必须有 `updated_at`，并由触发器 `touch_updated_at` 维护。
- **CONV-18** 只追加表（`entitlement_events`、`credit_ledger`、`audit_logs`、`payment_notifications`）由行级触发器禁止 UPDATE 与 DELETE，并由语句级 `BEFORE TRUNCATE` 触发器禁止 TRUNCATE。
- **CONV-29** 只追加表与 outbox 类表中不得保存可直接识别个人的明文，包括邮箱、支付账号、买家标识与自由文本中的个人信息。需要保存时有两种做法：
  - 放入可变的关联表；
  - 用按账号派生的密钥加密后存入 `_enc` 列，账号数据删除时销毁该账号的派生密钥，即“加密擦除”。

  支付宝通知原文在写入 `payment_notifications` 前，去除买家账号类字段（spec/12 PAY-06）。
- **CONV-19** 敏感值用应用层 AEAD 加密，列名以 `_enc` 结尾。敏感值包括：节点密钥、TOTP 密钥、支付私钥、DNS 服务商凭据、代理凭据、导出令牌明文（CONV-20），以及入站配置中的私钥（Reality `private_key`、Shadowsocks 2022 服务端密钥）。入站私钥保存在 `inbounds.secrets_enc`，不写入 `inbounds.settings`；控制面生成节点快照时合并进 `settings_json`。

  加密要求不限于数据库列，同样适用于以下位置中出现的敏感值：
  - Valkey 中的缓存（如导出配置，spec/23 EXP-07）；
  - Valkey Stream 中转发的指令（如 `CredUpsert`，spec/40 DEP-07）；
  - 通知队列中的变量（CONV-31）；
  - 节点本地的状态文件（spec/21 AGT-05）。

  加密主密钥来自环境变量或外部 KMS，不入库。
- **CONV-30** 密文格式为 `key_id（1 字节）‖ nonce ‖ ciphertext`。
  - 运行时同时加载当前主密钥与至多一把旧主密钥。
  - `panel keys rotate` 分批用当前主密钥重新加密全部 `_enc` 值，完成后旧密钥才可下线。
  - 签名私钥（PASETO 访问令牌、`/v1/config` 的 Ed25519 签名、Agent 发布签名）不入库，存放方式与主密钥相同。每个签名都带 key id，验证方同时接受当前与下一把公钥。
  - 主密钥与签名私钥的备份、恢复要求见 spec/40 DEP-10。
- **CONV-20** 令牌、兑换码、验证码只存 SHA-256，列名以 `_hash` 结尾。

  **例外**：导出令牌同时保存 `token_hash`（用于查找）与 `token_enc`（CONV-19，用于在用户中心与帮助文档中再次显示导入链接）。
- **CONV-31** 通知队列（`notification_outbox`）中含令牌、验证码或链接的变量，按 CONV-19 加密存储；投递成功或最终失败后立即清除这些变量。
- **CONV-21** 迁移规则：
  - 迁移只前进，不写 `-- +goose Down` 段；回滚只回退二进制，不回退迁移（spec/40 DEP-12）。
  - 文件名为 `NNNNN_描述.sql`；已提交的迁移不可修改。
  - 为已有数据的表加索引时，使用 `CREATE INDEX CONCURRENTLY` 并标记 `-- +goose NO TRANSACTION`；在同一个迁移中新建的表不受此限。

## 2.6 事件

- **CONV-22** 业务事件写入 `outbox`，与业务数据在同一事务中；worker 投递到 Valkey Stream `events:{topic}`；消费方以事件 ID 幂等。载荷带 `schema_version`，只增字段。
- 主题：

| 主题 | 触发 |
|---|---|
| `order.paid` | 订单标记为已支付（spec/12 ORD-08） |
| `entitlement.changed` | 每写一条权益事件（spec/11 BIL-03） |
| `plan.access_changed` | 套餐的线路组关联或 `tier` 变更 |
| `location_group.changed` | 线路组的 `min_tier` 变更 |
| `node.membership_changed` | 节点加入或离开线路组 |
| `credential.changed` | 代理凭据创建、轮换或吊销（设备注册与移除、共用凭据轮换） |
| `account.status_changed` | 账号暂停、恢复、进入或撤销注销 |

- **CONV-32** 投递与可靠性：
  - worker 以 `FOR UPDATE SKIP LOCKED` 按 `created_at` 顺序取出未发布事件，XADD 成功后再写 `published_at`。
  - Stream 使用 `MAXLEN ~ 100000`，消费组名为消费方角色名。
  - 消费方在处理业务的同一事务中写入 `consumed_events(event_id, consumer)`，以此幂等。
  - 同一事件消费失败 10 次后，移入 `events:dead:{topic}` 并告警。
  - 对账任务每 5 分钟执行一次：已发布超过 10 分钟、仍没有消费记录的事件，重新投递。这可以覆盖 Valkey 丢失已确认数据的情况（spec/22 ACC-07）。
  - 已发布且已被全部消费方处理、超过 7 天的 outbox 行删除。
- 外发通知不走事件主题：业务代码在同一事务中直接写 `notification_outbox`（spec/13 OPS-02）。

## 2.7 日志与隐私

- **CONV-23** 结构化日志（`slog`）的字段：`request_id`、`account_id`、`node_id`、`route`、`status`、`duration_ms`。`route` 记录路由模板（如 `GET /v1/configurations/{token}`），不记录实际路径。
- **CONV-24** 禁止记录：密码、令牌、导出链接、代理凭据、密钥、完整 IP（需要时只记录 /24 或 /48 前缀）、访问目标。前置代理的访问日志要求见 spec/40 DEP-13。
- **CONV-25** SPDX 许可证标识位于每个源文件的前两行之内：第一行是 shebang 或 `//go:build` 时，放在紧随其后的一行。许可证与所在仓库一致。
  - 来自上游、不补 SPDX 头的文件，在仓库根目录的 `REUSE.toml` 中登记，包括 node-agent 中来自 Xboard-Node 的文件，以及两个内核 fork 中的上游文件。
  - 两个内核 fork 只检查本组织新增的文件。
