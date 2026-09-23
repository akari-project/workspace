# 规格索引

本目录是实现的**唯一依据**，只描述当前应当实现的系统，不记录演变过程（历史见 `../adr/`）。

## 阅读规则（给 Claude Code 与贡献者）

1. 先读 `00-glossary.md` 与 `02-conventions.md`，再读与任务相关的文件。每个文件开头的“适用范围”说明它约束哪些仓库和代码目录。
2. 带编号的规则（如 `BIL-03`）是**必须满足**的约束。实现、测试与 PR 描述中引用规则编号。
3. 用词：**必须 / 禁止** 为强制要求；**应** 为默认做法，偏离时须在 PR 中说明理由；**可** 为可选。
4. 规格之间用 `spec/NN` 互相引用（NN 为文件编号）。
5. 规格与代码或契约（proto、OpenAPI、迁移）不一致时：契约文件是字段级事实来源，规格是行为与规则的事实来源。发现冲突时停止实现，先提出规格或契约的修改。
6. 规格没有覆盖的行为，不要自行发明；在 PR 或对话中提出问题。

## 文件

| 编号 | 文件 | 内容 | 主要约束的代码 |
|---|---|---|---|
| 00 | glossary | 术语与标识符对照 | 全部 |
| 01 | architecture | 系统组成、仓库、许可证、数据流 | 全部 |
| 02 | conventions | 标识符、金额、接口、错误码、数据库、事件、日志 | 全部 |
| 03 | data-model | 表与关系概览 | panel/server/migrations |
| 10 | accounts-auth | 账号、会话、设备、二次验证、管理员与权限 | panel/server/internal/auth、account |
| 11 | plans-entitlements | 套餐、价格、权益、折算、到期、节点权限 | internal/billing、internal/access |
| 12 | orders-payments | 报价、订单、开通、支付宝当面付、退款、余额、优惠券、兑换码 | internal/billing、internal/payment |
| 13 | operations | 通知、公告、工单、帮助文档、邀请返利 | internal/notify、content、support、referral |
| 20 | node-protocol | 节点接入、握手、加密、可靠投递、消息 | panel-spec/proto、internal/gateway、node-agent |
| 21 | node-agent | Agent（fork 自 Xboard-Node）、内核选择与协议矩阵 | node-agent、内核 fork |
| 22 | accounting | 流量计量、入账、配额租约、设备数限制、数据保留 | internal/accounting、node-agent |
| 23 | config-export | 第三方客户端配置导出 | internal/export |
| 30 | client-api | `/v1` 客户端接口与命名 | panel-spec/openapi/client、internal/clientapi、client |
| 31 | console-api | 管理接口 | panel-spec/openapi/console、internal/consoleapi |
| 32 | frontend | 用户中心与管理后台页面 | panel/web |
| 40 | deployment | 部署形态、前端内嵌、高可用、故障降级、备份、升级 | panel、node-agent |
| 41 | tech-stack | 技术选型 | 全部 |
| 42 | engineering | CI、测试、指标、发布、治理 | 全部 |
| 43 | claude-code | Claude Code 工作方式与多代理模式 | workspace |

路线图与任务在 `../backlog/`，决策记录在 `../adr/`。

## 按角色的阅读顺序

- **控制面后端**：00 → 02 → 03 → 10 → 11 → 12 → 20 → 22
- **前端**：00 → 02 → 30 → 31 → 32 → 11（只读规则部分）
- **Agent**：00 → 02 → 20 → 21 → 22
- **协议与接口**：00 → 02 → 20 → 30 → 31
