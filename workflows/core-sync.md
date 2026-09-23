创建并运行一个 workflow，在上游内核同步后验证 `node-agent`。在 `workspace/node-agent/` 中启动。

前提：已按 `core-upgrade` Skill 完成 fork 的 rebase 与 tag，`node-agent/go.mod` 已指向新 tag。

阶段一：矩阵测试（并行，每个组合一个代理，使用快速模型）
- 组合取自 spec/21 的协议矩阵与传输矩阵中标为“稳定”或“实验”的格子；“不支持”的格子跳过。每个组合跑 kernel-conformance Skill 列出的 5 个场景：
  - 增删凭据不影响他人连接；
  - 计量误差为 0；
  - 移除凭据后 1 秒内关闭全部连接；
  - 限速生效；
  - 入站重建后恢复服务。
- 每个代理运行 `make conformance PROTO=<协议> TRANSPORT=<传输> KERNEL=<内核> CASE=<场景>`，返回结构化结果。
- “实验”格子的失败只记录，不阻塞；“稳定”格子的失败必须处理。

阶段二：失败分析（每个失败项一个代理，使用 Opus）
- 阅读上游变更日志与相关提交，判断是上游行为变化还是补丁失效。
- 给出修复补丁或规避方案。

输出：`../review/core-sync-<上游版本>.md`（workspace 的 review 目录），列出通过率、失败项与处理建议；已知差异更新到 `node-agent/internal/kernel/CLAUDE.md`。
