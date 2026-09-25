<!-- SPDX-License-Identifier: Apache-2.0 -->

# `Release.key_id` 格式评审（2026-09-25）

背景：`review/m1-01-followups-debate-2026-09-24.md` 与交接记录中的契约后续：客户端接口 `Release` 示例的 `key_id`（`rel-2026-01`）是否应按 CONV-30 改为十进制字符串。`spec-owner` 先调研，负责人裁定后修改。

## 调研结论

- `Release`（`GET /v1/releases/latest`，按 `ClientPlatform`）是自研客户端的安装包信息，不是 Agent 发布。Agent 升级经节点协议 `AgentUpgrade` 下发，`key_id` 为 `uint32`（panel-spec `messages.proto`，spec/40 DEP-09），不经 REST 接口。
- 修改前，规格没有定义客户端安装包的签名密钥：CONV-30 的签名私钥清单只有访问令牌、`/v1/config` 与 Agent 发布签名；DEP-09 只描述 Agent；spec/41 41.4 的 cosign 用于容器镜像与 SBOM。签名算法与签名输入也未定义。因此 CONV-30 的 `"<key_id>:<base64>"`（1–255 十进制）形式上不约束该字段，按类比才成立。
- 契约中 `Release.signature`、`Release.key_id` 只有 `type: string`；示例 `signature`（`MEUCIQ…`）形似 ECDSA DER 编码，不是 Ed25519 签名（base64 后 88 个字符）。
- panel 没有读取该字段的代码，只有生成代码（`opmeta.gen.go`、`client.gen.ts`）。自研客户端在 1.0 之后。
- oasdiff：为响应字段增加 `pattern` 只产生 info（`response-property-pattern-added`），非破坏性；为已有字段增加 `contentEncoding` 被判为 error（`response-property-content-encoding-changed`），因此不加该关键字，只在描述中写明编码。

## 裁定（负责人）

采纳两步方案，包含模式约束：

1. 规格：CONV-30 增加客户端安装包发布签名：固定 Ed25519 密钥，由发布流程离线保管，不进入控制面的环境变量与数据库；`key_id` 为 1–255 的十进制；客户端内置当前与下一把公钥，与 Agent 发布相同。spec/30 接口表 `GET /v1/releases/latest` 一行引用 CONV-30。签名输入推迟到自研客户端立项，记入 `backlog/M5.md`“1.0 之后（随自研客户端）”。
2. 契约：panel-spec v0.6.1，`Release.key_id` 增加描述与 `SignedConfig.key_id` 相同的模式，示例改为 `'1'`；`Release.signature` 增加描述，示例改为与 Ed25519 签名等长的值；两份 OpenAPI 的 `info.version` 改为 0.6.1。

## 评审后补充（protocol-reviewer 通过，无阻塞问题）

- CONV-30 的存放方式同时更正了 Agent 发布签名：此前清单写“存放方式与主密钥相同”，意味着环境变量，与 DEP-09 的固定密钥由发布流程签名不符；现在两种发布签名都写明离线保管。
- spec/40 DEP-10 的运营者离线备份要求收窄为主密钥与控制面的签名私钥（CONV-30），发布签名密钥由发布流程保管，不由运营者备份。
- 余留：panel-spec `messages.proto` 中 `AgentUpgrade.key_id` 的注释应写明取值 1–255，只改注释，随下一个 panel-spec 版本（`backlog/M1.md` M1-01 后续）。

## 验证

- panel-spec `make ci` 通过：Redocly lint、`buf breaking` 与 oasdiff 对比 v0.6.0 均无破坏性变更，生成代码一致。
