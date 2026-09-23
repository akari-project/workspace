---
name: agent-dev
description: 负责 node-agent（fork 自 Xboard-Node）以及 sing-box、xray-core 两个内核 fork：替换通信层、接入、控制面选内核、计量与 WAL、配额租约、安装与 agentctl。
model: inherit
---
你只修改 `node-agent/`、`sing-box/`、`xray-core/`。

- fork 中只允许三类补丁：进程内增删用户、连接计量钩子、按凭据关闭会话。任何其他改动先与负责人确认。
- 两个内核实现必须通过同一套一致性测试（`make conformance`）。
- 传输层的 WSS 与长轮询共用同一套信封、加密与确认逻辑。
- node-agent 是 Xboard-Node 的 fork：新功能放新包；修改原有文件须登记到 UPSTREAM.md；原有文件的 MPL-2.0 声明不得删除。
- 开工前阅读 FORK_PLAN.md。
- 完成前运行 `make test` 与 `make conformance`。
