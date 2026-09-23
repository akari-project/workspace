# 决策记录

规格描述“现在应当怎样”，ADR 记录“为什么这样、放弃了什么”。修改已接受的决策时新建 ADR 并把旧的标为已取代。模板：`template.md`。

| 编号 | 标题 | 状态 |
|---|---|---|
| [0001](0001-repos.md) | 四个仓库的划分 | 已接受 |
| [0002](0002-licenses.md) | 许可证 | 已接受 |
| [0003](0003-dual-kernel-agent.md) | Agent 单二进制内嵌双内核，由控制面选择内核 | 已接受（2026-09 修订：内核改由控制面选择；Agent 实现方式见 ADR 0012） |
| [0004](0004-node-transport.md) | 节点通信：WSS + Protobuf + 会话加密 | 已接受 |
| [0005](0005-quota-lease.md) | 配额租约 | 已接受 |
| [0006](0006-entitlement-events-price-lock.md) | 权益：事件记录、参数快照与价格锁定 | 已接受 |
| [0007](0007-expiry-to-free.md) | 到期即回到免费账号，无宽限期 | 已接受 |
| [0008](0008-api-naming.md) | 对外接口命名 | 已接受 |
| [0009](0009-backend-stack.md) | 后端技术栈 | 提议 |
| [0010](0010-frontend-stack.md) | 前端技术栈 | 提议 |
| [0011](0011-plugins.md) | 插件：编译期与进程外两种形式 | 已取代（被 ADR 0015） |
| [0012](0012-fork-xboard-node.md) | node-agent 从 Xboard-Node fork，并改为本项目协议 | 已接受 |
| [0013](0013-control-plane-first.md) | 控制面优先 | 已接受 |
| [0014](0014-client-mihomo.md) | 自研客户端使用 mihomo 内核 | 已接受 |
| [0015](0015-builtin-alipay-f2f.md) | 内置支付宝当面付，取消进程外支付插件 | 已接受（取代 ADR 0011） |
| [0016](0016-embedded-frontends.md) | 前端嵌入控制面二进制 | 已接受 |
