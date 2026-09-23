创建并运行一个 workflow，在上游内核同步后验证 `node-agent`。

前提：已按 `core-upgrade` Skill 完成 fork 的 rebase 与 tag，`node-agent/go.mod` 已指向新 tag。

阶段一：矩阵测试（并行，每个组合一个代理，使用快速模型）
- 组合：7 种协议（vless、vmess、trojan、shadowsocks、hysteria2、tuic、anytls）× 2 个内核 × 3 个场景（增删用户不影响他人连接、计量准确、移除凭据后会话关闭）。
- 每个代理运行 `make conformance PROTO=<协议> KERNEL=<内核> CASE=<场景>` 并返回结构化结果。

阶段二：失败分析（每个失败项一个代理，使用 Opus）
- 阅读上游变更日志与相关提交，判断是上游行为变化还是补丁失效。
- 给出修复补丁或规避方案。

输出：`review/core-sync-<上游版本>.md`，列出通过率、失败项与处理建议；已知差异更新到 `node-agent/internal/kernel/CLAUDE.md`。
