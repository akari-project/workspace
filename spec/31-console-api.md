# 31 管理接口

适用范围：`panel-spec/openapi/console/v1.yaml`（M0-03 编写）、`panel/server/internal/consoleapi`、`panel/web/admin`。

- **CON-01** 位于独立域名（例如 `console.运营者域名`）或配置的路径前缀；命名、分页、错误遵守 spec/02 与 spec/30 API-01。
- **CON-02** 每个操作以 `x-permission` 声明所需权限（spec/10 AUTH-17）；每个操作至少一个响应示例，供 Mock 服务使用。
- **CON-03** 所有写操作写审计日志；AUTH-19 列出的敏感操作要求请求体包含 `reason`，并在界面二次确认。
- **CON-04** 对外把节点称为 `hosts`，与客户端接口面向用户的 `locations` 区分。

| 资源 | 路径 |
|---|---|
| 账号 | `/v1/accounts`、`/v1/accounts/{id}`、`/v1/accounts/{id}/suspension`、`/v1/accounts/{id}/sessions`、`/v1/accounts/{id}/devices` |
| 权益 | `/v1/accounts/{id}/entitlements`、`/v1/accounts/{id}/entitlement-adjustments`、`/v1/accounts/{id}/entitlement-events` |
| 余额 | `/v1/accounts/{id}/credits`、`/v1/accounts/{id}/credit-adjustments` |
| 套餐与价格 | `/v1/plans`、`/v1/plans/{id}`、`/v1/plans/{id}/prices`、`/v1/plans/{id}/impact` |
| 线路组 | `/v1/location-groups`、`/v1/location-groups/{id}/members` |
| 节点 | `/v1/hosts`、`/v1/hosts/{id}`、`/v1/hosts/{id}/enrollment-tokens`、`/v1/hosts/{id}/inbounds`、`/v1/hosts/{id}/routes`、`/v1/hosts/{id}/kernel` |
| 内核 | `/v1/kernels`（基线矩阵与各节点上报能力） |
| 订单 | `/v1/orders`、`/v1/orders/{id}`、`/v1/orders/{id}/refunds`、`/v1/orders/{id}/manual-payment` |
| 支付 | `/v1/payment-providers`、`/v1/payment-providers/alipay-f2f`、`/v1/payment-providers/alipay-f2f/test`、`/v1/payment-notifications` |
| 优惠券、兑换码 | `/v1/coupons`、`/v1/redeem-code-batches` |
| 内容与客服 | `/v1/announcements`、`/v1/articles`、`/v1/support/tickets` |
| 通知模板 | `/v1/notification-templates` |
| 设置 | `/v1/settings` |
| 管理员与角色 | `/v1/staff`、`/v1/roles` |
| 审计 | `/v1/audit-logs` |
| 看板 | `/v1/metrics/overview` |
