---
name: add-opcode
description: 在节点协议中新增一种消息（控制面下发或节点上报）时使用，给出跨三个仓库的检查清单。适合以 Agent Teams 执行。
---
# 新增节点协议消息

## 清单
- [ ] `panel-spec/proto/node/v1/messages.proto` 定义消息；`envelope.proto` 的 `Envelope.body` 增加 oneof 分支（使用未用过的编号）。
- [ ] `Capabilities` 增加布尔能力位；控制面仅在对端声明该能力时发送此消息。
- [ ] 定义幂等语义：同一 `idem_key` 重复收到时的处理结果必须相同。
- [ ] `panel/server/internal/gateway`：发送或接收处理器、单元测试、指标（发送数、失败数、时延）。
- [ ] `node-agent/internal/transport` 与对应业务模块：处理器、单元测试。
- [ ] 旧版 Agent（不声明能力位）与新版控制面组合的测试；新版 Agent 与旧版控制面组合的测试。
- [ ] 端到端测试：正常路径、断线重传、重复投递。
- [ ] `spec/20` 的操作码表更新。

## 建议的团队分工
spec-owner 先完成前三项并通知队友；panel-backend 与 agent-dev 并行实现；e2e-tester 同步编写端到端测试。
