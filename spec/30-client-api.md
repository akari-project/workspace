# 30 客户端接口

适用范围：`panel-spec/openapi/client/v1.yaml`（字段级事实来源）、`panel/server/internal/clientapi`、`panel/web/portal`、`client`。用户中心与自研客户端共用这套接口（用户中心以 Cookie 认证，客户端以 Bearer 令牌）。

## 30.1 命名

- **API-01** 路径参照大型公司公开 API：`/v1/` 加复数名词资源，当前用户的资源在 `/v1/me/`，认证走标准 OAuth 端点，错误为 problem+json。路径、字段、错误码中禁止出现 `subscribe`、`server`、`node`、`traffic`。第三方客户端依赖的标准响应头 `Subscription-Userinfo` 除外。
- **API-02** 不与 V2Board、Xboard、SSPanel 的路径雷同：

| 概念 | 常见面板 | 本项目 |
|---|---|---|
| 登录 | `/api/v1/passport/auth/login` | `POST /v1/sessions` |
| 用户信息 | `/api/v1/user/info` | `GET /v1/me` |
| 订阅 | `/api/v1/client/subscribe?token=`、`/link/{token}` | `GET /v1/me/configuration`；第三方 `GET /v1/configurations/{token}` |
| 节点 | `server`、`node` | `locations` |
| 流量 | `traffic`、`u`/`d` | `usage`，`bytes_used`、`bytes_limit` |
| 公共配置 | `/api/v1/guest/comm/config` | `GET /v1/config` |

## 30.2 接口清单

| 接口 | 说明 |
|---|---|
| `GET /v1/config` | 客户端启动配置：最低版本、公告版本、功能开关、备用域名；Ed25519 签名，公钥内置于客户端 |
| `GET /v1/releases/latest?platform=` | 新版本信息与安装包签名 |
| `POST /v1/accounts`、`POST /v1/accounts/verification` | 注册、邮箱验证 |
| `POST /v1/password-resets`、`PUT /v1/password-resets/{token}` | 找回密码 |
| `POST /v1/sessions` | 登录并注册设备；需要二次验证时返回 `mfa_required` |
| `DELETE /v1/sessions/current` | 登出并吊销本设备凭据 |
| `POST /v1/oauth/token` | 刷新令牌轮换；设备授权轮询（RFC 8628） |
| `POST /v1/oauth/device_authorization` | 电视、路由器等设备的授权码 |
| `POST /v1/device-links`、`POST /v1/device-links/{id}/approve` | 新设备扫码，已登录设备批准 |
| `GET /v1/me`、`DELETE /v1/me` | 账号信息；注销 |
| `GET /v1/me/usage` | 当前周期与每日用量 |
| `GET /v1/me/devices`、`DELETE /v1/me/devices/{id}` | 设备列表；移除 |
| `GET /v1/me/configuration` | 本设备的结构化连接配置（ETag） |
| `GET /v1/me/events` | SSE：`quota_warning`、`plan_changed`、`profile_updated`、`device_revoked`、`session_revoked`、`announcement` |
| `GET /v1/locations` | 可用地区与负载提示 |
| `GET /v1/assets/{digest}` | 按内容寻址的规则集等公共资源，可由 CDN 缓存 |
| `GET /v1/plans` | 在售套餐与价格 |
| `POST /v1/quotes` | 报价（spec/12） |
| `POST /v1/orders`、`GET /v1/orders`、`GET /v1/orders/{id}`、`POST /v1/orders/{id}/cancel` | 下单（返回支付指引）、查询、取消 |
| `GET /v1/me/entitlements`、`PATCH /v1/me/entitlements/current`、`DELETE /v1/me/entitlements/next` | 当前权益与下一段；自动续费开关；取消下一段 |
| `GET /v1/me/credits`、`POST /v1/me/redemptions` | 余额与流水；兑换码 |
| `GET /v1/announcements`、`GET /v1/articles`、`GET /v1/articles/{slug}` | 公告、帮助文档 |
| `GET /v1/support/tickets`、`POST /v1/support/tickets`、`POST /v1/support/tickets/{id}/messages` | 工单 |
| `GET /v1/me/referrals` | 邀请返利 |
| `POST /v1/diagnostics` | 用户主动提交的诊断日志（默认关闭） |

## 30.3 规则

- **API-03** 客户端版本通过标准 `User-Agent`（如 `AppName/1.4.0 (iOS 19.1)`）携带，不使用自定义请求头；版本过低返回 426 `upgrade_required`。
- **API-04** 登录按账号与 IP 限流；写接口按账号限流；公开接口按 IP 限流。
- **API-05** 订单的支付指引为 `payment` 对象：`method`（`alipay_qr` 或测试渠道）、`qr_content`、`expires_at`。客户端渲染二维码，移动端提供“打开支付宝”按钮。
- **API-06** 客户端缓存最后一次 `/v1/me/configuration`；控制面不可达时继续使用，直到凭据在节点上被移除。
- **API-07** SDK：由 `panel-spec` 的 OpenAPI 生成 TypeScript（用户中心）、Dart、Kotlin、Swift 类型与客户端，随规范版本发布。

## 30.4 自研客户端（1.0 之后）

- **API-08** 内嵌 mihomo（GPL-3.0）。从 `/v1/me/configuration` 在本地生成 mihomo 配置；转换逻辑与控制面 mihomo 导出适配器共用 golden 测试数据。
- **API-09** mihomo 不兼容 Xray-core v26.7.11 及以上的 Reality 服务端，也不支持 AnyTLS 与 Reality 组合。客户端只应连接 sing-box 内核节点上的 Reality 入站（spec/21 AGT-11）。
- 令牌存系统安全存储；启动配置必须验签。
