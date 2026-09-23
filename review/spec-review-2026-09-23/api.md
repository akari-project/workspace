# 账号、接口与前端组明细：spec/10、13、30、31、32

核对依据：spec/00、01、02、03、11、12、22、23、40；`panel-spec/openapi/client/v1.yaml`；`panel/server/migrations/00001_init.sql`；backlog M0/M1。`openapi/console/v1.yaml` 尚不存在，spec/31 只能与 spec/10、spec/32 和迁移文件对照。

编号 A-xx 与主报告一致。每条都经过发现者自我反驳。全部条目都已完成独立对抗复核，结论标在标题后，详见主报告第 3、7、8 节。

---

## 严重

### A-01 用户中心登录也会注册设备，设备上限可能把用户锁在门外 ｜矛盾｜严重（复核维持，见主报告 3.1）
- 位置：spec/00「设备」；spec/10 AUTH-10、AUTH-13、AUTH-14；spec/30 `DELETE /v1/sessions/current`。与 E-32 合并。
- 原文：「登录同时注册设备」；「设备数超过权益的设备上限时拒绝注册新设备」
- 问题：
  - 浏览器登录会占用一个设备名额，还会签发一条用不上的代理凭据。
  - 登出后设备记录保留，重新登录时没有复用规则，反复登录登出会让设备数一直累加。
  - 设备数达到上限后连登录都会失败，用户也就无法进入界面移除设备。
  - 免费账号的设备上限没有定义。
  - 降级后已有设备超出新上限时如何处理，没有定义。
- 建议修改：
  > **AUTH-10a** `platform=web` 的登录不创建代理凭据，也不计入设备上限。
  >
  > **AUTH-10b** 客户端登录时携带已有 `device_id` 及公钥签名，服务端据此复用原设备记录。登出时吊销该设备的凭据，并释放名额。
  >
  > **AUTH-14a** 设备数已达上限时，登录照常成功，但不下发代理凭据；响应中 `configuration` 为 `device_limit_reached`，用户可在登录后移除其他设备。
  >
  > **AUTH-14b** 免费账号的设备上限由 `free_device_limit` 配置，默认 1。设备数超出上限时，按 `last_seen_at` 保留最近使用的设备，其余设备不下发凭据。

### A-02 用户中心页面需要的客户端接口大量缺失 ｜遗漏｜严重 → 复核后降为重要（见主报告 3.2）
- 位置：spec/32 32.2；spec/30 30.2；spec/10 AUTH-03、AUTH-11、AUTH-16；spec/13 OPS-05；spec/12 ORD-01
- 问题：以下功能都没有接口：修改密码、TOTP、恢复码、Passkey、列出和吊销会话、通知偏好、导出链接的读取与重置、重发验证码、更换邮箱（迁移里已有 `email_change`）、流量包报价、读取注册策略。M0-03 的交付要求「补齐 spec/30 全部接口」，所以清单里没有的接口不会被实现。
- 建议修改：在 30.2 增加以下接口：

  | 接口 | 说明 |
  |---|---|
  | `PUT /v1/me/password` | 修改密码，需提供当前密码；成功后吊销其他会话 |
  | `POST /v1/me/email-changes`、`POST /v1/me/email-changes/verification` | 更换邮箱，验证码发往新邮箱，同时通知旧邮箱 |
  | `POST /v1/accounts/verification/resend` | 重发验证码，每分钟 1 次、每天 10 次 |
  | `POST /v1/me/mfa/totp`、`…/totp/activation`、`DELETE /v1/me/mfa/totp`、`POST /v1/me/mfa/recovery-codes` | TOTP 与恢复码 |
  | `POST /v1/me/passkeys/options`、`POST /v1/me/passkeys`、`GET /v1/me/passkeys`、`DELETE /v1/me/passkeys/{id}` | Passkey |
  | `GET /v1/me/sessions`、`DELETE /v1/me/sessions/{id}` | 登录会话 |
  | `GET`、`PUT /v1/me/notification-preferences` | 通知偏好 |
  | `GET /v1/me/export-link`、`POST /v1/me/export-link/rotation` | 导出链接与重置 |
  | `POST /v1/quotes` 增加 `addon_id` | 流量包报价（与 B-06 合并） |

  另加一条：修改密码、更换邮箱、停用二次验证、删除 Passkey、注销账号，都要求 5 分钟内重新验证过身份。

### A-03 二次验证登录流程不完整，TOTP 可被暴力猜测 ｜矛盾/遗漏｜严重 → 复核后降为重要（见主报告 3.2）
- 位置：spec/10 AUTH-11；spec/02 `mfa_required`；OpenAPI `createSession`、`Problem`
- 问题：
  - Problem 响应中没有 `challenge_id`。
  - 登录请求只接受 `totp_code`，不能用 Passkey 或恢复码登录。
  - 第二步是否需要重新提交密码，没有规定。
  - challenge 没有有效期和尝试次数上限。
  - 没有禁止重复使用同一个 TOTP 码。
- 建议修改：
  > **AUTH-11a** 需要二次验证时返回 401 `mfa_required`，附 `challenge_id`（有效 5 分钟）与 `methods`。第二步只提交 `challenge_id` 加 totp、webauthn、recovery 三者之一，不再提交密码。每个 challenge 最多尝试 5 次，失败次数计入 AUTH-09。同一时间窗内已用过的 TOTP 码不可再用。恢复码用后作废，剩余少于 3 个时发送通知。

### A-04 管理员登录与管理接口的令牌未定义，二次验证可被绕过 ｜遗漏｜严重（复核维持，见主报告 3.1）
- 位置：spec/10 AUTH-12；spec/31 CON-01；spec/32 32.3
- 问题：
  - 没有管理员登录接口。
  - 令牌的签发方式和受众未定义。
  - AUTH-12 只要求账号「已启用」二次验证，没有要求本次会话完成过二次验证。因此，设备授权、扫码登录签发的令牌，以及启用二次验证之前签发的令牌，都可能进入管理接口。
  - 首个超级管理员如何创建，没有规定。
- 建议修改：
  > **AUTH-12a** 管理接口只接受受众为 `console` 的令牌。这种令牌只能由管理域的 `POST /v1/sessions` 签发，且本次登录必须完成二次验证（`amr` 声明）。设备授权和扫码登录签发的令牌受众只能是 `client`。管理会话的刷新令牌最长 12 小时，空闲 30 分钟失效。管理员的角色或二次验证变更时，吊销其全部会话。首个超级管理员通过 `panel admin create --email` 创建，首次登录时强制绑定 TOTP。

## 重要

### A-05 帮助文档渲染用户变量，而文档接口是公开的 ｜矛盾｜重要 → 复核后降为一般（见主报告 8.1）
- 位置：spec/13 13.4；spec/30 `GET /v1/articles/{slug}`；OpenAPI `security: []`
- 影响：如果渲染结果被 CDN 或共享缓存保存，用户的导出令牌可能泄露。
- 建议修改：
  > 未登录时，用户变量渲染为占位提示。含用户变量的响应带 `Cache-Control: private, no-store`，不参与共享的 ETag 缓存。导入链接默认遮挡显示。

### A-06 访问令牌的吊销、刷新令牌的有效期、签名密钥的轮换都未定义 ｜遗漏/无法测试｜重要（复核维持，见主报告 8.1）
- 位置：spec/10 AUTH-04 至 AUTH-07；spec/32「强制下线」
- 建议修改：
  > **AUTH-06a** 吊销会话时把会话 ID 写入 Valkey 吊销集合（TTL 15 分钟），所有接口校验 `sid`，吊销在 1 秒内生效。SSE 连接收到 `session_revoked` 后关闭。
  >
  > **AUTH-07a** 刷新令牌空闲 30 天失效，从签发起最长 90 天。
  >
  > **AUTH-06b** 签名密钥轮换后，旧密钥继续用于验签 30 分钟。

### A-07 刷新令牌的重用检测会误伤并发刷新 ｜遗漏｜一般（复核维持，见主报告 8.1）
- 位置：spec/10 AUTH-07
- 建议修改：
  > **AUTH-07b** 同一刷新令牌在轮换后 10 秒内再次出现，且 IP 前缀与 UA 相同时，返回相同的新令牌对，不视为泄露。

### A-08 限流可被用于枚举邮箱或锁死他人账号，且没有具体数值 ｜遗漏/无法测试｜重要（复核维持，见主报告 8.1）
- 位置：spec/10 AUTH-09；spec/30 API-04；OpenAPI `createAccount`、`requestPasswordReset`
- 建议修改：
  > **AUTH-09a** 不存在的邮箱同样受冷却限制，并返回相同的 429。冷却期间仍允许走找回密码流程，以及使用已完成二次验证的会话，避免账号被他人锁死。邮箱不存在时，用虚拟哈希执行一次 argon2id，保持耗时一致。
  >
  > **AUTH-01a** 注册时邮箱已存在，照样返回「已发送」，并向该邮箱发送「有人尝试注册」的提醒。
  >
  > **API-04** 默认限额：登录每 IP 每分钟 20 次；找回密码与验证码每邮箱每小时 3 次、每 IP 每小时 10 次；写接口每账号每分钟 60 次；公开接口每 IP 每分钟 120 次。

### A-09 扫码登录与设备授权流程不完整，容易被钓鱼 ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/10 AUTH-10；spec/30 `device-links`、`oauth/device_authorization`
- 问题：
  - 用 `poll_token` 换取令牌的接口没有定义。
  - 批准时不显示任何确认信息：攻击者把自己生成的二维码发给受害者，受害者一点批准，攻击者就登录了受害者的账号。
  - 没有输入 `user_code` 的页面。
  - 这两种方式签发的令牌是否计入设备上限，没有规定。
- 建议修改：
  > **AUTH-10c** 批准界面显示设备的平台、型号、IP 前缀、地区，并显示 2 位校验数字，用户须选出与新设备屏幕上相同的数字。新设备通过 `POST /v1/oauth/token` 的 device_code 授权类型轮询取得令牌。用户中心提供 `/activate` 页面，调用 `POST /v1/me/device-authorizations`。这两种方式签发的令牌受众为 `client`，计入设备上限。

### A-10 重置导出令牌时没有同时轮换共用代理凭据 ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/10 AUTH-13、AUTH-16；spec/23
- 影响：导出链接泄露后，拿到配置的人仍能继续使用代理。
- 建议修改：
  > **AUTH-16a** 重置导出令牌时，在同一事务中吊销并重新生成共用凭据，写入 `credential.rotated` 事件，由协调器更新各节点。

### A-11 手动标记支付：AUTH-19 与 ORD-12 规定不一致 ｜矛盾｜重要 → 复核后降为一般（见主报告 8.1）
- 位置：spec/10 AUTH-19；spec/12 ORD-12。与 B-09 合并。
- 问题：AUTH-19 允许自定义角色获得这项权限，ORD-12 规定只有 superadmin 可以操作。
- 建议修改（两种写法，二选一）：
  > 在 AUTH-19 末尾写明「手动标记支付只允许 superadmin，任何角色都不能被授予」；或者设立权限 `orders.manual_payment`，内置角色中只有 superadmin 拥有。

### A-12 缺少权限目录；迁移中的 `nodes.*` 与接口的 `hosts` 不一致；没有防提权规则 ｜遗漏/矛盾/无法测试｜重要（复核维持，见主报告 7.1）
- 位置：spec/10 AUTH-17；spec/31 CON-02；迁移中 roles 的种子数据
- 建议修改：
  > **AUTH-17a** 在 spec/10 附权限目录表（`accounts.read`、`accounts.adjust`、`hosts.*`、`location-groups.*`、`kernels.write`、`plans.*`、`coupons.*`、`orders.refund`、`credits.adjust`、`payments.configure`、`content.*`、`tickets.*`、`settings.write`、`staff.*`、`audit.read`），列出内置角色拥有的权限。`x-permission` 只能取目录中的值，由 CI 校验。
  >
  > **AUTH-17b** 内置角色不可修改；自定义角色的权限必须是目录的子集。只有 superadmin 能分配角色，且不能授予超出自身的权限。系统至少保留一个 superadmin。邀请管理员使用 72 小时有效的一次性链接。

### A-13 「二次确认」只在界面上做，服务端无法验证 ｜无法测试/遗漏｜重要 → 复核后降为一般（见主报告 7.1）
- 位置：spec/10 AUTH-19；spec/31 CON-03；spec/32 UI-03
- 建议修改：
  > **AUTH-19a** 敏感操作要求请求头 `Mfa-Assertion`，其值为 5 分钟内通过 `POST /v1/staff/me/step-up` 完成验证后得到的令牌；缺少或过期时返回 401 `mfa_required`。敏感操作清单增加：角色与管理员变更、重置用户密码、吊销节点密钥、应用到现有用户、导出数据。

### A-14 许多错误情形没有错误码；OAuth 端点的错误格式与 CONV-16 冲突 ｜遗漏/矛盾｜重要 → 复核后降为一般（见主报告 7.1）
- 位置：spec/02 CONV-16；OpenAPI `issueToken`
- 建议修改：在错误码表中增加以下各行：

  | code | HTTP | 含义 |
  |---|---|---|
  | `registration_closed` | 403 | 注册已关闭 |
  | `invite_required` | 403 | 需要邀请码 |
  | `code_invalid` | 400 | 验证码、链接、兑换码或优惠码无效 |
  | `account_suspended` | 403 | 账号已暂停 |
  | `module_disabled` | 404 | 模块已关闭 |
  | `payload_too_large` | 413 | 请求体过大 |
  | `invalid_state` | 409 | 当前状态不允许该操作 |

  并注明：`/v1/oauth/*` 按 RFC 6749 §5.2 与 RFC 8628 返回 `{error, error_description}`，这是 CONV-16 唯一的例外。

### A-15 注销账号的细节未定义 ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/10 AUTH-05；OpenAPI `DELETE /v1/me`、`Me.status: deleting`
- 建议修改：
  > **AUTH-05a** 注销需在 5 分钟内重新验证身份。30 天内可以通过邮件链接撤销注销。注销时，生效中的权益立即结束，不退款，余额作废，界面须提示。删除数据后，邮箱替换为哈希值，原邮箱可以重新注册。管理员账号，以及有 pending 或 paid 订单的账号不能注销，返回 409 `invalid_state`。

### A-16 账号暂停与权益暂停的语义未定义 ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/31 `/v1/accounts/{id}/suspension`；spec/02 `account.suspended`；spec/11 `suspended`。与 B-17 相关。
- 建议修改：
  > **AUTH-20** 账号暂停时吊销全部会话与凭据，登录返回 403 `account_suspended`，并写入 `account.suspended` 事件，权益照常计时。权益暂停只停止下发凭据，用户仍可登录。两种暂停都必须填写 reason，并记审计日志。

### A-17 字段 `traffic_multiplier` 违反 API-01 ｜矛盾｜重要
- 与 E-02 合并。内容见主报告与 E-02。

### A-18 管理后台页面需要的管理接口缺失；兑换码「只存哈希」却要求「导出」 ｜遗漏/矛盾｜重要 → 复核后降为一般（见主报告 7.1）
- 位置：spec/31 资源表；spec/32 32.3；spec/10 AUTH-18；spec/11 BIL-02、BIL-04、ACS-06；spec/12 ORD-14；spec/13 OPS-03、OPS-07
- 建议修改：
  - 资源表补充：`/v1/location-groups/{id}` 与 `…/impact`、`/v1/accounts/{id}/password-resets`、`/v1/plans/{id}/rollouts`、`/v1/hosts/{id}/impact`、`/v1/hosts/{id}/key-rotations`、`/v1/audit-logs/exports`、`/v1/support/tickets/{id}` 与 `…/messages`、`/v1/notification-templates/{id}/preview`、`/v1/referral-earnings` 与 `…/review`、优惠券和兑换码的 `redemptions`。
  - 所有集合资源都提供 `/{id}` 的 GET、PATCH、DELETE。
  - 兑换码明文只在生成批次时返回一次，并提供一次性 CSV 下载。

### A-19 工单接口不完整，附件缺少安全约束 ｜遗漏｜重要（复核维持，见主报告 8.1）
- 位置：spec/13 13.3；spec/30 工单接口
- 建议修改：
  - 新增 `GET /v1/support/tickets/{id}`（包含消息）和 `POST /v1/support/attachments`。
  - 附件只允许 PNG、JPEG、WebP，按文件内容识别类型，每条消息最多 4 个。
  - 下载需要鉴权，响应带 `Content-Disposition: attachment` 和 `nosniff`。
  - 状态流转：用户回复后变为 open，客服回复后变为 waiting_user，任一方都可以关闭，关闭后 30 天内用户回复即重新打开。

### A-20 返利的基数、退款追回、可疑判定、邀请码含义都未定义 ｜遗漏/无法测试｜重要 → 复核后降为一般（见主报告 8.1）
- 位置：spec/13 13.5、OPS-06、OPS-07；spec/10 AUTH-02
- 建议修改：
  > **OPS-06a** 返利基数为渠道实付金额，不含余额抵扣与优惠。部分退款时，按比例作废冻结中的返利。返利已转入余额的，写入负向流水，余额允许为负。
  >
  > **OPS-07a** 以下情况判为可疑：注册 IP 的 /24 或 /48 前缀相同；`buyer_id` 相同（存入 `orders.payer_ref_hash`）；24 小时内注册数超过 N。
  >
  > **AUTH-02a** 「仅邀请码」注册接受账号邀请码或管理员生成的注册码；返利模块关闭时，账号邀请码仍可用于注册。

## 一般

### A-21 找回密码的令牌放在路径中，会被写进日志 ｜遗漏/矛盾｜一般 → 复核后降为轻微（见主报告 7.1）
- 位置：spec/30 `PUT /v1/password-resets/{token}`；spec/02 CONV-24
- 建议修改：
  > 改为 `POST /v1/password-resets/confirmation`，请求体为 `{token, new_password}`。邮件链接用 `#token=`（片段）传递令牌。令牌为 32 字节随机值，只存 SHA-256。发起新的找回请求时，旧令牌作废。CONV-23 的 `route` 字段记录路由模板。

### A-22 列表没有分页，余额流水没有上限 ｜矛盾｜一般（复核维持，见主报告 7.1）
- 建议修改：
  > 可能超过 200 条的列表一律使用游标分页。余额流水拆分为 `GET /v1/me/credits/entries`。

### A-23 `idempotency_keys` 不支持匿名请求 ｜矛盾｜一般
- 与 E-05 合并。

### A-24 自动续费开关：接口放在权益上，数据库放在账号上 ｜矛盾｜一般 → 复核后降为轻微（见主报告 7.1）
- 与 B-07 合并。
- 建议修改：
  > 开关属于账号，改为 `PATCH /v1/me {is_auto_renew}`；`Entitlement.is_auto_renew` 保留为只读镜像。

### A-25 通知分类、「异常登录」的判定、两个 outbox 的关系 ｜无法测试/矛盾｜一般（复核维持，见主报告 8.1）
- 两个 outbox 部分与 E-08 合并。
- 建议修改：
  > **OPS-04a** 通知分四类，只有提醒类与营销类可以关闭：
  > - 安全类：验证码、找回密码、新增设备、异常登录、密码与二次验证变更；
  > - 交易类：支付成功、开通、到期提醒；
  > - 提醒类：流量 80% 与 100%；
  > - 营销类：公告。
  >
  > 异常登录的定义：本次登录的国家与 ASN，和最近 30 天内的所有成功登录都不相同。验证码类通知的重试时长以验证码有效期为上限。

### A-26 模块关闭时接口的表现 ｜遗漏｜一般（复核维持，见主报告 8.1）
- 建议修改：
  > 模块关闭时返回 404 `module_disabled`。`/v1/config.features` 中列出各模块的布尔值。

### A-27 AUTH-02「验证码接口预留」、API-03 对 UA 的判定 ｜无法测试｜一般 → 复核后降为轻微（见主报告 8.1）
- 建议修改：
  > **AUTH-02a** 定义 `CaptchaVerifier` 接口，默认实现始终通过。
  >
  > **API-03a** 只对匹配 `^<AppName>/\d+\.\d+\.\d+` 的 UA 返回 426。

### A-28 契约草案与 spec/30、31 不一致 ｜矛盾｜一般 → 复核后降为轻微（见主报告 8.1）
- 问题：
  - OpenAPI 缺少以下接口：password-resets 的 PUT、articles/{slug}、ticket messages、me/referrals、diagnostics。
  - `Usage` 没有按地区的统计；`Entitlement` 没有流量包字段。
  - M0-03 中写的「第 18.4 节」不存在，应为 spec/31。这一点与 E 组的范围外发现合并。
- 建议修改：补齐上述接口；`Usage` 增加 `by_location[]`，`Entitlement` 增加 `addons[]`；把 M0-03 中的引用改为 spec/31。

### A-29 审计日志缺少 `reason` 与 `request_id` ｜矛盾｜一般 → 复核后降为轻微（见主报告 8.1）
- 建议修改：
  > **AUTH-18** 增加 `reason`（敏感操作必填）和 `request_id`。`_enc` 与 `_hash` 字段只记录「已修改」，不记录取值。

### A-30 设备公钥的用途未定义 ｜无法测试｜一般 → 复核后降为轻微（见主报告 8.1）
- 建议修改：
  > **AUTH-10d** 设备公钥使用 Ed25519，只用于两件事：重新登录时证明是同一台设备，以及扫码批准时签名。

## 已排除的疑点
- `/v1/oauth/device_authorization` 属于 RFC 8628 的惯用路径，是例外。
- 单例资源用单数名称，不违反 CONV-09。
- 客户端接口与管理接口的路径同名，由 CON-01 按域名或前缀区分。
- `servers:` 是 OpenAPI 的关键字，「Server-Sent Events」是描述文字，都不违反 API-01。
- `Subscription-Userinfo` 在 API-01 中已列为例外。
- `alipay_f2f` 与 `alipay_qr` 是两个不同的概念。
- 注册接口返回 `Me`：在 A-01 修正后，流程可以走通。
- 找回密码接口始终返回 202，不会泄露邮箱是否存在。
- 邮箱验证码每个码最多尝试 5 次，风险可以接受。
- 机器模式属于 M5。
- `X-Frame-Options` 已在 DEP-05 规定。
- `operator` 与 `accounts.adjust` 一致。
- 旧密码哈希的迁移属于 1.0 之后的工作。
