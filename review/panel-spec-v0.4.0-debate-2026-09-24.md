<!-- SPDX-License-Identifier: Apache-2.0 -->

# panel-spec v0.4.0 修订评审（2026-09-24）

背景：M1-01 实现中发现三项契约问题（workspace `backlog/M1.md` 的 M1-01 后续事项）。lead 提出方案，`spec-owner` 代理作为反方评审；lead 核实了反方引用的证据：client v1.yaml 中 `Session` 的令牌字段已为可选、扫码批准签名 `{id}.{check_digits}`，以及 console v1.yaml 中的 `SessionRefresh`。负责人事先同意先辩论再继续。

| # | lead 方案 | 反方意见 | 定案 |
|---|---|---|---|
| 1 | `TokenPair` 的令牌字段改为可选 | 反对：RFC 6749 §5.1 要求 `access_token` 必返回，原生客户端的类型会变弱；登录接口的 `Session` 已经是可选 | `/v1/oauth/token` 的 200 响应改为 `oneOf [TokenPair, CookieTokenRefresh]`，后者只含 `token_type`、`expires_in`、`device_id`，与 console 的 `SessionRefresh` 同理；后端删除空串占位 |
| 2 | `smtp` 增加 `tls`，缺省值待定 | 同意，缺省应要求加密：安全类邮件含秘密值，“有则用”在降级时静默走明文；国内服务商多用 465，必须支持隐式 TLS | `tls` 取 `starttls`（缺省）、`implicit`、`none`。保存时拒绝端口 465 与 `starttls` 的组合、`none` 与用户名的组合；不提供跳过证书校验；`none` 的定位是本机或可信内网中继。反方建议另设键 `smtp_tls`，未采纳：管理接口字段与 settings 键同名（spec/03 3.6），`tls` 放在 `smtp` 对象内 |
| 3 | 签名对象绑定 `device_id` | 同意但改写理由：冒充威胁不成立（查找限定账号、以所声明设备的公钥验签、nonce 一次性）；真正的价值是与扫码批准签名做域分隔 | 设备证明为 `akari-device-proof-v1\|<device_id>\|<nonce>`，扫码批准为 `akari-device-link-approval-v1\|<id>\|<check_digits>`；`device_id` 用小写规范写法；同一账号未吊销设备的公钥不得重复。反对“按设备签发 nonce”（未认证接口会成为设备探测口），采纳 |
| 附 | — | 重新验证场景的 `mfa_required` 是否附 `challenge_id` 应写明 | 不附；`methods` 可为空数组；Passkey 实现后按需附带（spec/10 AUTH-23） |

迁移：第 1、3 条在 1.0 之前按 ENG-04 于 CHANGELOG 说明（自研客户端尚未发布，直接切换）；第 2 条使已有站点从“有则用”变为要求加密，开发环境的 Mailpit 须显式设 `tls: none`。
