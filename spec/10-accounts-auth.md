# 10 账号、认证与权限

适用范围：`panel/server/internal/auth`、`internal/account`、`internal/rbac`；接口见 spec/30、spec/31。

## 10.1 注册与账号

- **AUTH-01** 注册使用邮箱与密码，邮箱按小写归一化后唯一。密码用 argon2id（内存 64 MiB、迭代 3、并行 1，可配置），长度 8–128。
  - 为防止枚举账号，邮箱已注册时注册接口返回与成功时相同的 202 响应（“验证邮件已发送”），不创建账号，改为向该邮箱发送“有人尝试用你的邮箱注册”的通知。
- **AUTH-02** 注册策略可配置：开放、仅邀请码、关闭；另可设邮箱域名白名单或黑名单。
  - “仅邀请码”接受两种码，都通过 `invite_code` 字段提交：账号邀请码（`accounts.referral_code`），以及管理员生成的注册码。返利模块关闭时，账号邀请码仍可用于注册，但不产生返利。
  - 策略与域名名单保存在 `settings`（键名见 spec/03 3.6）。两个名单可以同时设置：邮箱域名（`@` 之后的部分，小写，精确匹配）在黑名单中即拒绝；白名单非空时，不在白名单中也拒绝。被拒绝时返回 400，`errors[].code` 为 `not_allowed`。
  - 策略或任一名单的值异常（如直接改库写入了非法值）时，有效注册策略为关闭，`/v1/config` 同样下发 `closed`（spec/03 3.6）；缺键时按开放与空名单。
  - 注册关闭，或策略要求邀请码而请求未提供时，返回 403 `registration_closed`；邀请码无效时返回 400，`errors[].code` 为 `invalid_code`。
  - 人机验证预留：定义 `CaptchaVerifier` 接口，注册、登录、找回密码请求可以携带 `captcha_token`；默认实现总是通过。
- **AUTH-03** 邮箱验证码为 6 位数字，15 分钟有效，最多尝试 5 次。重新发送每个账号每分钟 1 次、每天 10 次；发送新码后旧码作废。已登录时只提交验证码，未登录时提交邮箱与验证码。未验证邮箱的账号可以登录，但下单返回 `email_unverified`。
- **AUTH-04** 找回密码：
  - 发送一次性链接，30 分钟有效。链接中的令牌为 32 字节 CSPRNG 随机值（base64url），放在 URL 片段（`#token=`）中，只存 SHA-256。
  - 同一账号发起新的找回请求时，旧令牌立即作废。
  - 确认接口为 `POST /v1/password-resets/confirmation`，请求体为 `{token, new_password}`。
  - 重置成功后吊销该账号的全部会话。
  - 无论邮箱是否存在，发起接口都返回 202。
- **AUTH-05** 注销账号：
  - 需要 5 分钟内完成过重新验证（AUTH-23）。
  - 下列账号不能注销，返回 409 `invalid_state`：持有管理员角色的账号；存在 `pending` 订单或已支付未开通订单的账号。
  - 发起后，账号进入 `deleting`：立即吊销全部会话与代理凭据；生效中的权益立即结束，不退款；余额作废（界面必须事先提示），写入 `account.status_changed` 事件。
  - 30 天内，用户可以凭邮件中的撤销链接恢复账号。恢复后需要重新登录，代理凭据重新生成，已结束的权益与作废的余额不恢复。
  - 30 天后删除个人数据：邮箱替换为不可逆的哈希，原邮箱可以重新注册；销毁该账号的派生密钥（CONV-29）；订单与账务记录脱敏保留。

## 10.2 登录与会话

- **AUTH-06** 访问令牌为 PASETO v4.public，有效期 15 分钟，令牌头带 key id，令牌中带会话 ID `sid` 与受众 `aud`（`client` 或 `console`）。
  - 会话被吊销时，把 `sid` 写入 Valkey 吊销集合（TTL 15 分钟）；所有接口都校验 `sid` 不在集合内，吊销在 1 秒内生效。
  - SSE 连接在会话被吊销或令牌过期时，发送 `session_revoked` 后关闭。
  - 签名密钥轮换后，旧密钥继续用于验签 30 分钟，然后下线（CONV-30）。
- **AUTH-07** 刷新令牌：
  - 为不透明随机值，服务端只存哈希，每次使用即轮换。
  - 客户端会话空闲 30 天失效，自首次登录起 90 天绝对失效。管理会话的有效期见 AUTH-21。
  - 已轮换的刷新令牌再次出现时，吊销整条会话链（`sessions.parent_id`）。例外：轮换后 10 秒内再次出现，且来源 IP 前缀与 User-Agent 相同时，返回与第一次相同的新令牌对，不判为泄露（多标签页或客户端重试）。
    - 10 秒以注入时钟与被轮换会话的 `used_at` 判定（CONV-04、CONV-27）；IP 前缀与 User-Agent 与子会话的 `ip_prefix`、`user_agent` 比对。
    - 新令牌对按 CONV-19 加密，以旧刷新令牌的哈希为键在 Valkey 中缓存，TTL 10 秒只作为上界（CONV-20 例外，ADR 0017）。
    - 窗口内且指纹一致、但缓存未命中（如 Valkey 丢失数据）时，返回 `invalid_grant`，不签发新令牌，也不吊销会话链；窗口外或指纹不一致时，一律吊销整条会话链。
  - 绝对失效时间保存在 `sessions.absolute_expires_at`：首次登录时写入，轮换时由子会话继承；为空时以 `expires_at` 为准。管理会话的 12 小时绝对失效（AUTH-21）同样写在该列。
- **AUTH-08** 浏览器中的访问令牌与刷新令牌放在 HttpOnly、Secure、SameSite=Strict、Path=/ 的 Cookie 中，响应体不返回令牌（刷新接口对浏览器返回不含令牌的响应，契约为 `CookieTokenRefresh`）；自研客户端把令牌存入系统安全存储。
  - 用户中心使用 `__Host-access_token`、`__Host-refresh_token`；
  - 管理后台使用独立的 `__Host-console_access_token`、`__Host-console_refresh_token`。两个应用可以部署在同一主机、只以路径前缀区分（spec/31 CON-01、spec/40 DEP-02），而 `__Host-` Cookie 必须为 Path=/，同名会互相覆盖。
- **AUTH-09** 登录限流：
  - 同一账号 5 次失败后冷却 15 分钟；同一 IP 每分钟 20 次上限。二次验证失败同样计入账号失败次数。
  - 冷却对不存在的邮箱同样生效，并返回同样的 429 `rate_limited`。
  - 账号不存在时，用固定的虚拟哈希执行一次 argon2id，使两条路径的耗时一致。验收方式：两条路径都恰好调用一次哈希函数。
  - 冷却期间，找回密码流程与已登录的会话不受影响，他人无法借此锁死账号。
- **AUTH-10** 登录时同时注册设备，记录平台、型号、应用版本、设备公钥：
  - `platform='web'`（浏览器中的用户中心）的登录只注册 web 设备，不生成代理凭据，也不计入设备上限。每个账号最多保留 50 个未吊销的 web 设备，超出时吊销最早活跃的一个及其会话。
  - 其他平台的客户端登录时可以带上已有的 `device_id`，并用该设备私钥对 `POST /v1/sessions/nonces` 下发的 nonce 签名（nonce 有效 60 秒，只能使用一次）；验证通过则复用原设备记录与名额，否则注册新设备。签名对象为 UTF-8 字符串 `akari-device-proof-v1|<device_id>|<nonce>`，`device_id` 取小写、带连字符的 UUID 规范写法。
  - 设备公钥为 Ed25519，只用于两件事：重新登录时证明是同一台设备；批准扫码登录时签名（AUTH-24）。两种签名对象以不同前缀区分（域分隔），同一把密钥的签名不能在两种用途之间挪用。刷新令牌不与公钥绑定。
  - 同一账号未吊销的设备，公钥不得重复。
  - 登出（`DELETE /v1/sessions/current`）吊销本会话，并吊销本设备及其代理凭据，释放设备名额。
- **AUTH-24** 新设备登录的另外两种方式：
  - **设备授权**（RFC 8628，用于电视、路由器等）：用户在用户中心的 `/activate` 页面输入 `user_code`，页面调用 `POST /v1/me/device-authorizations` 批准。
  - **扫码登录**：新设备调用 `POST /v1/device-links` 取得二维码与 `poll_token`，已登录设备扫码批准。批准前，批准方界面必须显示请求设备的平台、型号、IP 前缀，所在地区有则显示（未配置 GeoIP 时没有，与 OPS-09 相同），以及一个 2 位校验数字，用户需选出与新设备屏幕上相同的数字，以防钓鱼。非 web 批准方以设备私钥签名，签名对象为 UTF-8 字符串 `akari-device-link-approval-v1|<id>|<check_digits>`。
  
  两种方式中，批准方（已登录的用户中心或设备）都需要 5 分钟内重新验证过（AUTH-23），否则批准接口返回 401 `mfa_required`：批准等于为账号新增一个 90 天有效、不随批准方会话吊销的会话，短期被盗的会话不能借此换成攻击者设备上的长期会话。被批准的新设备登录不算重新验证（AUTH-23），这一条不变。

  两种方式中，新设备都以 `POST /v1/oauth/token`（`grant_type=urn:ietf:params:oauth:grant-type:device_code`；扫码登录时把 `poll_token` 作为 `device_code`）轮询取得令牌。签发的令牌受众只能是 `client`，设备计入设备上限。

## 10.3 二次验证

- **AUTH-11** 支持两种二次验证：
  - TOTP（RFC 6238）：启用时生成 10 个一次性恢复码。同一时间步内已使用过的 TOTP 码拒绝再次使用。恢复码用后立即作废，剩余不足 3 个时发送安全通知。
  - 绑定分两步：开始绑定（返回密钥，需要重新验证，AUTH-23）与确认绑定（提交验证码）。待确认的密钥绑定发起绑定的会话链（同一次登录经刷新轮换产生的会话，AUTH-07），确认必须来自同一会话链；同一账号再次开始绑定时，旧的待确认密钥作废；没有待确认密钥、已过期、已作废或会话链不符时，确认返回 409 `invalid_state`。
  - Passkey（WebAuthn）：可以延后到 M4 实现。
- **AUTH-20** 二次验证登录流程：
  1. 密码正确且账号已启用二次验证时，返回 401 `mfa_required`。problem 附 `challenge_id`（有效 5 分钟）与 `methods`，`methods` 为 `totp`、`passkey`、`recovery_code` 的子集。
  2. 第二步再次调用 `POST /v1/sessions`，提交 `challenge_id` 以及 `totp_code`、`webauthn_assertion`、`recovery_code` 三者之一，不再提交密码。服务端校验 challenge 属于同一账号，并与第一步的设备信息一致。
  3. 每个 challenge 最多尝试 5 次，用完即作废；失败次数同时计入 AUTH-09 的账号失败次数。
- **AUTH-12** 管理员账号必须启用二次验证，否则不能访问管理接口；本次登录也必须完成二次验证（AUTH-21）。
- **AUTH-23** 重新验证（step-up）：以下操作要求 5 分钟内重新验证过密码或二次验证，否则返回 401 `mfa_required`，由客户端完成验证后重试：
  - 修改密码、开始绑定二次验证（TOTP；M4 的 Passkey 注册）、停用二次验证、删除 Passkey、重新生成恢复码；
  - 重置导出令牌；
  - 批准设备授权与批准扫码登录（AUTH-24）；
  - 注销账号。

  以密码完成的 `POST /v1/sessions` 登录（账号启用二次验证时含第二步）视为一次重新验证：会话签发时写入重新验证状态，有效期自登录时刻起 5 分钟（注入的时钟，CONV-04）。设备授权与扫码登录（AUTH-24）签发的会话不写入。刷新令牌轮换只把已有状态连同剩余有效期带到新会话，不新建、不延长。

  账号没有密码（`password_hash` 为空）时，以密码重新验证一律返回 `incorrect`，耗时与校验真实密码相同。

  重新验证场景的 `mfa_required`：`methods` 只列出二次验证方式（密码总是可用，不列入），账号未启用二次验证时为空数组；不附 `challenge_id`，客户端调用 `POST /v1/me/reauthentications` 后重试原请求。Passkey（M4）实现后，需要 WebAuthn challenge 时才附 `challenge_id`。

## 10.4 设备与代理凭据

- **AUTH-13** 每台非 web 设备有一条独立的代理凭据；每个账号另有一条供第三方客户端共用的凭据，在账号创建时生成。凭据值加密存储（CONV-19）。凭据的创建、轮换与吊销都写入 `credential.changed` 事件，由权限协调器下发到节点（spec/11 ACS-02）。
- **AUTH-14** 设备上限：
  - 只统计未吊销的非 web 设备。付费权益的上限取权益快照中的值；免费账号的上限取设置项 `free_device_limit`（默认 1）；启用了免费套餐的，取免费套餐的值。
  - 已达上限时，登录照常成功并返回会话，但不为新设备下发代理凭据：`GET /v1/me/configuration` 返回状态 `device_limit_reached`。用户可以在已登录状态下移除其他设备，移除后新设备会自动获得凭据。
  - 权益变化使已有设备超出上限时，不移除设备记录：按 `last_seen_at` 从近到远，保留上限以内的设备的凭据，其余设备的凭据吊销，直到用户移除设备或上限提高。
- **AUTH-15** 移除设备：吊销其凭据，写入 `credential.changed` 事件，由权限协调器将其从所有节点移除（spec/11 ACS-02）。
- **AUTH-16** 重置导出令牌：
  - 需要重新验证（AUTH-23）。
  - 在同一事务中生成新的导出令牌（同时写 `token_hash` 与 `token_enc`，CONV-20），并轮换该账号的共用凭据，写入 `credential.changed` 事件。
  - 旧链接立即失效；已拿到旧配置的第三方客户端，在节点移除旧共用凭据后无法再连接。
  - 用户中心可以随时读取当前导出链接（`GET /v1/me/export-link`，界面默认遮挡）。

## 10.5 管理员、角色与审计

- **AUTH-17** 权限以字符串表示，格式为 `资源.动作`，资源名使用管理接口的路径名（如 `hosts`，而不是 `nodes`），`资源.*` 表示该资源的全部动作，`*` 表示全部权限。管理接口 OpenAPI 的每个操作以 `x-permission` 声明一个权限，取值只能来自下表，或以下两个特殊值，由 CI 校验；中间件统一校验权限。
  - `none`：只要求管理员已登录（受众为 `console`），用于认证类接口与查看本人信息；
  - `superadmin`：只允许 `superadmin` 角色，不可授予其他角色（例如手动标记支付，AUTH-22）。

| 权限 | 范围 | superadmin | operator | support |
|---|---|---|---|---|
| `accounts.read` | 查看账号、权益、订单概要、设备、最近 7 天用量 | ✓ | ✓ | ✓ |
| `accounts.adjust` | 调整权益、暂停与恢复账号、强制下线、重置用户密码 | ✓ | ✓ | |
| `credits.adjust` | 余额调整 | ✓ | | |
| `orders.read` | 查看订单与支付通知 | ✓ | ✓ | ✓ |
| `orders.refund` | 退款 | ✓ | | |
| `plans.*` | 套餐、价格、应用到现有用户 | ✓ | ✓ | |
| `location-groups.*` | 线路组 | ✓ | ✓ | |
| `hosts.*` | 节点、入站、路由、接入令牌、吊销节点密钥 | ✓ | ✓ | |
| `kernels.write` | 切换节点内核 | ✓ | ✓ | |
| `coupons.*` | 优惠券与兑换码 | ✓ | ✓ | |
| `content.*` | 公告、帮助文档、通知模板 | ✓ | ✓ | |
| `tickets.*` | 工单 | ✓ | | ✓ |
| `payments.configure` | 支付渠道配置 | ✓ | | |
| `settings.read` | 查看系统设置 | ✓ | ✓ | |
| `settings.write` | 修改系统设置 | ✓ | | |
| `staff.*` | 管理员、邀请、角色（保留项：只包含在 superadmin 的 `*` 中，不可授予自定义角色；相关操作的 `x-permission` 为 `superadmin`，AUTH-22） | ✓ | | |
| `audit.read` | 查询与导出审计日志 | ✓ | | |

- **AUTH-22** 角色管理：
  - 三个内置角色不可修改、不可删除。可以创建自定义角色，其权限必须是上表的子集，且不能包含 `*` 与 `staff.*`，否则返回 400，`errors[].code` 为 `not_allowed`。角色可以带可选的描述（`roles.description`）。
  - 管理员、邀请与角色的全部操作（包括只读操作）只允许 `superadmin`，管理接口中这些操作的 `x-permission` 为 `superadmin`。`staff.*` 保留在权限目录中，但只通过 superadmin 的 `*` 持有，因此“不能授予超出自身的权限”对这些操作自然成立。系统中至少保留一个 `superadmin`，移除最后一个时返回 409 `invalid_state`。
  - 删除自定义角色时，内置角色、仍有管理员持有的角色、仍被 `pending` 邀请引用的角色，返回 409 `invalid_state`。
  - 手动标记支付只允许 `superadmin`，任何角色都不能被授予该操作（spec/12 ORD-12）。
  - 账号获得或失去管理员角色时（接受邀请、修改角色、移除管理员），在同一事务中向该账号发送安全类通知（模板 `staff_roles_changed`，spec/13 OPS-04）。
  - 新管理员通过一次性邮件邀请加入，首次登录时必须绑定 TOTP（AUTH-21）。一次邀请可以指定多个角色。
    - 邀请令牌为 32 字节 CSPRNG 随机值（base64url），只存 SHA-256（`staff_invitations.token_hash`，CONV-20）；72 小时有效，`expires_at` 由注入的时钟写入（CONV-27）。
    - 链接为管理后台的公开地址加 `accept-invitation#token=<令牌>`，令牌放在 URL 片段中（与 AUTH-04 相同，不进入访问日志与 Referer）。公开地址取部署配置 `ui.admin.public_url`；未配置时取唯一的 `hosts` 与 `path_prefix`，与找回密码链接的规则相同，不取自请求的 Host。
    - 创建邀请的响应不返回令牌与链接，只通过邮件送达。
    - 邀请邮件为安全类通知（模板 `staff_invitation`，OPS-04），只走邮件渠道，语言取邀请人账号的 `locale`。收件人可能还没有账号：`notification_outbox.staff_invitation_id` 引用邀请，投递时从 `staff_invitations.email` 读取收件地址，outbox 中不保存邮箱（CONV-29）；令牌按 CONV-31 放在 `secret_variables_enc`；最长重试时间等于邀请的有效期（OPS-02）；投递时邀请已不是 `pending`（已接受、已撤销或已过期）的，不再投递，按最终失败处理并清除秘密变量。
    - 被邀请的邮箱已是管理员，或同一邮箱已有 `pending` 邀请时，返回 400 `invalid_request`，`errors[]` 为 `{field: email, code: taken}`；需要重发时先撤销旧邀请。
    - 超级管理员失去 `superadmin` 角色时（修改角色或移除管理员），在同一事务中撤销其发出的全部 `pending` 邀请，每条写一条审计 `staff_invitation.revoke`。
  - 接受邀请（`POST /v1/staff-invitations/acceptance`，请求体 `{token, password?}`）：
    - 令牌不存在、已被接受或已撤销，返回 400，`errors[]` 为 `{field: token, code: invalid_code}`；已过期为 `{field: token, code: expired}`。
    - 邀请行加锁，在同一事务中写 `accepted_at` 与 `account_id`、授予邀请中的全部角色、写审计 `staff.create`，令牌因此只能使用一次。
    - 按被邀请邮箱的账号状态处理：
      1. 没有账号：`password` 必填，缺少时返回 400，`errors[]` 为 `{field: password, code: required}`；密码规则同 AUTH-01。创建账号，邮箱视为已验证（写入 `email_verified_at`），与 AUTH-21 命令行创建管理员一样生成共用代理凭据并在同一事务中写 `credential.changed`。
      2. 账号存在且邮箱已验证：忽略 `password`，沿用原密码。持有邮件中的链接证明当前控制该邮箱；登录管理接口仍需要该账号的密码与 TOTP。
      3. 账号存在但邮箱未验证：`password` 必填（缺少时同第 1 项）；替换密码，删除该账号的 TOTP 与 Passkey（包括待确认的绑定），吊销该账号的全部会话，写入 `email_verified_at`。原因：未验证邮箱的账号可以登录（AUTH-03），可能是他人抢先用该邮箱注册并设置了密码与二次验证；沿用原凭据会让注册者取得管理员身份。
      4. 账号为 `suspended`、`deleting` 或 `deleted`，或已经是管理员：返回 409 `invalid_state`。
- **AUTH-21** 管理员登录与会话：
  - 管理接口只接受受众为 `console` 的访问令牌。这种令牌只能由管理接口域名下的 `POST /v1/sessions` 签发，且本次登录必须完成二次验证（令牌带 `amr` 声明）。客户端接口签发的令牌、设备授权与扫码登录签发的令牌，都不能访问管理接口。
  - 管理会话的刷新令牌自登录起 12 小时绝对失效，空闲 30 分钟失效。
  - 管理员的角色或二次验证设置变化时，吊销其全部管理会话。
  - 首个超级管理员由命令行 `panel admin create --email <邮箱> [--password-stdin]` 创建，首次登录时必须绑定 TOTP：
    - 密码默认在终端提示输入两次，两次不一致时拒绝；带 `--password-stdin` 时从标准输入读取一次，供脚本使用。密码不出现在命令行参数与日志中（CONV-24）。
    - 已存在 `superadmin` 时拒绝执行，其他管理员通过邀请加入（AUTH-22）。
    - 邮箱视为已验证（写入 `email_verified_at`）。
    - 与普通注册一样生成共用代理凭据（AUTH-13），在同一事务中写 `credential.changed`（载荷见 spec/02 CONV-34）与审计日志。
  - 尚未绑定二次验证的管理员登录时，第一步返回的 `mfa_required` 附带 `totp_enrollment`（密钥与 otpauth URI）；第二步提交 TOTP 码即完成绑定与本次验证，并返回恢复码。
- **AUTH-18** 所有管理写操作写入 `audit_logs`，字段为：操作者、动作、对象、变更前后差异、来源 IP 前缀、`request_id`、`reason`（敏感操作必填）。
  - 差异中的 `_enc` 与 `_hash` 字段，以及 `settings` 中以 `_enc` 结尾的键，只记录“已修改”，不记录取值。
  - 审计日志不可修改，只能查询与导出（`/v1/audit-logs/exports`，导出在 backlog M1-02b 实现）。
  - 动作（`action`）与对象类型（`target_type`）的取值见 spec/31 CON-09。
  - 管理员的认证事件（只限受众为 `console`）同样写审计：登录成功 `session.create`、登出 `session.delete`、完成 step-up `step_up.create`、接受邀请 `staff.create`。刷新令牌轮换不写。
  - 登录与 step-up 失败不写审计：只追加表不能清理（CONV-18），未认证的请求写入会成为无限增长的途径；失败时也没有可信的操作者，且不应保存邮箱（CONV-29）。失败计入 AUTH-09 的限流，并记一条 warn 日志，只记 `account_id`（已知时），不记邮箱（CONV-24）。
  - 命令行写入的审计（如 AUTH-21 的 `panel admin create`）没有请求，生成一个 UUIDv7 作为 `request_id`；`actor_id` 为空。
- **AUTH-19** 以下为敏感操作，需要以下三项：
  - 带原因：请求体中的 `reason`；DELETE 操作改用请求头 `Audit-Reason`（spec/31 CON-03）；
  - 请求头带 `Mfa-Assertion`：5 分钟内通过 `POST /v1/staff/me/step-up` 完成一次 TOTP 或 Passkey 验证后得到的短期令牌，缺少或过期返回 401 `mfa_required`；
  - 界面二次确认（spec/32 UI-03）。

  `Mfa-Assertion` 的要求：
  - 由 `POST /v1/staff/me/step-up` 签发，有效期 5 分钟（注入的时钟，CONV-04）；有效期内可以用于多个敏感操作。
  - step-up 只接受 TOTP（M4 起另有 Passkey），恢复码不能用于 step-up；登录时完成的二次验证不签发 `Mfa-Assertion`。
  - 绑定账号与签发时的会话链（AUTH-07）：只在同一账号、同一会话链的请求中有效，会话链被吊销（登出、角色或二次验证变化，AUTH-21）后立即失效。它的受众与访问令牌不同，两者不能互相替代。不写入日志与审计（CONV-24）。
  - 缺少、过期、签名无效或会话链不符，一律返回 401 `mfa_required`：`methods` 只列出 step-up 可用的方式（M1 为 `["totp"]`），不含 `recovery_code`，不附 `challenge_id`。管理后台完成 step-up 后重试原请求（spec/32 UI-09）。
  - 校验顺序：认证 → 权限（403）→ 参数与原因（400）→ `Mfa-Assertion`（401）→ 业务处理。返回 401 之前不产生副作用（CONV-12）。

  敏感操作包括：手动标记支付、余额调整、退款、切换节点内核、修改支付配置、应用到现有用户、从套餐移除线路组、吊销节点密钥、管理员与角色变更、重置用户密码、管理员删除账号、导出审计日志或用户数据（`/v1/audit-logs/exports`、`/v1/accounts/{id}/data-exports`）。执行者还必须拥有该操作对应的权限（AUTH-17）。
- **AUTH-25** 账号暂停（管理员操作）：
  - 吊销该账号的全部会话与代理凭据，登录返回 403 `account_suspended`，写入 `account.status_changed` 事件。
  - 暂停期间权益照常计时，不冻结。
  - 恢复后，用户需重新登录，代理凭据重新生成。
  - 账号暂停与权益暂停（spec/11 的 `suspended` 状态）不同：权益暂停只停止下发凭据，用户仍可登录与查看。两者都必须填写 `reason` 并写审计。
