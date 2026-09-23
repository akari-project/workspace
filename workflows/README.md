# Dynamic Workflow 提示词

以下文件是启动 Dynamic Workflow 的提示词。开启 auto mode 后，在下表“启动目录”中打开 Claude Code，粘贴对应文件内容（或说“按 <路径> 创建并运行 workflow”）。worktree 属于具体的 git 仓库，需要独立 worktree 的工作流必须在对应仓库内启动；这类工作流的报告写入 workspace 的 `review/`（spec/43 CC-01）。

先在小范围试跑确认 token 消耗。运行成功的工作流可以保存为项目工作流，供其他贡献者复用；保存位置与命令以当时的 Claude Code 文档为准。

| 文件 | 用途 | 启动目录 | 何时运行 |
|---|---|---|---|
| spec-review.md | 对规格做并行评审与对抗式复核 | `workspace/`（只写 `review/`，不修改 `spec/` 与代码） | M0 开始时；每次大改规格后 |
| billing-adversarial.md | 对折算、价格锁定、状态机构造反例 | `workspace/panel/`（提示词路径 `../workflows/billing-adversarial.md`） | M1 计费完成后；每次改动计费后 |
| core-sync.md | 上游内核同步后的协议矩阵测试 | `workspace/node-agent/` | 每次同步上游 |
| release-audit.md | 发版前全仓审计 | `workspace/`（只写 `review/`，不修改代码） | 每次发版前 |
