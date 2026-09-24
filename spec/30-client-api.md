# 30 客户端接口

适用范围：`panel-spec/openapi/client/v1.yaml`（字段级事实来源）、`panel/server/internal/clientapi`、`panel/web/portal`、`client`。用户中心与自研客户端共用这套接口：用户中心以 Cookie 认证，客户端以 Bearer 令牌认证。

## 30.1 命名

- **API-01** 路径参照大型公司的公开 API：`/v1/` 加复数名词资源，当前用户的资源在 `/v1/me/` 下，认证走标准 OAuth 端点，错误为 problem+json（OAuth 端点例外，见 CONV-16）。
  - 路径、字段、枚举值、错误码中禁止出现 `subscribe`、`server`、`node`、`traffic`。例外只有第三方客户端依赖的标准响应头 `Subscription-Userinfo`。
  - `panel-spec` 的 CI 对两份 OpenAPI 做禁用词检查。
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

**公共与启动**

| 接口 | 说明 |
|---|---|
| `GET /v1/config` | 客户端启动配置：最低版本、公告版本、功能开关（`features`，spec/13 OPS-08）、注册策略（可选字段 `registration_policy`，缺省时前端按 `open` 处理，以服务端校验为准；不下发域名名单）、备用域名；修改注册策略后重新生成签名与 ETag；用 Ed25519 签名，签名对象为 `payload` 按 RFC 8785（JCS）规范化后的字节，带 `key_id`，公钥内置于客户端（CONV-30） |
| `GET /v1/releases/latest?platform=` | 新版本信息与安装包签名 |
| `GET /v1/assets/{digest}` | 按内容寻址的规则集等公共资源，可以由 CDN 缓存 |
| `GET /v1/plans` | 在售套餐与价格，以及加购项价格 |
| `GET /v1/locations` | 可用地区、负载提示、倍率（`usage_multiplier`） |

**注册、登录与会话**

| 接口 | 说明 |
|---|---|
| `POST /v1/accounts` | 注册，返回 202（spec/10 AUTH-01） |
| `POST /v1/accounts/verification`、`POST /v1/accounts/verification/resend` | 邮箱验证、重新发送验证码（AUTH-03） |
| `POST /v1/password-resets`、`POST /v1/password-resets/confirmation` | 发起与确认找回密码（AUTH-04） |
| `POST /v1/sessions` | 登录并注册设备；需要二次验证时返回 `mfa_required`，第二步提交 `challenge_id`（AUTH-20） |
| `POST /v1/sessions/nonces` | 取得一次性 nonce，供设备复用时签名（AUTH-10） |
| `DELETE /v1/sessions/current` | 登出，并吊销本设备及其凭据（AUTH-10） |
| `POST /v1/oauth/token` | 刷新令牌轮换；设备授权与扫码登录的轮询（AUTH-24） |
| `POST /v1/oauth/device_authorization` | 电视、路由器等设备取得授权码 |
| `POST /v1/me/device-authorizations` | 用户中心提交 `user_code` 批准设备授权 |
| `POST /v1/device-links`、`GET /v1/device-links/{id}`、`POST /v1/device-links/{id}/approve` | 新设备发起扫码登录；批准方查看请求设备信息；带校验数字批准（AUTH-24） |
| `POST /v1/deletion-cancellations` | 用邮件中的令牌撤销注销（AUTH-05） |

**账号与安全**

| 接口 | 说明 |
|---|---|
| `GET /v1/me`、`PATCH /v1/me`、`DELETE /v1/me` | 账号信息；修改语言、时区、自动续费开关 `is_auto_renew`（spec/11 BIL-19）；注销 |
| `POST /v1/me/reauthentications` | 重新验证，提交密码或二次验证中的一种（AUTH-23） |
| `PUT /v1/me/password` | 修改密码；成功后吊销除当前会话外的全部会话 |
| `POST /v1/me/mfa/totp`、`POST /v1/me/mfa/totp/activation`、`DELETE /v1/me/mfa/totp`、`POST /v1/me/mfa/recovery-codes` | 开始绑定 TOTP、确认绑定并取得恢复码、停用、重新生成恢复码 |
| `POST /v1/me/passkeys/options`、`POST /v1/me/passkeys`、`GET /v1/me/passkeys`、`DELETE /v1/me/passkeys/{id}` | Passkey（可以延后到 M4） |
| `GET /v1/me/devices`、`DELETE /v1/me/devices/{id}` | 设备与登录会话列表（含 web 设备，只返回未吊销的，可以不分页）；移除 |
| `GET /v1/me/notification-preferences`、`PUT /v1/me/notification-preferences` | 通知偏好（spec/13 OPS-05） |

**连接与用量**

| 接口 | 说明 |
|---|---|
| `GET /v1/me/configuration` | 本设备的结构化连接配置（ETag）；未下发凭据时返回状态说明，如 `device_limit_reached` |
| `GET /v1/me/export-link`、`POST /v1/me/export-link/rotation` | 第三方导入链接；重置（spec/10 AUTH-16） |
| `GET /v1/me/usage` | 当前周期用量、每日用量、按地区分布 |
| `GET /v1/me/events` | SSE 事件：`quota_warning`、`plan_changed`、`profile_updated`、`device_revoked`、`session_revoked`、`announcement` |

**购买与权益**

| 接口 | 说明 |
|---|---|
| `POST /v1/quotes` | 报价（spec/12）：`price_id` 或 `addon_price_id`、优惠码、是否使用余额 |
| `POST /v1/orders`、`GET /v1/orders`、`GET /v1/orders/{id}`、`POST /v1/orders/{id}/cancel` | 下单（返回支付指引）、查询、取消 |
| `GET /v1/me/entitlements`、`DELETE /v1/me/entitlements/next` | 当前权益（含加购项与只读的 `is_auto_renew`）与下一段；取消下一段 |
| `GET /v1/me/credits`、`GET /v1/me/credit-entries` | 余额；余额流水（分页） |
| `POST /v1/me/redemptions` | 兑换码 |

**运营模块**（模块关闭时返回 404，spec/13 OPS-08）

| 接口 | 说明 |
|---|---|
| `GET /v1/announcements`、`GET /v1/articles`、`GET /v1/articles/{slug}` | 公告、帮助文档（公开；含用户变量的渲染见 spec/13 OPS-12） |
| `GET /v1/support/tickets`、`POST /v1/support/tickets`、`GET /v1/support/tickets/{id}`、`POST /v1/support/tickets/{id}/messages`、`POST /v1/support/attachments`、`GET /v1/support/attachments/{id}` | 工单列表（分页）、创建、详情与消息、回复、上传与下载附件 |
| `GET /v1/me/referrals` | 邀请返利 |
| `POST /v1/diagnostics` | 用户主动提交的诊断日志（默认关闭） |

## 30.3 规则

- **API-03** 客户端版本通过标准 `User-Agent`（如 `AppName/1.4.0 (iOS 19.1)`）携带，不使用自定义请求头。只有匹配 `^<AppName>/\d+\.\d+\.\d+` 的请求才与 `/v1/config` 的 `min_version[platform]` 比较，版本过低返回 426 `upgrade_required`；浏览器与第三方客户端永不返回 426。
- **API-04** 限流默认值（可配置），超限返回 429 并带 `Retry-After`：

| 对象 | 默认值 |
|---|---|
| 登录 | 见 spec/10 AUTH-09 |
| 找回密码与验证码发送 | 每个邮箱每小时 3 次，每个 IP 每小时 10 次 |
| 已认证的写接口 | 每个账号每分钟 60 次 |
| 公开接口 | 每个 IP 每分钟 120 次 |
| 第三方配置导出 | 见 spec/23 EXP-01 |

  按 IP 限流时，真实客户端 IP 的取得方式见 spec/40 DEP-13。
- **API-05** 订单的支付指引为 `payment` 对象：`method`（`alipay_qr` 或测试渠道）、`qr_content`、`expires_at`。客户端渲染二维码，移动端提供“打开支付宝”按钮。
- **API-06** 客户端缓存最后一次 `/v1/me/configuration`；控制面不可达时继续使用，直到凭据在节点上被移除。
- **API-07** SDK：由 `panel-spec` 的 OpenAPI 生成 TypeScript（用户中心）、Dart、Kotlin、Swift 类型与客户端，随规范版本发布。
- **API-10** OpenAPI 必须覆盖 spec/32 各页面需要的全部字段（例如用量的按地区分布、权益的加购项），不能只覆盖 30.2 的接口清单。

## 30.4 自研客户端（1.0 之后）

- **API-08** 内嵌 mihomo（GPL-3.0），从 `/v1/me/configuration` 在本地生成 mihomo 配置；转换逻辑与控制面的 mihomo 导出适配器共用 golden 测试数据。
- **API-09** mihomo 不兼容 Xray-core v26.7.11 及以上的 Reality 服务端，也不支持 AnyTLS 与 Reality 的组合。客户端只应连接 sing-box 内核节点上的 Reality 入站（spec/21 AGT-11）；导出时的处理见 spec/23 EXP-08。
- 令牌存入系统安全存储；启动配置必须验签。
