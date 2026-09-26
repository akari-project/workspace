# 31 管理接口

适用范围：`panel-spec/openapi/console/v1.yaml`（M0-03 编写）、`panel/server/internal/consoleapi`、`panel/web/admin`。

- **CON-01** 位于独立域名（例如 `console.运营者域名`）或配置的路径前缀；命名、分页、错误遵守 spec/02 与 spec/30 API-01。只接受受众为 `console` 的令牌（spec/10 AUTH-21）。
- **CON-02** 每个操作以 `x-permission` 声明所需权限，取值只能来自 spec/10 AUTH-17 的权限目录，由 CI 校验。每个操作至少有一个响应示例，供 Mock 服务使用。
- **CON-03** 所有写操作都写审计日志。spec/10 AUTH-19 列出的敏感操作，要求带原因、请求头带 `Mfa-Assertion`，并在界面上二次确认。原因放在请求体的 `reason` 中；DELETE 请求没有请求体，改用请求头 `Audit-Reason`（UTF-8 百分号编码，最长 500 字符）。缺少原因返回 400，缺少 `Mfa-Assertion` 返回 401 `mfa_required`。
- **CON-08** 权限目录之外的读操作按以下对应：看板 `/v1/metrics/overview` 用 `orders.read`；内核矩阵 `/v1/kernels` 用 `hosts.*`；返利列表用 `accounts.read`，返利审核用 `credits.adjust`。
- **CON-04** 对外把节点称为 `hosts`，与客户端接口面向用户的 `locations` 区分。
- **CON-05** 下表按资源族列出路径。凡是集合资源，都隐含 `GET` 集合、`POST` 创建，以及 `/{id}` 的 `GET`、`PATCH`、`DELETE`，除非标注为只读。以下集合只提供有意义的操作：会话与设备（查看、吊销）、接入令牌（签发）、订单（查看，以及退款与手动标记支付子资源）、权益（查看；修改只经 `entitlement-adjustments`，spec/11 BIL-03）、应用记录、管理员（只能经邀请加入）、邀请、返利。可修改的单个资源遵守 CONV-13 与 CONV-28（ETag 与 `If-Match`）。
  - ETag 只覆盖可编辑的状态，由资源的版本列（spec/03 3.6）或 `updated_at` 生成；套餐与线路组用版本列，价格行用 `updated_at`。内嵌的子集合（如套餐的在售价格行与线路组关联）属于可编辑状态：子资源变化时在同一事务中把父资源的版本加 1。
  - `LocationGroup.host_count` 是成员数，只随增减成员变化，而增减成员使线路组版本加 1；节点状态变化不改变该字段，也不改变 ETag。
  - 派生计数（如 `Plan.active_entitlement_count`、`LocationGroup.plan_ids`）不参与 ETag：它们随购买或节点变化而变，若参与，编辑时会反复遇到 409 `conflict`。因此 304 响应中的派生计数可能过时，界面需要最新值时不带 `If-None-Match` 重新读取。

| 资源 | 路径 |
|---|---|
| 认证 | `POST /v1/sessions`（本次登录必须完成二次验证）、`DELETE /v1/sessions/current`、`POST /v1/oauth/token`（刷新）、`POST /v1/staff/me/step-up`（取得 `Mfa-Assertion`）、`GET /v1/staff/me`（当前管理员、权限与站点结算货币 `site_currency`，未初始化时为 `null`，CONV-08）、`POST /v1/staff-invitations/acceptance`（接受邀请） |
| 账号 | `/v1/accounts`、`/v1/accounts/{id}`、`/v1/accounts/{id}/suspension`、`/v1/accounts/{id}/sessions`、`/v1/accounts/{id}/devices`、`/v1/accounts/{id}/password-resets`、`/v1/accounts/{id}/data-exports`（导出用户数据，敏感操作） |
| 权益 | `/v1/accounts/{id}/entitlements`、`/v1/accounts/{id}/entitlement-adjustments`、`/v1/accounts/{id}/entitlement-events`（只读） |
| 余额 | `/v1/accounts/{id}/credits`、`/v1/accounts/{id}/credit-entries`（只读）、`/v1/accounts/{id}/credit-adjustments` |
| 套餐与价格 | `/v1/plans`、`/v1/plans/{id}/prices`（价格行只能新建与停售，spec/11 BIL-01）、`/v1/plans/{id}/impact`（影响预览）、`/v1/plans/{id}/location-groups/{group_id}`（PUT 添加；DELETE 移除，敏感操作）、`/v1/plans/{id}/rollouts`（应用到现有用户，spec/11 BIL-02）、`/v1/addon-prices`（M4） |
| 线路组 | `/v1/location-groups`、`/v1/location-groups/{id}/members`、`/v1/location-groups/{id}/impact` |
| 节点 | `/v1/hosts`、`/v1/hosts/{id}/enrollment-tokens`、`/v1/hosts/{id}/key-revocations`（立即吊销节点密钥，spec/20 NODE-19）、`/v1/hosts/{id}/inbounds`、`/v1/hosts/{id}/routes`、`/v1/hosts/{id}/kernel`、`/v1/hosts/{id}/impact` |
| 内核 | `/v1/kernels`（只读：基线矩阵与各节点上报的能力） |
| 订单 | `/v1/orders`、`/v1/orders/{id}/refunds`、`/v1/orders/{id}/manual-payment` |
| 支付 | `/v1/payment-providers`、`/v1/payment-providers/alipay-f2f`、`/v1/payment-providers/alipay-f2f/test`、`/v1/payment-notifications`（只读） |
| 优惠券、兑换码 | `/v1/coupons`、`/v1/coupons/{id}/redemptions`（只读）、`/v1/redeem-code-batches`、`/v1/redeem-code-batches/{id}/redemptions`（只读） |
| 内容与客服 | `/v1/announcements`、`/v1/articles`、`/v1/support/tickets`、`/v1/support/tickets/{id}/messages`、`/v1/support/tickets/{id}/assignment`、`/v1/support/attachments` |
| 通知模板 | `/v1/notification-templates`、`/v1/notification-templates/{id}/preview`（M4） |
| 邀请返利 | `/v1/referral-earnings`、`/v1/referral-earnings/{id}/review`（M5） |
| 设置 | `/v1/settings` |
| 管理员与角色 | `/v1/staff`、`/v1/staff-invitations`、`/v1/roles`（spec/10 AUTH-22；全部操作的 `x-permission` 为 `superadmin`） |
| 审计 | `/v1/audit-logs`（只读）、`/v1/audit-logs/exports`、`/v1/audit-logs/exports/{id}/file`（导出在 backlog M1-02b 实现） |
| 看板 | `/v1/metrics/overview` |

- **CON-09** 审计日志的 `action` 为 `资源.动词`，资源为单数 `snake_case`，使用对外名称（遵守 spec/30 API-01，例如用 `host` 而不是 `node`）；`target_type` 为 `target_id` 所指对象的类型。管理后台按 `action` 显示本地化文案，遇到未知取值时原样显示。下表随各任务补充，新增取值必须先加入本表。

| `action` | `target_type` | `target_id` | 触发 | 差异（`diff`）要点 |
|---|---|---|---|---|
| `session.create` | `account` | 管理员账号 ID | 管理员登录成功（spec/10 AUTH-18） | 无 |
| `session.delete` | `account` | 管理员账号 ID | 管理员登出 | 无 |
| `step_up.create` | `account` | 管理员账号 ID | 完成 step-up（AUTH-19） | 无 |
| `staff.create` | `account` | 新管理员账号 ID | `panel admin create`（AUTH-21）或接受邀请（AUTH-22） | `roles`；接受邀请时 `actor_id` 为接受邀请的账号，另有 `staff_invitation_id`、`inviter_id`、`is_new_account`，重置了凭据时（AUTH-22 第 3 项）另有 `has_credentials_reset: true` |
| `staff.update` | `account` | 管理员账号 ID | 修改管理员角色 | `roles` 前后值 |
| `staff.delete` | `account` | 管理员账号 ID | 移除管理员 | `roles` 前值 |
| `staff_invitation.create` | `staff_invitation` | 邀请 ID | 邀请管理员 | `roles`（不含邮箱，CONV-29） |
| `staff_invitation.revoke` | `staff_invitation` | 邀请 ID | 撤销邀请；超级管理员失去 `superadmin` 时自动撤销（AUTH-22） | 无 |
| `role.create` | `role` | 角色名 | 创建自定义角色 | `description`、`permissions` |
| `role.update` | `role` | 角色名 | 修改自定义角色 | 变化的字段前后值 |
| `role.delete` | `role` | 角色名 | 删除自定义角色 | `permissions` 前值 |
| `credit_adjustment.create` | `account` | 账号 ID | 余额调整（spec/12） | `balance_minor` 前后值 |
| `payment_provider.update` | `payment_provider` | 渠道标识 | 修改支付配置（spec/12） | 变化的字段；`_enc` 只记录“已修改” |
| `audit_export.create` | `audit_export` | 导出任务 ID | 导出审计日志（M1-02b） | 筛选条件 |
| `plan.create` | `plan` | 套餐 ID | 创建套餐（M1-04） | 全部字段，含 `location_group_ids` |
| `plan.update` | `plan` | 套餐 ID | 修改套餐 | 变化的字段前后值 |
| `plan.delete` | `plan` | 套餐 ID | 删除套餐（spec/11 BIL-26） | `name`、`kind`、`tier` 前值 |
| `plan_price.create` | `plan_price` | 价格行 ID | 新建价格行（BIL-01） | `plan_id`、`period`、`period_days`、`amount_minor`、`currency`、`discontinued_price_id`（同一周期旧行被停售时为其 ID，否则为 `null`；只写这一条审计） |
| `plan_price.discontinue` | `plan_price` | 价格行 ID | 停售价格行 | `plan_id`、`period`、`amount_minor` |
| `plan_location_group.create` | `plan` | 套餐 ID | 为套餐添加线路组（BIL-04） | `location_group_id` |
| `plan_location_group.delete` | `plan` | 套餐 ID | 从套餐移除线路组（敏感操作，带 `reason_id`） | `location_group_id` |
| `plan_rollout.create` | `plan` | 套餐 ID | 应用到现有用户（BIL-02，M1-05；敏感操作，带 `reason_id`） | `plan_rollout_id`、`fields`、`target_values`（冻结的目标值）、`affected_account_count`。免费套餐的 `free_grant`、`free_end` 记录不写本条，由 `setting.update` 记录 |
| `entitlement_adjustment.create` | `account` | 账号 ID | 调整权益（spec/11 11.6：`admin_adjust`、`suspend`、`resume`，包括授予新权益；带 `reason_id`） | `entitlement_id`、`event_id`、`event_type`、变化的字段前后值；授予新权益时另有 `plan_id`，同时结束免费权益时另有 `ended_entitlement_id` |
| `setting.update` | `setting` | 空 | 修改系统设置（M1-09）；修改 `free_plan_id` 时为敏感操作，带 `reason_id`（spec/11 BIL-15） | 变化的键前后值（`_enc` 键只记录“已修改”）；修改 `free_plan_id` 时另有 `plan_rollout_id` 与 `plan_rollout_kind` |
| `location_group.create` | `location_group` | 线路组 ID | 创建线路组 | `name`、`description`、`min_tier` |
| `location_group.update` | `location_group` | 线路组 ID | 修改线路组 | 变化的字段前后值 |
| `location_group.delete` | `location_group` | 线路组 ID | 删除线路组（ACS-06） | `name`、`min_tier` 前值 |

- **CON-06** 生成兑换码批次时，明文码只在创建批次的响应中返回一次，并同时提供一次性的 CSV 下载；此后只能导出使用记录（spec/12 ORD-14）。
- **CON-07** 影响预览（`impact`）返回受影响的账号数与节点数，用于 spec/32 UI-03 的“将影响 N 名用户”。切换节点内核时，另外返回与目标内核不兼容的入站。
  - 账号数按不同账号计，口径见 spec/11 BIL-26。线路组 `min_tier` 变更的受影响账号，是关联该线路组、且 `tier` 在新旧 `min_tier` 之间跨越的套餐的持有者；删除线路组的影响恒为 0（仍被引用时删除返回 409）。
  - 节点在 M2 才存在：M1 中 `affected_host_count` 为 0，`credential_additions`、`credential_removals` 省略。
