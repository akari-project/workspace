# 31 管理接口

适用范围：`panel-spec/openapi/console/v1.yaml`（M0-03 编写）、`panel/server/internal/consoleapi`、`panel/web/admin`。

- **CON-01** 位于独立域名（例如 `console.运营者域名`）或配置的路径前缀；命名、分页、错误遵守 spec/02 与 spec/30 API-01。只接受受众为 `console` 的令牌（spec/10 AUTH-21）。
- **CON-02** 每个操作以 `x-permission` 声明所需权限，取值只能来自 spec/10 AUTH-17 的权限目录，由 CI 校验。每个操作至少有一个响应示例，供 Mock 服务使用。
- **CON-03** 所有写操作都写审计日志。spec/10 AUTH-19 列出的敏感操作，要求请求体包含 `reason`、请求头带 `Mfa-Assertion`，并在界面上二次确认。
- **CON-04** 对外把节点称为 `hosts`，与客户端接口面向用户的 `locations` 区分。
- **CON-05** 下表按资源族列出路径。凡是集合资源，都隐含 `GET` 集合、`POST` 创建，以及 `/{id}` 的 `GET`、`PATCH`、`DELETE`，除非标注为只读。可修改的单个资源遵守 CONV-13 与 CONV-28（ETag 与 `If-Match`）。

| 资源 | 路径 |
|---|---|
| 认证 | `POST /v1/sessions`（本次登录必须完成二次验证）、`DELETE /v1/sessions/current`、`POST /v1/oauth/token`（刷新）、`POST /v1/staff/me/step-up`（取得 `Mfa-Assertion`） |
| 账号 | `/v1/accounts`、`/v1/accounts/{id}`、`/v1/accounts/{id}/suspension`、`/v1/accounts/{id}/sessions`、`/v1/accounts/{id}/devices`、`/v1/accounts/{id}/password-resets` |
| 权益 | `/v1/accounts/{id}/entitlements`、`/v1/accounts/{id}/entitlement-adjustments`、`/v1/accounts/{id}/entitlement-events`（只读） |
| 余额 | `/v1/accounts/{id}/credits`、`/v1/accounts/{id}/credit-adjustments` |
| 套餐与价格 | `/v1/plans`、`/v1/plans/{id}/prices`（价格行只能新建与停售，spec/11 BIL-01）、`/v1/plans/{id}/impact`（影响预览）、`/v1/plans/{id}/rollouts`（应用到现有用户，spec/11 BIL-02）、`/v1/addon-prices`（M4） |
| 线路组 | `/v1/location-groups`、`/v1/location-groups/{id}/members`、`/v1/location-groups/{id}/impact` |
| 节点 | `/v1/hosts`、`/v1/hosts/{id}/enrollment-tokens`、`/v1/hosts/{id}/key-revocations`（立即吊销节点密钥，spec/20 NODE-19）、`/v1/hosts/{id}/inbounds`、`/v1/hosts/{id}/routes`、`/v1/hosts/{id}/kernel`、`/v1/hosts/{id}/impact` |
| 内核 | `/v1/kernels`（只读：基线矩阵与各节点上报的能力） |
| 订单 | `/v1/orders`、`/v1/orders/{id}/refunds`、`/v1/orders/{id}/manual-payment` |
| 支付 | `/v1/payment-providers`、`/v1/payment-providers/alipay-f2f`、`/v1/payment-providers/alipay-f2f/test`、`/v1/payment-notifications`（只读） |
| 优惠券、兑换码 | `/v1/coupons`、`/v1/coupons/{id}/redemptions`（只读）、`/v1/redeem-code-batches`、`/v1/redeem-code-batches/{id}/redemptions`（只读） |
| 内容与客服 | `/v1/announcements`、`/v1/articles`、`/v1/support/tickets`、`/v1/support/tickets/{id}/messages`、`/v1/support/tickets/{id}/assignment` |
| 通知模板 | `/v1/notification-templates`、`/v1/notification-templates/{id}/preview`（M4） |
| 邀请返利 | `/v1/referral-earnings`、`/v1/referral-earnings/{id}/review`（M5） |
| 设置 | `/v1/settings` |
| 管理员与角色 | `/v1/staff`、`/v1/staff-invitations`、`/v1/roles`（spec/10 AUTH-22） |
| 审计 | `/v1/audit-logs`（只读）、`/v1/audit-logs/exports` |
| 看板 | `/v1/metrics/overview` |

- **CON-06** 生成兑换码批次时，明文码只在创建批次的响应中返回一次，并同时提供一次性的 CSV 下载；此后只能导出使用记录（spec/12 ORD-14）。
- **CON-07** 影响预览（`impact`）返回受影响的账号数与节点数，用于 spec/32 UI-03 的“将影响 N 名用户”。切换节点内核时，另外返回与目标内核不兼容的入站。
